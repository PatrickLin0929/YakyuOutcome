import SwiftUI
import SwiftData

struct GameHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @Query private var teams: [Team]
    @Query private var rules: [RuleSet]

    @State private var selectedAway: Team?
    @State private var selectedHome: Team?
    @State private var selectedRules: RuleSet?
    @State private var showCreate = false
    @State private var hapticTrigger = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Create New Game") {
                    Button {
                        triggerHaptic()
                        showCreate = true
                    } label: {
                        Label("New Game", systemImage: "plus.circle")
                    }
                }

                Section("Games") {
                    if games.isEmpty {
                        Text("No games yet. Create one.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(games) { game in
                        NavigationLink {
                            LiveGameView(game: game)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(game.awayTeam?.name ?? "Away") @ \(game.homeTeam?.name ?? "Home")")
                                    .font(.headline)
                                let st = game.getState()
                                let statusLabel = game.status == .finished ? localized("Final") : localized("In Progress")
                                Text(localizedFormat("Inning %lld %@  Score %lld-%lld  • %@", st.inning, halfLabel(st.half, includeArrow: false), st.awayScore, st.homeScore, statusLabel))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteGames)
                }
            }
            .navigationTitle("Baseball Match Sim")
            .sheet(isPresented: $showCreate) {
                createSheet
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section("Teams") {
                    Picker("Away", selection: $selectedAway) {
                        Text("Select").tag(Team?.none)
                        ForEach(teams) { t in Text(t.name).tag(Team?.some(t)) }
                    }
                    Picker("Home", selection: $selectedHome) {
                        Text("Select").tag(Team?.none)
                        ForEach(teams) { t in Text(t.name).tag(Team?.some(t)) }
                    }
                }
                Section("Rules") {
                    Picker("RuleSet", selection: $selectedRules) {
                        Text("Select").tag(RuleSet?.none)
                        ForEach(rules) { r in Text(r.name).tag(RuleSet?.some(r)) }
                    }
                }
            }
            .navigationTitle("New Game")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        triggerHaptic()
                        showCreate = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        triggerHaptic()
                        createGame()
                        showCreate = false
                    }
                    .disabled(selectedAway == nil || selectedHome == nil || selectedRules == nil)
                }
            }
            .onAppear {
                if selectedRules == nil { selectedRules = rules.first }
            }
        }
    }

    private func createGame() {
        guard let away = selectedAway, let home = selectedHome, let rs = selectedRules else { return }
        away.ensureNineLineupSlots(modelContext: modelContext)
        home.ensureNineLineupSlots(modelContext: modelContext)

        let game = Game(awayTeam: away, homeTeam: home, ruleSet: rs)
        modelContext.insert(game)
    }

    private func deleteGames(offsets: IndexSet) {
        for i in offsets {
            modelContext.delete(games[i])
        }
    }

    private func triggerHaptic() {
        hapticTrigger += 1
    }
}

private func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

private func localizedFormat(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args)
}

private func halfLabel(_ half: HalfInning, includeArrow: Bool = true) -> String {
    let base = localized(half == .top ? "game.top" : "game.bottom")
    if includeArrow {
        return (half == .top ? "▲ " : "▼ ") + base
    }
    return base
}
