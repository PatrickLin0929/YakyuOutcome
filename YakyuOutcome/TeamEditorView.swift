import SwiftUI
import SwiftData

struct TeamEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.name) private var allPlayers: [Player]

    @Bindable var team: Team
    var isNew: Bool = false

    @State private var editMode: EditMode = .inactive
    @State private var showAddPlayers = false

    var body: some View {
        Form {
            Section("Team") {
                TextField("Name", text: $team.name)
            }

            Section("Roster") {
                if team.players.isEmpty {
                    Text("No players in roster yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(team.players) { p in
                        Text(p.name)
                    }
                    .onDelete { idx in
                        idx.forEach { team.players.remove(at: $0) }
                    }
                }

                Button {
                    showAddPlayers = true
                } label: {
                    Label("Add Players", systemImage: "person.badge.plus")
                }
            }

            Section("Lineup & Positions (9)") {
                Button {
                    team.ensureNineLineupSlots(modelContext: modelContext)
                } label: {
                    Label("Ensure 9 Slots", systemImage: "wrench.adjustable")
                }

                let lineup = team.sortedLineup()
                if lineup.isEmpty {
                    Text("No lineup slots. Tap 'Ensure 9 Slots'.")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(lineup) { slot in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("#\(slot.order + 1)")
                                        .font(.headline)
                                        .monospacedDigit()
                                    Spacer()
                                    Picker("Pos", selection: Binding(
                                        get: { slot.position },
                                        set: { slot.position = $0 }
                                    )) {
                                        ForEach(Position.allCases) { pos in
                                            Text(pos.displayName).tag(pos)
                                        }
                                    }
                                    .labelsHidden()
                                }

                                Picker("Player", selection: Binding(
                                    get: { slot.player },
                                    set: { slot.player = $0 }
                                )) {
                                    Text("Unassigned").tag(Player?.none)
                                    ForEach(team.players) { p in
                                        Text(p.name).tag(Player?.some(p))
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .onMove { from, to in
                            var arr = team.sortedLineup()
                            // reorder array
                            arr.move(fromOffsets: from, toOffset: to)
                            // write back order indices
                            for (i, s) in arr.enumerated() { s.order = i }
                            team.lineup.sort { $0.order < $1.order }
                        }
                    }
                    .frame(minHeight: 360)
                    .environment(\.editMode, $editMode)
                }

                HStack {
                    Button(editMode == .active ? "Done Reorder" : "Reorder") {
                        editMode = (editMode == .active) ? .inactive : .active
                    }
                }
            }

            if isNew {
                Section {
                    Text("Tip: Add at least 9 lineup players to simulate games.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(team.name)
        .sheet(isPresented: $showAddPlayers) {
            NavigationStack {
                List {
                    ForEach(allPlayers) { p in
                        HStack {
                            Text(p.name)
                            Spacer()
                            if team.players.contains(where: { $0.id == p.id }) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            togglePlayer(p)
                        }
                    }
                }
                .navigationTitle("Add Players")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showAddPlayers = false }
                    }
                }
            }
        }
        .onAppear {
            team.ensureNineLineupSlots(modelContext: modelContext)
        }
    }

    private func togglePlayer(_ p: Player) {
        if let idx = team.players.firstIndex(where: { $0.id == p.id }) {
            team.players.remove(at: idx)
        } else {
            team.players.append(p)
        }
    }
}
