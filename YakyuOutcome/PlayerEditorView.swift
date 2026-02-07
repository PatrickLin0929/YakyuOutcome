import SwiftUI
import SwiftData

struct PlayerEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var player: Player
    var isNew: Bool = false

    var body: some View {
        Form {
            Section("基本資料") {
                TextField("姓名", text: $player.name)
                Picker("打擊", selection: $player.bats) {
                    ForEach(BatHand.allCases) { v in
                        Text(batHandLabel(v)).tag(v)
                    }
                }
                Picker("傳球", selection: $player.throwsHand) {
                    ForEach(ThrowHand.allCases) { v in
                        Text(throwHandLabel(v)).tag(v)
                    }
                }
            }

            Section("打擊：揮棒 / 擊中") {
                NumericRow(title: "好球帶揮棒率", value: $player.zSwing)
                NumericRow(title: "壞球帶揮棒率", value: $player.oSwing)
                NumericRow(title: "好球帶擊中率", value: $player.zContact)
                NumericRow(title: "壞球帶擊中率", value: $player.oContact)
            }

            Section("擊球型態分布（總和約為 1）") {
                NumericRow(title: "滾地球比例 (GB)", value: $player.gbRate)
                NumericRow(title: "飛球比例 (FB)", value: $player.fbRate)
                NumericRow(title: "平飛球比例 (LD)", value: $player.ldRate)
                NumericRow(title: "高飛球比例 (PU)", value: $player.puRate)
            }

            Section("長打能力") {
                NumericRow(title: "安打率", value: $player.hitRate)
                NumericRow(title: "全壘打比例（高飛/平飛）", value: $player.hrShare)
                NumericRow(title: "二壘打比例（高飛/平飛）", value: $player.doubleShare)
                NumericRow(title: "三壘打比例（高飛/平飛）", value: $player.tripleShare)
                NumericRow(title: "速度", value: $player.speed)
            }

            Section("投球") {
                NumericRow(title: "進好球帶機率", value: $player.zoneRate)
                NumericRow(title: "誘導揮空能力", value: $player.whiffInduce)
            }

            Section("守備") {
                NumericRow(title: "守備能力", value: $player.fielding)
                NumericRow(title: "傳球能力", value: $player.throwing)
                NumericRow(title: "捕逸/接捕能力", value: $player.catching)
            }

            if isNew {
                Section {
                    Button("完成") { dismiss() }
                }
            }
        }
        .navigationTitle(isNew ? "新球員" : player.name)
    }

    private func batHandLabel(_ hand: BatHand) -> String {
        switch hand {
        case .right: return "右打"
        case .left: return "左打"
        case .switchH: return "左右開弓"
        }
    }

    private func throwHandLabel(_ hand: ThrowHand) -> String {
        switch hand {
        case .right: return "右投"
        case .left: return "左投"
        }
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
