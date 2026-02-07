import SwiftUI
import AudioToolbox
import SwiftData

struct LiveGameView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var logs: [PlayLog]

    @State var game: Game

    @State private var showTrace = false
    @State private var lastPA: PAResult?
    @State private var engineError: String?
    @State private var hapticTrigger = 0
    @State private var showCelebration = false
    @State private var hasCelebrated = false

    var body: some View {
        let state = game.getState()
        let filteredLogs = logs.filter { $0.gameId == game.id }.sorted { $0.timestamp < $1.timestamp }
        let statusLabel = game.status == .finished ? localized("Final") : localized("In Progress")

        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(state: state, statusLabel: statusLabel)
                    scoreBoard(state: state)

                    HStack {
                        BaseDiamondView(bases: state.bases)
                        VStack(alignment: .leading, spacing: 8) {
                            CountView(balls: state.balls, strikes: state.strikes)
                            OutsView(outs: state.outs)
                            Text(localizedFormat("Inning %lld %@", state.inning, halfLabel(state.half)))
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)

                    Toggle("Show detailed trace", isOn: $showTrace)
                        .padding(.horizontal)

                    controlPanel

                    if let engineError {
                        Text(engineError)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    if let lastPA {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localizedFormat("Last PA Outcome: %@", lastPA.outcome))
                                .font(.title3).bold()
                                .padding(.horizontal)

                            HStack(spacing: 8) {
                                statChip(title: localized("Inning"), value: "\(state.inning) \(halfLabel(state.half))", tint: .indigo)
                                statChip(title: localized("Score"), value: "\(state.awayScore)-\(state.homeScore)", tint: .green)
                            }
                                .padding(.horizontal)

                            if showTrace {
                                TracePAView(pa: lastPA)
                                    .padding(.horizontal)
                            }
                        }
                    }

                    Divider().padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Play Log")
                            .font(.title3).bold()
                            .padding(.horizontal)

                        ForEach(Array(filteredLogs.enumerated()), id: \.element.id) { index, entry in
                            let log = entry
                            let showHalfHeader = index == 0
                                || filteredLogs[index - 1].inning != log.inning
                                || filteredLogs[index - 1].half != log.half

                            if showHalfHeader {
                                Text(localizedFormat("Inning %lld %@", log.inning, halfLabel(log.half)))
                                    .font(.headline)
                                    .padding(.horizontal)
                                    .padding(.top, 6)
                            }

                            if showTrace {
                                NavigationLink {
                                    LogDetailView(log: log)
                                } label: {
                                    playLogCard(log: log)
                                }
                                .buttonStyle(.plain)
                            } else {
                                playLogCard(log: log)
                            }
                        }
                    }
                }
            }
            if showCelebration {
                ConfettiView()
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        .navigationTitle("\(game.awayTeam?.name ?? localized("Away")) @ \(game.homeTeam?.name ?? localized("Home"))")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    triggerHaptic()
                    BaseballEngine.resetGame(game: game)
                    lastPA = nil
                    engineError = nil
                    hasCelebrated = false
                } label: {
                    Label(localized("Reset"), systemImage: "arrow.counterclockwise")
                }
            }
        }
        .onAppear {
            if game.status == .finished && !hasCelebrated {
                startCelebration()
            }
        }
        .onChange(of: game.status) { _, newValue in
            if newValue == .finished && !hasCelebrated {
                startCelebration()
            }
        }
    }

    @ViewBuilder
    private func header(state: GameState, statusLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(statusLabel)
                .font(.headline)
                .foregroundStyle(game.status == .finished ? .secondary : .primary)

            Text(localizedFormat("Seed: %lld", game.seed))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func scoreBoard(state: GameState) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(game.awayTeam?.name ?? localized("Away")).font(.headline)
                Text(localized("Away")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(state.awayScore)")
                .font(.largeTitle).bold()
            Text(" - ")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("\(state.homeScore)")
                .font(.largeTitle).bold()
            Spacer()
            VStack(alignment: .trailing) {
                Text(game.homeTeam?.name ?? localized("Home")).font(.headline)
                Text(localized("Home")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private var controlPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    triggerHaptic()
                    runPA()
                } label: {
                    Label(localized("Auto PA"), systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(game.status == .finished)

                Button {
                    triggerHaptic()
                    runHalf()
                } label: {
                    Label(localized("Auto Half"), systemImage: "forward.end")
                }
                .buttonStyle(.bordered)
                .disabled(game.status == .finished)

                Button {
                    triggerHaptic()
                    runGame()
                } label: {
                    Label(localized("Auto Game"), systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(game.status == .finished)
            }
        }
        .padding(.horizontal)
    }

    private func runPA() {
        engineError = nil
        do {
            lastPA = try BaseballEngine.simulatePA(game: game, modelContext: modelContext)
            checkGameFinished()
        } catch {
            engineError = error.localizedDescription
        }
    }

    private func runHalf() {
        engineError = nil
        do {
            try BaseballEngine.simulateHalfInning(game: game, modelContext: modelContext)
            lastPA = nil
            checkGameFinished()
        } catch {
            engineError = error.localizedDescription
        }
    }

    private func runGame() {
        engineError = nil
        do {
            try BaseballEngine.simulateGame(game: game, modelContext: modelContext)
            lastPA = nil
            checkGameFinished()
        } catch {
            engineError = error.localizedDescription
        }
    }

    private func triggerHaptic() {
        hapticTrigger += 1
    }

    private func startCelebration() {
        hasCelebrated = true
        showCelebration = true
        playCelebrationSound()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            showCelebration = false
        }
    }

    private func checkGameFinished() {
        if game.status == .finished && !hasCelebrated {
            startCelebration()
        }
    }

    private func playCelebrationSound() {
        AudioServicesPlaySystemSound(1109)
    }

    @ViewBuilder
    private func playLogCard(log: PlayLog) -> some View {
        let snapshot = gameSnapshot(for: log)
        let scoreText = snapshot.map { "\($0.away)-\($0.home)" } ?? "--"
        let basesText = snapshot.map { baseStateLabel($0.bases) } ?? localized("Unknown")

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                statChip(
                    title: localized("Inning"),
                    value: "\(log.inning) \(halfLabel(log.half, includeArrow: false))",
                    tint: .indigo
                )
                statChip(title: localized("Score"), value: scoreText, tint: .green)
                statChip(title: localized("Bases"), value: basesText, tint: .blue)
                statChip(title: localized("Pitches"), value: "\(log.pitchesCount)", tint: .orange)
            }

                Text(localizedFormat("Outcome: %@", log.paOutcome))
                    .font(.headline)
                    .foregroundStyle(.primary)

            Text(localizedFormat("%@ vs %@ • %@ / %@", log.offenseTeam, log.defenseTeam, log.batterName, log.pitcherName))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    @ViewBuilder
    private func statChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tint.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Log Detail

struct LogDetailView: View {
    var log: PlayLog
    @State private var pa: PAResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(localizedFormat("Inning %lld %@", log.inning, halfLabel(log.half)))
                    .font(.title3).bold()
                Text(localizedFormat("%@ batting • vs %@", log.offenseTeam, log.defenseTeam))
                    .foregroundStyle(.secondary)
                Text(localizedFormat("Batter: %@", log.batterName))
                Text(localizedFormat("Pitcher: %@", log.pitcherName))
                Text(localizedFormat("Outcome: %@", log.paOutcome))
                    .font(.headline)
                if let score = scoreSnapshot(for: log) {
                    Text(localizedFormat("Score %lld-%lld", score.away, score.home))
                        .foregroundStyle(.secondary)
                }
                if let snapshot = gameSnapshot(for: log) {
                    Text(localizedFormat("Bases: %@", baseStateLabel(snapshot.bases)))
                        .foregroundStyle(.secondary)
                }

                Divider()

                if let pa {
                    ForEach(pa.pitches) { p in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(localizedFormat("Pitch %lld: %@", p.pitchNumberInPA, localized(p.label)))
                                .font(.headline)
                            ForEach(p.trace) { t in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("• \(localized(t.title)): \(localized(t.picked))")
                                    Text(localizedFormat("  roll %lld/%lld, threshold %lld", t.roll, t.range, t.threshold))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !t.details.isEmpty {
                                        Text("  \(t.details.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.leading, 8)
                            }
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                } else {
                    Text(localized("Loading details…"))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .onAppear {
            pa = BaseballEngine.decodePAResult(log.detailJSON)
        }
        .navigationTitle(localized("PA Detail"))
    }
}

// MARK: - Trace View for last PA

struct TracePAView: View {
    let pa: PAResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(pa.pitches) { pitch in
                VStack(alignment: .leading, spacing: 6) {
                    Text(localizedFormat("Pitch %lld: %@", pitch.pitchNumberInPA, localized(pitch.label)))
                        .font(.headline)
                    ForEach(pitch.trace) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("• \(localized(t.title)): \(localized(t.picked))")
                            Text(localizedFormat("  roll %lld/%lld, threshold %lld", t.roll, t.range, t.threshold))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !t.details.isEmpty {
                                Text("  \(t.details.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, 8)
                    }
                }
                .padding(.vertical, 8)
                Divider()
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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

private func scoreSnapshot(for log: PlayLog) -> (away: Int, home: Int)? {
    guard let snapshot = gameSnapshot(for: log) else { return nil }
    return (snapshot.away, snapshot.home)
}

private func gameSnapshot(for log: PlayLog) -> (away: Int, home: Int, bases: Int)? {
    guard let pa = BaseballEngine.decodePAResult(log.detailJSON) else { return nil }
    guard let last = pa.pitches.last else { return nil }
    for step in last.trace.reversed() {
        if step.title == "Score Snapshot" {
            let away = Int(step.details["awayScore"] ?? "")
            let home = Int(step.details["homeScore"] ?? "")
            let bases = Int(step.details["bases"] ?? "") ?? 0
            if let away, let home {
                return (away, home, bases)
            }
        }
    }
    return nil
}

private func baseStateLabel(_ bases: Int) -> String {
    let on1 = (bases & 1) != 0
    let on2 = (bases & 2) != 0
    let on3 = (bases & 4) != 0

    if !on1 && !on2 && !on3 { return localized("Empty") }
    if on1 && on2 && on3 { return localized("Loaded") }

    var occupied: [String] = []
    if on1 { occupied.append(localized("1B")) }
    if on2 { occupied.append(localized("2B")) }
    if on3 { occupied.append(localized("3B")) }
    return occupied.joined(separator: " + ")
}


#Preview("Live Game (Seeded)") {
    // 1) Create an in-memory SwiftData container for Preview
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Player.self, Team.self, LineupSlot.self, RuleSet.self, Game.self, PlayLog.self,
        configurations: config
    )
    let context = container.mainContext

    // 2) Seed RuleSet
    let rules = RuleSet(name: "Preview Rules")
    context.insert(rules)

    // 3) Seed Players (至少 4 個，示範用；打序會重複填滿 9 人)
    let p1 = Player(name: "Preview Slugger", bats: .right, zSwing: 0.70, oSwing: 0.28, zContact: 0.78, oContact: 0.58,
                    gbRate: 0.38, fbRate: 0.38, ldRate: 0.19, puRate: 0.05,
                    hitRate: 0.33, hrShare: 0.16, doubleShare: 0.20, tripleShare: 0.02,
                    speed: 0.45,
                    zoneRate: 0.52, whiffInduce: 0.45,
                    fielding: 0.55, throwing: 0.60, catching: 0.45)

    let p2 = Player(name: "Preview Contact", bats: .left, zSwing: 0.62, oSwing: 0.22, zContact: 0.88, oContact: 0.70,
                    gbRate: 0.52, fbRate: 0.20, ldRate: 0.23, puRate: 0.05,
                    hitRate: 0.35, hrShare: 0.06, doubleShare: 0.22, tripleShare: 0.04,
                    speed: 0.72,
                    zoneRate: 0.50, whiffInduce: 0.40,
                    fielding: 0.62, throwing: 0.58, catching: 0.50)

    let p3 = Player(name: "Preview Ace (P)", bats: .right, zSwing: 0.55, oSwing: 0.18, zContact: 0.76, oContact: 0.55,
                    gbRate: 0.44, fbRate: 0.32, ldRate: 0.20, puRate: 0.04,
                    hitRate: 0.28, hrShare: 0.08, doubleShare: 0.18, tripleShare: 0.02,
                    speed: 0.45,
                    zoneRate: 0.60, whiffInduce: 0.72,
                    fielding: 0.55, throwing: 0.62, catching: 0.45)

    let p4 = Player(name: "Preview Defender", bats: .right, zSwing: 0.60, oSwing: 0.20, zContact: 0.80, oContact: 0.62,
                    gbRate: 0.48, fbRate: 0.25, ldRate: 0.22, puRate: 0.05,
                    hitRate: 0.29, hrShare: 0.05, doubleShare: 0.18, tripleShare: 0.02,
                    speed: 0.55,
                    zoneRate: 0.50, whiffInduce: 0.45,
                    fielding: 0.78, throwing: 0.72, catching: 0.55)

    [p1, p2, p3, p4].forEach { context.insert($0) }

    // 4) Seed Teams
    let away = Team(name: "Preview Away")
    let home = Team(name: "Preview Home")
    context.insert(away)
    context.insert(home)

    away.players = [p1, p2, p3, p4]
    home.players = [p1, p2, p3, p4]

    away.ensureNineLineupSlots(modelContext: context)
    home.ensureNineLineupSlots(modelContext: context)

    // 5) Assign lineup & positions
    let positions: [Position] = [.CF, .SS, ._1B, .DH, .LF, .RF, ._3B, ._2B, .C]
    for i in 0..<9 {
        away.lineup[i].player = [p1, p2, p4, p2][i % 4]
        away.lineup[i].position = positions[i]

        home.lineup[i].player = [p2, p1, p4, p1][i % 4]
        home.lineup[i].position = positions[i]
    }
    // 把 home 的投手指定成 p3
    home.lineup[0].player = p3
    home.lineup[0].position = .P

    // 6) Create a Game
    let game = Game(awayTeam: away, homeTeam: home, ruleSet: rules, seed: 123456)
    context.insert(game)

    // 7) Pre-simulate a few PAs so Preview has logs/results
    try? BaseballEngine.simulatePA(game: game, modelContext: context)
    try? BaseballEngine.simulatePA(game: game, modelContext: context)
    try? BaseballEngine.simulatePA(game: game, modelContext: context)

    // 8) Show the view
    return NavigationStack {
        LiveGameView(game: game)
    }
    .modelContainer(container)
}
