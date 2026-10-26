#if DEBUG
import Foundation

/// Deterministic fixtures: no network, credentials, sleeps, or production defaults.
@MainActor
enum QuotaRefillCheck {
    static func run() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let a = ResetCredits.Credit(id: "a", expiresAt: now.addingTimeInterval(86_400))
        let b = ResetCredits.Credit(id: "b", expiresAt: now.addingTimeInterval(172_800))
        let empty = ResetCredits(availableCount: 0, credits: [])
        let bank = ResetCredits(availableCount: 1, credits: [a])
        func reading(_ seconds: Double, used: Double = 80, credits: ResetCredits? = nil,
                     reset: Double = 3 * 86_400, account: String = "account", plan: String? = "pro") -> QuotaRefillTracker.Reading {
            .init(account: account, date: now.addingTimeInterval(seconds), windows: [
                .init(id: "codex.secondary", title: "Weekly", usedPercent: used,
                      resetsAt: now.addingTimeInterval(reset), windowDurationMins: 10_080, planType: plan)
            ], credits: credits)
        }
        func classify(_ old: ResetCredits?, _ new: ResetCredits?,
                      confirmed: ResetCredits? = nil, interval: Double = 60) -> QuotaRefillTracker.Cause? {
            var tracker = QuotaRefillTracker()
            tracker.observe(reading(0, credits: old))
            tracker.observe(reading(interval, used: 2, credits: new))
            tracker.observe(reading(interval + 20, used: 3, credits: confirmed ?? new))
            return tracker.events.first?.cause
        }
        try require(classify(bank, bank) == .unexpected, "Retained banked ID permits early-refill detection")
        try require(classify(empty, empty) == .unexpected, "Zero banked resets permits early-refill detection")
        try require(classify(bank, empty) == .bankedReset, "Consumed banked reset suppresses unexpected classification")
        try require(classify(bank, bank, confirmed: empty) == .bankedReset, "Delayed credit decrement is caught at confirmation")
        let replaced = ResetCredits(availableCount: 1, credits: [b])
        try require(classify(bank, replaced) == .bankedReset, "Replacement credit cannot hide redemption behind unchanged count")
        let granted = ResetCredits(availableCount: 2, credits: [a, b])
        try require(classify(bank, granted) == .unknown, "Grant during refill leaves cause uncertain")
        let countOnly = ResetCredits(availableCount: 1, credits: [])
        try require(classify(countOnly, countOnly) == .unknown, "Count-only bank cannot rule out grant plus redemption")
        try require(classify(bank, nil) == .unknown, "Missing credit balance cannot claim unexpected refill")
        try require(classify(nil, empty) == .unknown, "Missing prior balance cannot claim unexpected refill")
        let expired = ResetCredits(availableCount: 1, credits: [
            .init(id: "expired", expiresAt: now.addingTimeInterval(30))
        ])
        try require(classify(expired, empty) == .unknown, "Expiration could also hide redemption before expiry")
        let unknownExpiry = ResetCredits(availableCount: 1, credits: [.init(id: "a", expiresAt: nil)])
        try require(classify(unknownExpiry, empty) == .bankedReset, "Missing expiration does not excuse disappearing ID")
        let truncatedNew = ResetCredits(availableCount: 2, credits: [b])
        try require(classify(bank, truncatedNew) == .unknown, "Truncated rows do not prove an ID disappeared")
        try require(classify(bank, bank, interval: 3_600) == .unknown, "Long offline gap is uncertain")
        print("PASS: banked reset counts, IDs, grants, expirations, missing/truncated data, and delayed redemption")

