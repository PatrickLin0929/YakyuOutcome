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
                    Text("找不到規則設定。")
                    Button("建立預設規則") {
                        modelContext.insert(RuleSet())
                    }
                }
                .navigationTitle("規則")
            }
        }
    }
}

struct RuleEditorView: View {
    @Bindable var ruleSet: RuleSet

    var body: some View {
        Form {
            Section("一般") {
                TextField("名稱", text: $ruleSet.name)
                HStack {
                    Text("局數")
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

            Section("球數") {
                Toggle("兩好球後界外球維持兩好球", isOn: $ruleSet.twoStrikeFoulKeepsTwoStrikes)
            }

            Section("擊中後結果") {
                NumericRow(title: "擊中後變界外球機率", value: $ruleSet.foulRateOnContact)
            }

            Section("暴投 / 捕逸（有人上壘且壞球）") {
                NumericRow(title: "目送時 WP/PB 機率", value: $ruleSet.wildPitchChanceOnTake)
                NumericRow(title: "揮棒時 WP/PB 機率", value: $ruleSet.wildPitchChanceOnSwing)
                NumericRow(title: "捕逸佔比", value: $ruleSet.passedBallShare)
            }

            Section("守備與站位") {
                Picker("預設內野站位", selection: $ruleSet.defaultAlignment) {
                    ForEach(InfieldAlignment.allCases) { a in
                        Text(alignmentLabel(a)).tag(a)
                    }
                }
                NumericRow(title: "佈陣時滾地安打倍率", value: $ruleSet.shiftGBHitMultiplier)
                NumericRow(title: "趨前時滾地安打倍率", value: $ruleSet.infieldInGBHitMultiplier)
            }

            Section("策略規則") {
                Picker("本壘傳球策略", selection: $ruleSet.throwHomePolicy) {
                    ForEach(ThrowHomePolicy.allCases) { p in
                        Text(throwHomePolicyLabel(p)).tag(p)
                    }
                }
                NumericRow(title: "跑壘積極度", value: $ruleSet.runnerAggressiveness)
                Toggle("可行時優先嘗試雙殺", isOn: $ruleSet.tryDoublePlayPolicy)
            }
        }
        .navigationTitle("規則")
    }

    private func alignmentLabel(_ alignment: InfieldAlignment) -> String {
        switch alignment {
        case .normal: return "標準站位"
        case .shiftLeft: return "左打佈陣"
        case .shiftRight: return "右打佈陣"
        case .infieldIn: return "內野趨前"
        }
    }

    private func throwHomePolicyLabel(_ policy: ThrowHomePolicy) -> String {
        switch policy {
        case .never: return "不傳本壘"
        case .always: return "永遠傳本壘"
        case .situational: return "依情境判斷"
        }
    }
}
