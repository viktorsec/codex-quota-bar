import Foundation
import Observation

/// Temporary display inputs. Never replaces or persists live account data.
@Observable
@MainActor
final class QuotaSimulation {
    @Observable
    @MainActor
    final class BankedReset: Identifiable {
        let id = UUID()
        var expiresAt: Date { didSet { onChange?() } }
        @ObservationIgnored var onChange: (() -> Void)?

        init(expiresAt: Date) { self.expiresAt = expiresAt }
    }

    var weeklyRemainingPercent: Double { didSet { onChange?() } }
    var weeklyResetsAt: Date { didSet { onChange?() } }
    var fiveHourRemainingPercent: Double { didSet { onChange?() } }
    var fiveHourResetsAt: Date { didSet { onChange?() } }
    var bankedResets: [BankedReset] {
        didSet {
            observeBankedResets()
            onChange?()
        }
    }
    @ObservationIgnored var onChange: (() -> Void)?

    init(weekly: QuotaWindow?, fiveHour: QuotaWindow?, credits: ResetCredits?, now: Date = .now) {
        weeklyRemainingPercent = Double(weekly?.remainingPercent ?? 75)
        weeklyResetsAt = weekly?.resetsAt ?? now.addingTimeInterval(3 * 86_400)
        fiveHourRemainingPercent = Double(fiveHour?.remainingPercent ?? 50)
        fiveHourResetsAt = fiveHour?.resetsAt ?? now.addingTimeInterval(3 * 3_600)
        bankedResets = (0..<min(20, credits?.availableCount ?? 0)).map { index in
            let expiration = credits?.credits.indices.contains(index) == true
                ? credits?.credits[index].expiresAt : nil
            return BankedReset(expiresAt: expiration ?? now.addingTimeInterval(86_400))
        }
        observeBankedResets()
    }

    private func observeBankedResets() {
        for reset in bankedResets {
            reset.onChange = { [weak self] in self?.onChange?() }
        }
    }

    var weeklyWindow: QuotaWindow {
        QuotaWindow(id: "simulation.weekly", title: "Weekly", usedPercent: 100 - weeklyRemainingPercent,
                    resetsAt: weeklyResetsAt, windowDurationMins: 10_080)
    }

    var fiveHourWindow: QuotaWindow {
        QuotaWindow(id: "simulation.fiveHour", title: "5-hour", usedPercent: 100 - fiveHourRemainingPercent,
                    resetsAt: fiveHourResetsAt, windowDurationMins: 300)
    }

    var resetCredits: ResetCredits {
        ResetCredits(availableCount: bankedResets.count, credits: bankedResets.map {
            .init(id: $0.id.uuidString, expiresAt: $0.expiresAt)
        })
    }
}
