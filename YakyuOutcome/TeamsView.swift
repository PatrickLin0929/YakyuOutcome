import SwiftUI
import SwiftData

struct TeamsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Team.name) private var teams: [Team]

    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(teams) { t in
                    NavigationLink {
                        TeamEditorView(team: t)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.name).font(.headline)
                            Text("Players: \(t.players.count) • Lineup: \(t.lineup.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteTeams)
            }
            .navigationTitle("Teams")
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
                    let team = Team(name: "New Team")
                    TeamEditorView(team: team, isNew: true)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showAdd = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    modelContext.insert(team)
                                    team.ensureNineLineupSlots(modelContext: modelContext)
                                    showAdd = false
                                }
                            }
                        }
                }
            }
        }
    }

    private func deleteTeams(offsets: IndexSet) {
        for i in offsets {
            modelContext.delete(teams[i])
        }
    }
}
