import AppKit
import SwiftUI

enum QuotaBadge {
    enum Urgency: Int {
        case yellow, orange, red

        var color: NSColor {
            NSColor(name: nil) { appearance in
                if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                    switch self {
                    case .yellow: return .systemYellow
                    case .orange: return .systemOrange
                    case .red: return .systemRed
                    }
                }
                // Darker shades keep the tiny values readable on light backgrounds.
                switch self {
                case .yellow: return NSColor(srgbRed: 0.58, green: 0.43, blue: 0, alpha: 1)
                case .orange: return NSColor(srgbRed: 0.72, green: 0.30, blue: 0, alpha: 1)
                case .red: return NSColor(srgbRed: 0.78, green: 0.10, blue: 0.08, alpha: 1)
                }
            }
        }
    }

    static func expirationUrgency(until expiration: Date?, now: Date) -> Urgency? {
        // A Banked reset represents a full reset opportunity: 100 / days left.
        // Normal > 5 days; yellow <= 5 days; orange <= 4 days; red <= 60 hours.
        quotaUrgency(remainingPercent: 100, until: expiration, now: now)
    }

    static func combinedUrgency(window: QuotaWindow?, credits: ResetCredits?, now: Date) -> Urgency? {
        let next = combinedResetDate(window: window, credits: credits, now: now)
        let expiration = credits?.nextExpiration(after: now)
        let bankedUrgency = next == expiration ? expirationUrgency(until: expiration, now: now) : nil
        // Both values share the strongest applicable warning; the icon stays neutral.
        return [weeklyUrgency(window: window, now: now), bankedUrgency]
            .compactMap { $0 }.max { $0.rawValue < $1.rawValue }
    }

    static func weeklyUrgency(window: QuotaWindow?, now: Date) -> Urgency? {
        guard let window, window.remainingPercent > 10 else { return nil }
        return quotaUrgency(remainingPercent: window.remainingPercent, until: window.resetsAt, now: now)
    }

    static func fiveHourUrgency(window: QuotaWindow?, now: Date) -> Urgency? {
        guard let window, window.remainingPercent > 10 else { return nil }
        // Scale weekly's 7-day cycle to 5 hours: final 5/7 of the window,
        // yellow/orange/red at 28/35/56 percentage points per hour.
        // Quota left | 3 hours | 2 hours | 1 hour
        //        80% | Normal  | Orange  | Red
        //        40% | Normal  | Normal  | Orange
        //        10% | Normal  | Normal  | Normal
        return quotaUrgency(remainingPercent: window.remainingPercent, until: window.resetsAt,
                            now: now, cycleDuration: 5 * 3_600)
    }

    private static func quotaUrgency(remainingPercent: Int, until reset: Date?, now: Date,
                                     cycleDuration: Double = 7 * 86_400) -> Urgency? {
        guard let reset else { return nil }
        // Express time in equivalent weekly days so every period shares thresholds.
        let days = reset.timeIntervalSince(now) * 7 / cycleDuration
        guard days > 0, days <= 5 else { return nil }
        let pointsPerDay = Double(remainingPercent) / days
        if pointsPerDay >= 40 { return .red }
        if pointsPerDay >= 25 { return .orange }
        if pointsPerDay >= 20 { return .yellow }
        return nil
    }

    enum Period {
        case weekly, fiveHour

        var title: String { self == .weekly ? "Weekly" : "5-hour" }
        var symbol: String { self == .weekly ? "gauge.medium" : "clock" }
    }

    static func image(window: QuotaWindow?, period: Period, now: Date) -> NSImage {
        let percentage = window.map { "\($0.remainingPercent)%" } ?? "—%"
        let countdown = countdown(until: window?.resetsAt, period: period, now: now)
        let image = badge(topText: percentage, bottomText: countdown, symbol: period.symbol,
                          urgency: period == .weekly ? weeklyUrgency(window: window, now: now)
                              : fiveHourUrgency(window: window, now: now))
        image.accessibilityDescription = window.map {
            "\(period.title) quota: \($0.remainingPercent)% remaining. Reset countdown: \(countdown)."
        } ?? "\(period.title) quota unavailable"
        return image
    }

    static func countdown(until reset: Date?, period: Period, now: Date) -> String {
        guard let reset else { return period == .fiveHour ? "--:--" : "—" }
        let seconds = reset.timeIntervalSince(now)
        if period == .fiveHour {
            let minutes = Int(ceil(max(0, seconds) / 60))
            return String(format: "%02d:%02d", minutes / 60, minutes % 60)
        }
        if seconds <= 0 { return "Now" }
        if seconds >= 86_400 { return "\(Int(seconds / 86_400))d" }
        if seconds >= 3_600 { return "\(Int(seconds / 3_600))h" }
        return "\(Int(ceil(seconds / 60)))m"
    }

    static func combinedResetDate(window: QuotaWindow?, credits: ResetCredits?, now: Date) -> Date? {
        [window?.resetsAt, credits?.nextExpiration(after: now)].compactMap { $0 }.min()
    }

    static func combinedImage(window: QuotaWindow?, credits: ResetCredits?, now: Date) -> NSImage {
        let next = combinedResetDate(window: window, credits: credits, now: now)
        let percentage = window.map { "\($0.remainingPercent)%" } ?? "—%"
        let image = badge(
            topText: percentage,
            bottomText: countdown(until: next, period: .weekly, now: now),
            symbol: "gauge.medium",
            urgency: combinedUrgency(window: window, credits: credits, now: now)
        )
        let quota = window.map { "Weekly quota: \($0.remainingPercent)% remaining." } ?? "Weekly quota unavailable."
        if let next {
            let event = next == window?.resetsAt ? "Weekly reset" : "Banked reset expiration"
            image.accessibilityDescription = "\(quota) \(event): \(next.formatted(date: .abbreviated, time: .shortened))."
        } else {
            image.accessibilityDescription = "\(quota) Weekly reset and banked reset expiration unavailable."
        }
        return image
    }

    static func resetExpirationImage(credits: ResetCredits?, now: Date) -> NSImage {
        let next = credits?.nextExpiration(after: now)
        let top: String
        let bottom: String
        let description: String
        if let next {
            top = "Banked"
            bottom = countdown(until: next, period: .weekly, now: now)
            description = "Next banked reset expires \(next.formatted(date: .abbreviated, time: .shortened))"
        } else if credits?.availableCount == 0 {
            top = "No banked"
            bottom = "resets"
            description = "No banked resets left"
        } else {
            top = "Banked"
            bottom = "—"
            description = "Banked reset expiration unavailable"
        }
        let image = badge(topText: top, bottomText: bottom, symbol: "hourglass",
                          urgency: expirationUrgency(until: next, now: now))
        image.accessibilityDescription = description
        return image
    }

    /// Normal badges use templates; urgent badges color both values together.
    private static func badge(topText: String, bottomText: String, symbol: String,
                              urgency: Urgency? = nil) -> NSImage {
        let hasColor = urgency != nil
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: urgency?.color ?? NSColor.black
        ]
        let top = NSAttributedString(string: topText, attributes: attributes)
        let bottom = NSAttributedString(string: bottomText, attributes: attributes)
        let textWidth = ceil(max(top.size().width, bottom.size().width))
        let size = NSSize(width: 19 + textWidth, height: 22)
        let image = NSImage(size: size, flipped: false) { _ in
            var icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            if hasColor {
                icon = icon?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
            }
            icon?.draw(in: NSRect(x: 0, y: 4, width: 14, height: 14))
            top.draw(at: NSPoint(x: 19 + (textWidth - top.size().width) / 2, y: 10))
            bottom.draw(at: NSPoint(x: 19 + (textWidth - bottom.size().width) / 2, y: 0))
            return true
        }
        image.isTemplate = !hasColor
        if hasColor { image.cacheMode = .never }
        return image
    }
}

#Preview {
    Image(nsImage: QuotaBadge.image(window: QuotaWindow(
        id: "codex.secondary", title: "Weekly", usedPercent: 24,
        resetsAt: .now.addingTimeInterval(3 * 86_400), windowDurationMins: 10_080
    ), period: .weekly, now: .now))
    .padding()
}
