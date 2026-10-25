import SwiftUI

struct SecretWindowView: View {
    let model: QuotaModel

    var body: some View {
        Group {
            if let values = model.simulation {
                SimulationControls(values: values)
            }
        }
        .frame(width: 500, height: 640)
    }
}

private struct SimulationControls: View {
    @Bindable var values: QuotaSimulation

    var body: some View {
        Form {
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
        .formStyle(.grouped)
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
        var secondsPerMinor: Double { self == .daysHours ? 3_600 : 60 }
    }

    let title: String
    @Binding var date: Date
    let units: Units
    let maximum: Int
    // Keep the controls steady while editing; the resulting dates still count down.
    @State private var reference = Date.now

    private var total: Int {
        max(0, Int((date.timeIntervalSince(reference) / units.secondsPerMinor).rounded()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            HStack(spacing: 20) {
                component(units.majorTitle, value: Binding(
                    get: { Double(min(maximum, total / units.minorPerMajor)) },
                    set: { update(major: Int($0), minor: total % units.minorPerMajor) }
                ), maximum: maximum)
                component(units.minorTitle, value: Binding(
                    get: { Double(total % units.minorPerMajor) },
                    set: { update(major: min(maximum, total / units.minorPerMajor), minor: Int($0)) }
                ), maximum: units.minorPerMajor - 1)
            }
        }
        .padding(.vertical, 4)
    }

    private func update(major: Int, minor: Int) {
        date = reference.addingTimeInterval(Double(major * units.minorPerMajor + minor) * units.secondsPerMinor)
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
