import AppKit
import SwiftUI

enum QuotaBadge {
    enum Period {
        case weekly, fiveHour

        var title: String { self == .weekly ? "Weekly" : "5-hour" }
        var symbol: String { self == .weekly ? "gauge.medium" : "clock" }
    }

    static func image(window: QuotaWindow?, period: Period, now: Date) -> NSImage {
        let percentage = window.map { "\($0.remainingPercent)%" } ?? "—%"
        let countdown = countdown(until: window?.resetsAt, period: period, now: now)
        let image = badge(topText: percentage, bottomText: countdown, symbol: period.symbol)
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
            symbol: "gauge.medium"
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
        let image = badge(topText: top, bottomText: bottom, symbol: "hourglass")
        image.accessibilityDescription = description
        return image
    }

    /// A template image keeps both rows aligned and adapts to the menu bar appearance.
    private static func badge(topText: String, bottomText: String, symbol: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.black
        ]
        let top = NSAttributedString(string: topText, attributes: attributes)
        let bottom = NSAttributedString(string: bottomText, attributes: attributes)
        let textWidth = ceil(max(top.size().width, bottom.size().width))
        let size = NSSize(width: 19 + textWidth, height: 22)
        let image = NSImage(size: size, flipped: false) { _ in
            let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            icon?.draw(in: NSRect(x: 0, y: 4, width: 14, height: 14))
            top.draw(at: NSPoint(x: 19 + (textWidth - top.size().width) / 2, y: 10))
            bottom.draw(at: NSPoint(x: 19 + (textWidth - bottom.size().width) / 2, y: 0))
            return true
        }
        image.isTemplate = true
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