        var tracker = QuotaRefillTracker()
        tracker.observe(reading(0, credits: bank))
        tracker.observe(reading(60, used: 2, credits: bank))
        try require(tracker.needsConfirmation && tracker.events.isEmpty, "First refill reading requires confirmation")
        tracker.observe(reading(61, used: 2, credits: bank))
        try require(tracker.events.isEmpty, "Back-to-back responses do not count as confirmation")
        tracker.observe(reading(80, used: 3, credits: bank))
        tracker.observe(reading(100, used: 4, credits: bank))
        try require(tracker.events.count == 1 && !tracker.needsConfirmation, "Confirmed refill is recorded once")
        tracker.observe(reading(110, used: 4, credits: empty))
        try require(tracker.events.first?.cause == .bankedReset, "Late redemption corrects a recent refill classification")

        tracker = QuotaRefillTracker()
        tracker.observe(reading(0, credits: bank))
        tracker.observe(reading(60, used: 2, credits: bank))
        tracker.observe(reading(80, used: 80, credits: bank))
        try require(tracker.events.isEmpty, "Transient stale usage reading is discarded")

        for changed in [reading(60, used: 2, credits: bank, account: "other"),
                        reading(60, used: 2, credits: bank, plan: "plus"),
                        reading(60, used: 75, credits: bank)] {
            tracker = QuotaRefillTracker()
            tracker.observe(reading(0, credits: bank))
            tracker.observe(changed)
            try require(!tracker.needsConfirmation, "Account/plan changes and small corrections do not trigger refill")
        }
        tracker = QuotaRefillTracker()
        tracker.observe(reading(0, credits: bank, reset: 60))
        tracker.observe(reading(65, used: 2, credits: bank))
        try require(!tracker.needsConfirmation, "Scheduled reset uses the old deadline")
        tracker = QuotaRefillTracker()
        tracker.observe(reading(0, credits: bank))
        tracker.observe(reading(60, used: 2, credits: bank))
        tracker.observe(reading(4 * 86_400, used: 2, credits: bank))
        try require(tracker.events.isEmpty, "Offline confirmation after the old deadline is discarded")

        tracker = QuotaRefillTracker()
        tracker.observe(reading(0, credits: bank))
        tracker.observe(reading(30, credits: empty))
        tracker.observe(reading(60, used: 2, credits: empty))
        tracker.observe(reading(80, used: 2, credits: empty))
        try require(tracker.events.first?.cause == .bankedReset, "Credit decrement arriving before quota is correlated")
        tracker = QuotaRefillTracker()
        tracker.observe(reading(0, credits: bank))
        tracker.observe(reading(30, credits: empty))
        tracker.observe(reading(330, used: 2, credits: empty))
        tracker.observe(reading(350, used: 2, credits: empty))
        try require(tracker.events.first?.cause == .bankedReset, "Redemption correlation spans a default polling cycle")
        print("PASS: confirmation, deduplication, stale readings, account/plan changes, scheduled resets, and event ordering")

        let suite = "UseYourTokens.RefillCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QuotaRefillStore(defaults: defaults)
        store.observe(reading(0, credits: bank))
        store.observe(reading(60, used: 2, credits: bank))
        let restored = QuotaRefillStore(defaults: defaults)
        try require(restored.tracker.needsConfirmation, "Pending refill survives restart")
        restored.observe(reading(80, used: 2, credits: empty))
        try require(restored.tracker.events.first?.cause == .bankedReset, "Restart preserves pre-refill banked balance")
        try require(QuotaRefillStore(defaults: defaults).tracker.events.count == 1, "History survives restart")
        restored.clear()
        try require(QuotaRefillStore(defaults: defaults).tracker.events.isEmpty, "Sign-out clears tracking")
        defaults.set(Data("broken".utf8), forKey: "quotaRefillTracking.v1")
        try require(QuotaRefillStore(defaults: defaults).tracker.events.isEmpty, "Corrupt baseline safely starts fresh")
        print("PASS: persisted baseline, pending confirmation, credit history, sign-out cleanup, and corrupt storage recovery")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw CheckError.failed(message) }
    }
    private enum CheckError: LocalizedError {
        case failed(String)
        var errorDescription: String? { switch self { case .failed(let message): message } }
    }
}
#endif
