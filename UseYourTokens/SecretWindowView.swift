import SwiftUI

struct SecretWindowView: View {
    let model: QuotaModel

    private var globalResetCandidates: [QuotaRefillTracker.Event] {
        model.refillEvents.filter { $0.cause == .unexpected }
    }

    private var unknownCauseRefills: [QuotaRefillTracker.Event] {
        model.refillEvents.filter { $0.cause == .unknown }
    }

    var body: some View {
        Form {
            if let values = model.simulation {
                SimulationControls(values: values)
            }
            Section {
                if let message = model.notifications.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if globalResetCandidates.isEmpty {
                    Text("No recent global reset candidates detected")
                        .foregroundStyle(.secondary)
                }
                ForEach(globalResetCandidates) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.message)
                        Text(event.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                HStack {
                    Text("Recent global resets")
                    Spacer()
                    Button("Send test notification") {
                        Task { await model.notifications.sendTest() }
                    }
                    .disabled(model.notifications.isSendingTest || model.notifications.isRequestingPermission)
                }
            } footer: {
                Text("Quota refilled early while complete banked-reset data stayed unchanged, suggesting an OpenAI reset.")
            }
            Section {
                if unknownCauseRefills.isEmpty {
                    Text("No recent unknown-cause refills detected")
                        .foregroundStyle(.secondary)
                }
                ForEach(unknownCauseRefills) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.message)
                        Text(event.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Recent unknown-cause refills")
            } footer: {
                Text("Quota refilled early, but we couldn’t rule out a user spending a banked reset—for example, reset details were missing, a credit expired or was granted around the same time, or the app was offline too long.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 640)
    }
}

private struct SimulationControls: View {
    @Bindable var values: QuotaSimulation

    var body: some View {
        Group {
            Section("Weekly quota") {
                percentage("Remaining", value: $values.weeklyRemainingPercent)
                CountdownSliders(title: "Resets in", date: $values.weeklyResetsAt, units: .daysHours, maximum: 7)
            }
            Section("5-hour quota") {
                percentage("Remaining", value: $values.fiveHourRemainingPercent)
                CountdownSliders(title: "Resets in", date: $values.fiveHourResetsAt, units: .hoursMinutes, maximum: 5)
            }
            Section {
                if values.bankedResets.isEmpty {
                    Text("No banked resets")
                        .foregroundStyle(.secondary)
                }
                ForEach(values.bankedResets) { reset in
                    @Bindable var editableReset = reset
                    HStack {
                        CountdownSliders(title: "Expires in", date: $editableReset.expiresAt, units: .daysHours, maximum: 30)
                        Button("Remove banked reset", systemImage: "minus.circle") {
                            values.bankedResets.removeAll { $0.id == reset.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add Banked Reset", systemImage: "plus") {
                    values.bankedResets.append(.init(expiresAt: .now.addingTimeInterval(86_400)))
                }
                .disabled(values.bankedResets.count >= 20)
            } header: {
                Text("Banked resets: \(values.bankedResets.count)")
            }
        }
    }

    private func percentage(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))%")
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...100, step: 1) {
                Text(title)
            }
            .labelsHidden()
            .accessibilityValue("\(Int(value.wrappedValue)) percent")
        }
    }
}

private struct CountdownSliders: View {
    enum Units {
        case daysHours, hoursMinutes

        var majorTitle: String { self == .daysHours ? "Days" : "Hours" }
        var minorTitle: String { self == .daysHours ? "Hours" : "Minutes" }
        var minorPerMajor: Int { self == .daysHours ? 24 : 60 }
        var minutesPerMinor: Int { self == .daysHours ? 60 : 1 }
    }

    let title: String
    @Binding var date: Date
    let units: Units
    let maximum: Int
    // Keep the controls steady while editing; the resulting dates still count down.
    @State private var reference = Date.now

    private var total: Int {
        max(0, Int((date.timeIntervalSince(reference) / 60).rounded()))
    }

    private var major: Int { min(maximum, total / (units.minorPerMajor * units.minutesPerMinor)) }
    private var minor: Int { total / units.minutesPerMinor % units.minorPerMajor }
    private var minutes: Int { total % units.minutesPerMinor }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            HStack(spacing: 20) {
                component(units.majorTitle, value: Binding(
                    get: { Double(major) },
                    set: { update(major: Int($0), minor: minor, minutes: minutes) }
                ), maximum: maximum)
                component(units.minorTitle, value: Binding(
                    get: { Double(minor) },
                    set: { update(major: major, minor: Int($0), minutes: minutes) }
                ), maximum: units.minorPerMajor - 1)
                if units == .daysHours {
                    component("Minutes", value: Binding(
                        get: { Double(minutes) },
                        set: { update(major: major, minor: minor, minutes: Int($0)) }
                    ), maximum: 59)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func update(major: Int, minor: Int, minutes: Int) {
        let totalMinutes = (major * units.minorPerMajor + minor) * units.minutesPerMinor + minutes
        date = reference.addingTimeInterval(Double(totalMinutes) * 60)
    }

    private func component(_ title: String, value: Binding<Double>, maximum: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...Double(maximum), step: 1) {
                Text("\(self.title): \(title)")
            }
            .labelsHidden()
            .accessibilityValue("\(Int(value.wrappedValue)) \(title.lowercased())")
        }
    }
}
