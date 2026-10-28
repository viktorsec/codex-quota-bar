import AppKit
import SwiftUI

enum QuotaBadge {
    static func styled(_ image: NSImage, style: MenuBarStyle) -> NSImage {
        guard style == .monochrome, !image.isTemplate else { return image }
        // Template rendering uses the badge's alpha mask and lets macOS choose
        // the neutral foreground, including when the menu bar is highlighted.
        let monochrome = image.copy() as! NSImage
        monochrome.isTemplate = true
        return monochrome
    }

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
    }

    private enum Icon {
        case combined, fiveHour, weekly, banked

        var image: NSImage {
            switch self {
            case .combined: NSImage(resource: .menuBarCombined)
            case .fiveHour: NSImage(resource: .menuBarFiveHour)
            case .weekly: NSImage(resource: .menuBarWeekly)
            case .banked: NSImage(resource: .menuBarBanked)
            }
        }
    }

    static func image(window: QuotaWindow?, period: Period, now: Date) -> NSImage {
        let percentage = window.map { "\($0.remainingPercent)%" } ?? "—%"
        let countdown = countdown(until: window?.resetsAt, period: period, now: now)
        let image = badge(topText: percentage, bottomText: countdown,
                          icon: period == .weekly ? .weekly : .fiveHour,
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
        if seconds > 2 * 86_400 { return "\(Int(ceil(seconds / 86_400)))d" }
        if seconds > 2 * 3_600 { return "\(Int(ceil(seconds / 3_600)))h" }
        return "\(Int(ceil(seconds / 60)))m"
    }

    static func combinedImage(window: QuotaWindow?, credits: ResetCredits?, now: Date) -> NSImage {
        let expiration = credits?.nextExpiration(after: now)
        let percentage = window.map { "\($0.remainingPercent)%" } ?? "—%"
        let image = badge(
            topText: percentage,
            bottomText: countdown(until: window?.resetsAt, period: .weekly, now: now),
            icon: .combined,
            urgency: weeklyUrgency(window: window, now: now),
            bankedText: credits?.availableCount == 0 ? nil
                : countdown(until: expiration, period: .weekly, now: now),
            bankedUrgency: expirationUrgency(until: expiration, now: now)
        )
        let quota = window.map { "Weekly quota: \($0.remainingPercent)% remaining." } ?? "Weekly quota unavailable."
        let weeklyDescription = window?.resetsAt.map {
            "Weekly reset: \($0.formatted(date: .abbreviated, time: .shortened))."
        } ?? "Weekly reset unavailable."
        let bankedDescription = expiration.map {
            "Banked reset expiration: \($0.formatted(date: .abbreviated, time: .shortened))."
        } ?? (credits?.availableCount == 0 ? "No banked resets left." : "Banked reset expiration unavailable.")
        image.accessibilityDescription = "\(quota) \(weeklyDescription) \(bankedDescription)"
        return image
    }

    static func resetExpirationImage(credits: ResetCredits?, now: Date) -> NSImage {
        let next = credits?.nextExpiration(after: now)
        let value: String
        let description: String
        if let next {
            value = countdown(until: next, period: .weekly, now: now)
            description = "Next banked reset expires \(next.formatted(date: .abbreviated, time: .shortened))"
        } else if credits?.availableCount == 0 {
            value = "0"
            description = "No banked resets left"
        } else {
            value = "—"
            description = "Banked reset expiration unavailable"
        }
        let image = badge(topText: nil, bottomText: value, icon: .banked,
                          urgency: expirationUrgency(until: next, now: now))
        image.accessibilityDescription = description
        return image
    }

    /// Combined badges color the weekly values and banked countdown independently.
    private static func badge(topText: String?, bottomText: String, icon: Icon,
                              urgency: Urgency? = nil, bankedText: String? = nil,
                              bankedUrgency: Urgency? = nil) -> NSImage {
        // The combined badge needs explicit colors even without warnings so its divider stays gray.
        let usesExplicitColors = urgency != nil || bankedText != nil
        let font = topText == nil
            ? NSFont.menuBarFont(ofSize: 0)
            : NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: urgency?.color ?? (usesExplicitColors ? NSColor.labelColor : .black)
        ]
        let top = topText.map { NSAttributedString(string: $0, attributes: attributes) }
        let bottom = NSMutableAttributedString(string: bottomText, attributes: attributes)
        if let bankedText {
            let neutral = usesExplicitColors ? NSColor.labelColor : .black
            // A plain ticket silhouette stays legible at countdown size.
            let sourceCoupon = NSImage(resource: .menuBarCoupon)
            let coupon = NSImage(size: NSSize(width: 8, height: 6), flipped: false) { bounds in
                sourceCoupon.draw(in: bounds)
                neutral.setFill()
                bounds.fill(using: .sourceAtop)
                return true
            }
            if usesExplicitColors { coupon.cacheMode = .never }
            let attachment = NSTextAttachment()
            attachment.image = coupon
            // Align the silhouette to the visible digit height above the text baseline.
            attachment.bounds = NSRect(x: 0, y: (font.capHeight - coupon.size.height) / 2,
                                       width: coupon.size.width, height: coupon.size.height)
            bottom.append(NSAttributedString(string: "\u{2009}|\u{2009}", attributes: [
                .font: font, .foregroundColor: NSColor.systemGray.withAlphaComponent(0.7)
            ]))
            let couponText = NSMutableAttributedString(attachment: attachment)
            couponText.addAttribute(.font, value: font, range: NSRange(location: 0, length: couponText.length))
            bottom.append(couponText)
            bottom.append(NSAttributedString(string: "\u{2009}", attributes: [
                .font: font, .foregroundColor: neutral
            ]))
            bottom.append(NSAttributedString(string: bankedText, attributes: [
                .font: font, .foregroundColor: bankedUrgency?.color ?? neutral
            ]))
        }
        let textWidth = ceil(max(top?.size().width ?? 0, bottom.size().width))
        // The SVGs include internal padding; a larger canvas gives the glyphs
        // a readable weight beside the two lines of quota values.
        let iconSize: CGFloat = 18
        let textOriginX = iconSize + 5
        let size = NSSize(width: textOriginX + textWidth, height: 22)
        let sourceIcon = icon.image
        // Tint the vector artwork separately so warnings color only the values.
        let neutralIcon = NSImage(size: sourceIcon.size, flipped: false) { bounds in
            sourceIcon.draw(in: bounds)
            (usesExplicitColors ? NSColor.labelColor : .black).setFill()
            bounds.fill(using: .sourceAtop)
            return true
        }
        if usesExplicitColors { neutralIcon.cacheMode = .never }
        let image = NSImage(size: size, flipped: false) { _ in
            neutralIcon.draw(in: NSRect(x: 0, y: (size.height - iconSize) / 2,
                                       width: iconSize, height: iconSize))
            if let top {
                top.draw(at: NSPoint(x: textOriginX + (textWidth - top.size().width) / 2, y: 10))
            }
            let bottomY = top == nil ? (size.height - bottom.size().height) / 2 : 0
            bottom.draw(at: NSPoint(x: textOriginX + (textWidth - bottom.size().width) / 2, y: bottomY))
            return true
        }
        image.isTemplate = !usesExplicitColors
        if usesExplicitColors { image.cacheMode = .never }
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
