import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var players: [Player]
    @Query private var teams: [Team]
    @Query private var rules: [RuleSet]

    var body: some View {
        TabView {
            GameHubView()
                .tabItem { Label("Game", systemImage: "sportscourt") }

            PlayersView()
                .tabItem { Label("Players", systemImage: "person.3") }

            TeamsView()
                .tabItem { Label("Teams", systemImage: "shield") }

            SettingsView()
                .tabItem { Label("Rules", systemImage: "slider.horizontal.3") }

            LogsView()
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
        }
        .onAppear {
            bootstrapIfNeeded()
        }
        .onChange(of: players.count) { _, newValue in
            if newValue == 0 { bootstrapIfNeeded() }
        }
        .onChange(of: teams.count) { _, newValue in
            if newValue == 0 { bootstrapIfNeeded() }
        }
        .onChange(of: rules.count) { _, newValue in
            if newValue == 0 { bootstrapIfNeeded() }
        }
    }

    private func bootstrapIfNeeded() {
        if rules.isEmpty {
            modelContext.insert(RuleSet())
        }

        var samplePlayers = players
        if samplePlayers.isEmpty {
            // Create some sample players
            let p1 = Player(name: "A. Slugger", bats: .right, zSwing: 0.68, oSwing: 0.25, zContact: 0.78, oContact: 0.58,
                            gbRate: 0.40, fbRate: 0.35, ldRate: 0.20, puRate: 0.05, hitRate: 0.32,
                            hrShare: 0.14, doubleShare: 0.22, tripleShare: 0.02, speed: 0.45,
                            zoneRate: 0.52, whiffInduce: 0.45,
                            fielding: 0.55, throwing: 0.60, catching: 0.45)

            let p2 = Player(name: "B. Contact", bats: .left, zSwing: 0.62, oSwing: 0.22, zContact: 0.87, oContact: 0.70,
                            gbRate: 0.50, fbRate: 0.22, ldRate: 0.23, puRate: 0.05, hitRate: 0.34,
                            hrShare: 0.06, doubleShare: 0.20, tripleShare: 0.04, speed: 0.70,
                            zoneRate: 0.50, whiffInduce: 0.40,
                            fielding: 0.62, throwing: 0.58, catching: 0.50)

            let p3 = Player(name: "C. Ace (P)", bats: .right, zSwing: 0.55, oSwing: 0.18, zContact: 0.75, oContact: 0.55,
                            gbRate: 0.44, fbRate: 0.32, ldRate: 0.20, puRate: 0.04, hitRate: 0.28,
                            hrShare: 0.09, doubleShare: 0.18, tripleShare: 0.02, speed: 0.45,
                            zoneRate: 0.58, whiffInduce: 0.70,
                            fielding: 0.55, throwing: 0.62, catching: 0.45)

            let p4 = Player(name: "D. Defender", bats: .right, zSwing: 0.60, oSwing: 0.20, zContact: 0.80, oContact: 0.62,
                            gbRate: 0.48, fbRate: 0.25, ldRate: 0.22, puRate: 0.05, hitRate: 0.29,
                            hrShare: 0.05, doubleShare: 0.18, tripleShare: 0.02, speed: 0.55,
                            zoneRate: 0.50, whiffInduce: 0.45,
                            fielding: 0.78, throwing: 0.72, catching: 0.55)

            let seeded = [p1, p2, p3, p4]
            seeded.forEach { modelContext.insert($0) }
            samplePlayers = seeded
        }

        if teams.isEmpty {
            // Create two teams using existing or newly created players.
            let roster = samplePlayers

            let tA = Team(name: "Away Stars")
            let tH = Team(name: "Home Knights")
            modelContext.insert(tA)
            modelContext.insert(tH)

            if !roster.isEmpty {
                tA.players = roster
                tH.players = roster

                tA.ensureNineLineupSlots(modelContext: modelContext)
                tH.ensureNineLineupSlots(modelContext: modelContext)

                let positions: [Position] = [.CF,.SS,._1B,.DH,.LF,.RF,._3B,._2B,.C]
                for i in 0..<9 {
                    tA.lineup[i].player = roster[i % roster.count]
                    tA.lineup[i].position = positions[i]
                    tH.lineup[i].player = roster[(i+1) % roster.count]
                    tH.lineup[i].position = positions[i]
                }
                tA.lineup[0].position = .CF
                tH.lineup[0].position = .P
            }
        }
    }
}
