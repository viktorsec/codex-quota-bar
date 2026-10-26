import Foundation

/// Compares full server reads only. Notifications can omit credit details or
/// arrive before a redemption's updated balance, so they only trigger a read.
struct QuotaRefillTracker: Codable {
    enum Cause: String, Codable {
        case unexpected, bankedReset, unknown
    }

    struct Event: Identifiable, Codable {
        let id: UUID
        let date: Date
        let titles: [String]
        var cause: Cause

        var message: String {
            let windows = titles.joined(separator: ", ")
            switch cause {
            case .unexpected: return "\(windows) refilled early · no banked reset use detected"
            case .bankedReset: return "\(windows) refilled · banked reset likely used"
            case .unknown: return "\(windows) refilled early · cause unknown"
            }
        }
    }

    struct Reading: Codable {
        let account: String // A fingerprint, never an email or credential.
        let date: Date
        let windows: [QuotaWindow]
        let credits: ResetCredits?
    }

    private struct Pending: Codable {
        let before: Reading
        let firstSeen: Date
        let windowIDs: [String]
        var creditEvidence: CreditEvidence
    }

    private enum CreditEvidence: String, Codable {
        case unchanged, likelyRedeemed, uncertain
    }

    private struct CreditChange: Codable {
        let date: Date
        let evidence: CreditEvidence
    }

    private var previous: Reading?
    private var pending: Pending?
    private var recentCreditChange: CreditChange?
    private(set) var events: [Event] = []
    var needsConfirmation: Bool { pending != nil }

    /// Ten percentage points avoids rounding/reconciliation noise. Confirmation
    /// does not require zero usage: the user may already be spending the refill.
    private static let minimumDrop = 10.0
    static let confirmationDelay = 15.0
    private static let resetMargin = 120.0
    // Span several default polling cycles: a balance update may be observed
    // before quota changes, or arrive well after the confirmation read.
    private static let correlationInterval = 15.0 * 60

    mutating func observe(_ reading: Reading) {
        guard !reading.windows.isEmpty else { return }
        guard let old = previous, old.account == reading.account,
              reading.date >= old.date else {
            self = Self()
            previous = reading
            return
        }
        let transition = Self.creditEvidence(from: old, to: reading)
        // Credit accounting can lag beyond the confirmation read. Correct a
        // recent classification if later evidence points to a user reset.
        if transition != .unchanged {
            for index in events.indices where reading.date.timeIntervalSince(events[index].date) <= Self.correlationInterval {
                if transition == .likelyRedeemed { events[index].cause = .bankedReset }
                else if events[index].cause == .unexpected { events[index].cause = .unknown }
            }
        }
        if transition != .unchanged {
            recentCreditChange = CreditChange(date: reading.date, evidence: transition)
        }
        if let change = recentCreditChange,
           reading.date.timeIntervalSince(change.date) > Self.correlationInterval {
            recentCreditChange = nil
        }

        if var candidate = pending {
            candidate.creditEvidence = Self.combine(candidate.creditEvidence, transition)
            candidate.creditEvidence = Self.combine(candidate.creditEvidence,
                Self.creditEvidence(from: candidate.before, to: reading))
            pending = candidate
            if reading.date.timeIntervalSince(candidate.firstSeen) >= Self.confirmationDelay {
                let confirmed = reading.windows.filter { window in
                    candidate.windowIDs.contains(window.id) && Self.isEarlyRefill(
                        window, before: candidate.before, at: reading.date)
                }
                if !confirmed.isEmpty {
                    let cause: Cause
                    switch candidate.creditEvidence {
                    case .likelyRedeemed: cause = .bankedReset
                    case .uncertain: cause = .unknown
                    case .unchanged: cause = .unexpected
                    }
                    events.insert(Event(id: UUID(), date: candidate.firstSeen,
                                        titles: confirmed.map(\.title), cause: cause), at: 0)
                    events = Array(events.prefix(5))
                }
                pending = nil
            }
        } else {
            let refilled = reading.windows.filter { Self.isEarlyRefill($0, before: old, at: reading.date) }
            if !refilled.isEmpty {
                var evidence = transition
                if let recentCreditChange {
                    evidence = Self.combine(evidence, recentCreditChange.evidence)
                }
                pending = Pending(before: old, firstSeen: reading.date,
                                  windowIDs: refilled.map(\.id), creditEvidence: evidence)
            }
        }
        previous = reading
    }

    private static func isEarlyRefill(_ window: QuotaWindow, before: Reading, at date: Date) -> Bool {
        guard let old = before.windows.first(where: { $0.id == window.id }),
              old.windowDurationMins == window.windowDurationMins,
              old.planType == window.planType,
              let reset = old.resetsAt, reset.timeIntervalSince(date) > resetMargin else { return false }
        return old.usedPercent - window.usedPercent >= minimumDrop
    }

    private static func combine(_ lhs: CreditEvidence, _ rhs: CreditEvidence) -> CreditEvidence {
        if lhs == .likelyRedeemed || rhs == .likelyRedeemed { return .likelyRedeemed }
        if lhs == .uncertain || rhs == .uncertain { return .uncertain }
        return .unchanged
    }

    private static func creditEvidence(from before: Reading, to after: Reading) -> CreditEvidence {
        guard let old = before.credits, let new = after.credits else { return .uncertain }
        let newIDs = Set(new.credits.map(\.id))
        let missing = old.credits.filter { !newIDs.contains($0.id) }
        let possiblyExpired = old.credits.filter {
            guard let expiry = $0.expiresAt else { return false }
            return expiry <= after.date.addingTimeInterval(resetMargin)
        }
        // Counts are authoritative even if the service caps the detail rows.
        if old.availableCount - new.availableCount > possiblyExpired.count,
           old.credits.count == old.availableCount {
            return .likelyRedeemed
        }
        // An unexpired ID disappearing is evidence even if a newly granted
        // credit hides the redemption in the total count. Only trust absence
        // when the new list is complete.
        if new.credits.count == new.availableCount,
           missing.contains(where: { credit in
               credit.expiresAt.map { $0 > after.date.addingTimeInterval(resetMargin) } ?? true
           }) {
            return .likelyRedeemed
        }
        let complete = Set(old.credits.map(\.id)).count == old.availableCount &&
            newIDs.count == new.availableCount
        guard complete, old.availableCount == new.availableCount,
              Set(old.credits.map(\.id)) == newIDs, possiblyExpired.isEmpty,
              after.date.timeIntervalSince(before.date) <= 15 * 60 else { return .uncertain }
        return .unchanged
    }
}

/// One bounded snapshot plus five events. No tokens or raw account identifiers.
@MainActor
final class QuotaRefillStore {
    private let defaults: UserDefaults
    private let key = "quotaRefillTracking.v1"
    private(set) var tracker: QuotaRefillTracker

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            do { tracker = try JSONDecoder().decode(QuotaRefillTracker.self, from: data) }
            catch {
                // Tracking is advisory; an incompatible/corrupt baseline must
                // start fresh rather than block quota display or claim a refill.
                tracker = QuotaRefillTracker()
                defaults.removeObject(forKey: key)
            }
        } else { tracker = QuotaRefillTracker() }
    }

    func observe(_ reading: QuotaRefillTracker.Reading) {
        tracker.observe(reading)
        do { defaults.set(try JSONEncoder().encode(tracker), forKey: key) }
        catch { defaults.removeObject(forKey: key) }
    }

    func clear() {
        tracker = QuotaRefillTracker()
        defaults.removeObject(forKey: key)
    }
}
