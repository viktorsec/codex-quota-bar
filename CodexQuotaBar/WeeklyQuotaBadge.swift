import AppKit
import SwiftUI

enum WeeklyQuotaBadge {
    static func image(window: QuotaWindow?, now: Date) -> NSImage {
        let percentage = window.map { "\($0.remainingPercent)%" } ?? "—%"
        let countdown = countdown(until: window?.resetsAt, now: now)
        let image = badge(percentage: percentage, countdown: countdown)
        image.accessibilityDescription = window.map {
            "Weekly quota: \($0.remainingPercent)% remaining. Reset: \(countdown)."
        } ?? "Weekly quota unavailable"
        return image
    }

    static func countdown(until reset: Date?, now: Date) -> String {
        guard let reset else { return "—" }
        let seconds = reset.timeIntervalSince(now)
        if seconds <= 0 { return "Now" }
        if seconds >= 86_400 { return "\(Int(seconds / 86_400))d" }
        if seconds >= 3_600 { return "\(Int(seconds / 3_600))h" }
        return "\(Int(ceil(seconds / 60)))m"
    }

    /// A single template image preserves both rows in MenuBarExtra, whose label
    /// otherwise adapts text and image content to a standard one-line button.
    private static func badge(percentage: String, countdown: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.black
        ]
        let top = NSAttributedString(string: percentage, attributes: attributes)
        let bottom = NSAttributedString(string: countdown, attributes: attributes)
        let textWidth = ceil(max(top.size().width, bottom.size().width))
        let size = NSSize(width: 19 + textWidth, height: 22)
        let image = NSImage(size: size, flipped: false) { _ in
            let icon = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: nil)
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
    Image(nsImage: WeeklyQuotaBadge.image(window: QuotaWindow(
        id: "codex.secondary", title: "Weekly", usedPercent: 24,
        resetsAt: .now.addingTimeInterval(3 * 86_400), windowDurationMins: 10_080
    ), now: .now))
    .padding()
}
