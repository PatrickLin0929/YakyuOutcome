import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var rules: [RuleSet]

    var body: some View {
        NavigationStack {
            if let rs = rules.first {
                RuleEditorView(ruleSet: rs)
            } else {
                VStack(spacing: 12) {
                    Text("No RuleSet found.")
                    Button("Create Default") {
                        modelContext.insert(RuleSet())
                    }
                }
                .navigationTitle("Rules")
            }
        }
    }
}

struct RuleEditorView: View {
    @Bindable var ruleSet: RuleSet

    var body: some View {
        Form {
            Section("General") {
                TextField("Name", text: $ruleSet.name)
                HStack {
                    Text("Innings")
                    Spacer()
                    TextField("", value: $ruleSet.innings, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .onChange(of: ruleSet.innings) { _, newValue in
                            ruleSet.innings = min(15, max(1, newValue))
                        }
                }
            }

            Section("Count") {
                Toggle("Two-strike foul keeps 2 strikes", isOn: $ruleSet.twoStrikeFoulKeepsTwoStrikes)
            }

            Section("Contact Outcome") {
                NumericRow(title: "Foul Rate on Contact", value: $ruleSet.foulRateOnContact)
            }

            Section("WP / PB (runners on, out of zone)") {
                NumericRow(title: "WP/PB chance on TAKE", value: $ruleSet.wildPitchChanceOnTake)
                NumericRow(title: "WP/PB chance on SWING", value: $ruleSet.wildPitchChanceOnSwing)
                NumericRow(title: "Passed Ball share", value: $ruleSet.passedBallShare)
            }

            Section("Defense & Alignment") {
                Picker("Default Alignment", selection: $ruleSet.defaultAlignment) {
                    ForEach(InfieldAlignment.allCases) { a in
                        Text(a.rawValue).tag(a)
                    }
                }
                NumericRow(title: "Shift GB Hit Multiplier", value: $ruleSet.shiftGBHitMultiplier)
                NumericRow(title: "Infield-In GB Hit Multiplier", value: $ruleSet.infieldInGBHitMultiplier)
            }

            Section("Ambiguity Policies") {
                Picker("Throw Home Policy", selection: $ruleSet.throwHomePolicy) {
                    ForEach(ThrowHomePolicy.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                NumericRow(title: "Runner Aggressiveness", value: $ruleSet.runnerAggressiveness)
                Toggle("Try Double Play if possible", isOn: $ruleSet.tryDoublePlayPolicy)
            }
        }
        .navigationTitle("Rules")
    }
}

