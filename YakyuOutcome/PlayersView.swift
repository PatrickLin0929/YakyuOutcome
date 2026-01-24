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
                            Text("Bat \(p.bats.rawValue) / Throw \(p.throwsHand.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deletePlayers)
            }
            .navigationTitle("Players")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    let newPlayer = Player(name: "New Player")
                    PlayerEditorView(player: newPlayer, isNew: true)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showAdd = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
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
}


