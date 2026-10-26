import SwiftUI

struct SettingsView: View {
    let preferences: MenuBarPreferences
    let model: QuotaModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                menuBarSection
                styleSection
                refreshSection
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 600, height: 700)
    }

    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Menu Bar")
                    .fontWeight(.semibold)
                Text("Choose which items appear in your menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)

            VStack(spacing: 0) {
                ForEach(MenuBarPanel.allCases, id: \.self) { panel in
                    HStack(alignment: .center, spacing: 16) {
                        Toggle(panel.title, isOn: Binding(
                            get: { preferences.isEnabled(panel) },
                            set: { preferences.setEnabled($0, for: panel) }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .controlSize(.large)
                        .fixedSize()
                        .scaleEffect(1.4)
                        .frame(width: 32, height: 32)
                        .disabled(!preferences.canToggle(panel))

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(panel.title)
                                    .fontWeight(.medium)
                                if panel.includesBankedResets {
                                    BankedResetsHelpButton()
                                }
                            }
                            Text(description(for: panel))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        MenuBarItemPreview(image: image(for: panel), showsBothAppearances: false, scale: 1.5)
                    }
                    .frame(minHeight: 56)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    if panel != MenuBarPanel.allCases.last {
                        Divider()
                    }
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            Text("At least one item must stay on. Hold ⌘ and drag an item within menu bar to reorder.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Style")
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
            HStack(spacing: 12) {
                ForEach(MenuBarStyle.allCases, id: \.self) { style in
                    StyleOptionButton(style: style, isSelected: preferences.style == style) {
                        preferences.setStyle(style)
                    }
                }
            }
            Text("Warmer colors mean less time to use what’s left.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
        }
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Refresh Interval")
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fetch quota every")
                    Spacer()
                    Text(refreshIntervalText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: {
                        Double(MenuBarPreferences.refreshIntervals.firstIndex(of: preferences.refreshIntervalMinutes) ?? 0)
                    },
                    set: { preferences.setRefreshIntervalMinutes(MenuBarPreferences.refreshIntervals[Int($0)]) }
                ), in: 0...Double(MenuBarPreferences.refreshIntervals.count - 1), step: 1) {
                    Text("Refresh interval")
                } minimumValueLabel: {
                    Text("1 min")
                } maximumValueLabel: {
                    Text("1 hour")
                }
                .labelsHidden()
                .accessibilityValue("Every \(refreshIntervalText)")
            }
            .padding(14)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var refreshIntervalText: String {
        switch preferences.refreshIntervalMinutes {
        case 1: "1 minute"
        case 60: "1 hour"
        default: "\(preferences.refreshIntervalMinutes) minutes"
        }
    }

    private func image(for panel: MenuBarPanel) -> NSImage {
        let image: NSImage = switch panel {
        case .combined: model.combinedMenuBarImage
        case .weekly: model.weeklyMenuBarImage
        case .fiveHour: model.fiveHourMenuBarImage
        case .resetExpiration: model.resetExpirationMenuBarImage
        }
        return QuotaBadge.styled(image, style: preferences.style)
    }

    private func description(for panel: MenuBarPanel) -> String {
        switch panel {
        case .combined:
            "Weekly quota remaining, with time until the weekly reset or a banked reset expires—whichever comes first."
        case .weekly:
            "Weekly quota remaining, with time until the weekly reset."
        case .fiveHour:
            "5-hour quota remaining, with hours and minutes until it resets."
        case .resetExpiration:
            "Time until your next banked reset expires."
        }
    }
}

private struct StyleOptionButton: View {
    let style: MenuBarStyle
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false
    @State private var previewStep = 0

    // Frame zero is also the static preview, so hovering never changes it immediately.
    // Vary only time at 80% quota, showing the actual weekly colors.
    private static let frames: [(remaining: Int, days: Double)] = [
        (80, 3), (80, 2), (80, 1), (80, 6), (80, 5), (80, 4)
    ]

    var body: some View {
        Button(action: select) {
            VStack(spacing: 10) {
                MenuBarItemPreview(image: previewImage)
                Text(style.title)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover {
            previewStep = 0
            isHovered = $0
        }
        .task(id: isHovered) {
            guard isHovered else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(750)) }
                catch { return }
                previewStep = (previewStep + 1) % Self.frames.count
            }
        }
    }

    private var previewImage: NSImage {
        let frame = Self.frames[isHovered ? previewStep : 0]
        let now = Date.now
        let window = QuotaWindow(id: "style-preview", title: "Weekly", usedPercent: Double(100 - frame.remaining),
                                 resetsAt: now.addingTimeInterval(frame.days * 86_400), windowDurationMins: 10_080)
        return QuotaBadge.styled(QuotaBadge.image(window: window, period: .weekly, now: now), style: style)
    }
}

private struct BankedResetsHelpButton: View {
    @State private var isPresented = false

    var body: some View {
        Button("About Banked resets", systemImage: "questionmark.circle") {
            isPresented.toggle()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .frame(width: 24, height: 24)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Banked resets")
                    .font(.headline)
                Text(MenuBarPanel.bankedResetsExplanation)
            }
            .font(.callout)
            .padding(20)
            .frame(width: 340)
        }
    }
}
