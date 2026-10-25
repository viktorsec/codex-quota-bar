import SwiftUI

struct SettingsView: View {
    let preferences: MenuBarPreferences
    let model: QuotaModel

    var body: some View {
        Form {
            Section {
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

                        Image(nsImage: image(for: panel))
                            .renderingMode(.template)
                            .foregroundStyle(.primary)
                            .frame(width: 84, height: 44)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 56)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Menu Bar")
                    Text("Choose which items appear in your menu bar.")
                        .font(.callout)
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("At least one item must stay on. Hold ⌘ and drag an item within menu bar to reorder.")
            }

            Section {
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
                .padding(.vertical, 4)
            } header: {
                Text("Refresh Interval")
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 700)
    }

    private var refreshIntervalText: String {
        switch preferences.refreshIntervalMinutes {
        case 1: "1 minute"
        case 60: "1 hour"
        default: "\(preferences.refreshIntervalMinutes) minutes"
        }
    }

    private func image(for panel: MenuBarPanel) -> NSImage {
        switch panel {
        case .combined: model.combinedMenuBarImage
        case .weekly: model.weeklyMenuBarImage
        case .fiveHour: model.fiveHourMenuBarImage
        case .resetExpiration: model.resetExpirationMenuBarImage
        }
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
