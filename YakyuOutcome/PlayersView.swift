import SwiftUI
import SwiftData

struct PlayersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.name) private var players: [Player]

    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(players) { p in
                    NavigationLink {
                        PlayerEditorView(player: p)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.name).font(.headline)
                            Text("打擊 \(batHandLabel(p.bats)) / 傳球 \(throwHandLabel(p.throwsHand))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deletePlayers)
            }
            .navigationTitle("球員")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Label("新增", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    let newPlayer = Player(name: "新球員")
                    PlayerEditorView(player: newPlayer, isNew: true)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("取消") { showAdd = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("儲存") {
                                    modelContext.insert(newPlayer)
                                    showAdd = false
                                }
                            }
                        }
                }
            }
        }
    }

    private func deletePlayers(offsets: IndexSet) {
        for i in offsets {
            modelContext.delete(players[i])
        }
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

