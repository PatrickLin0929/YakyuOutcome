import SwiftUI
import SwiftData

struct PlayerEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var player: Player
    var isNew: Bool = false

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $player.name)
                Picker("Bats", selection: $player.bats) {
                    ForEach(BatHand.allCases) { v in
                        Text(v.rawValue).tag(v)
                    }
                }
                Picker("Throws", selection: $player.throwsHand) {
                    ForEach(ThrowHand.allCases) { v in
                        Text(v.rawValue).tag(v)
                    }
                }
            }

            Section("Batting: Swing / Contact") {
                NumericRow(title: "Z-Swing", value: $player.zSwing)
                NumericRow(title: "O-Swing", value: $player.oSwing)
                NumericRow(title: "Z-Contact", value: $player.zContact)
                NumericRow(title: "O-Contact", value: $player.oContact)
            }

            Section("Batted Ball Distribution (sum≈1)") {
                NumericRow(title: "GB Rate", value: $player.gbRate)
                NumericRow(title: "FB Rate", value: $player.fbRate)
                NumericRow(title: "LD Rate", value: $player.ldRate)
                NumericRow(title: "PU Rate", value: $player.puRate)
            }

            Section("Hitting Quality") {
                NumericRow(title: "Hit Rate", value: $player.hitRate)
                NumericRow(title: "HR Share (air hits)", value: $player.hrShare)
                NumericRow(title: "2B Share (air hits)", value: $player.doubleShare)
                NumericRow(title: "3B Share (air hits)", value: $player.tripleShare)
                NumericRow(title: "Speed", value: $player.speed)
            }

            Section("Pitching") {
                NumericRow(title: "Zone Rate", value: $player.zoneRate)
                NumericRow(title: "Whiff Induce", value: $player.whiffInduce)
            }

            Section("Defense") {
                NumericRow(title: "Fielding", value: $player.fielding)
                NumericRow(title: "Throwing", value: $player.throwing)
                NumericRow(title: "Catching", value: $player.catching)
            }

            if isNew {
                Section {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationTitle(isNew ? "New Player" : player.name)
    }
}

struct NumericRow: View {
    var title: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: $value, format: .number.precision(.fractionLength(3)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 96)
                .onChange(of: value) { _, newValue in
                    value = min(1, max(0, newValue))
                }
        }
    }
}
