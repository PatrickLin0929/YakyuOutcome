import Foundation
import SwiftData

// MARK: - Enums

enum BatHand: String, Codable, CaseIterable, Identifiable {
    case right = "R"
    case left = "L"
    case switchH = "S"
    var id: String { rawValue }
}

enum ThrowHand: String, Codable, CaseIterable, Identifiable {
    case right = "R"
    case left = "L"
    var id: String { rawValue }
}

enum Position: String, Codable, CaseIterable, Identifiable {
    case P, C, _1B, _2B, _3B, SS, LF, CF, RF, DH

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .P: return "P"
        case .C: return "C"
        case ._1B: return "1B"
        case ._2B: return "2B"
        case ._3B: return "3B"
        case .SS: return "SS"
        case .LF: return "LF"
        case .CF: return "CF"
        case .RF: return "RF"
        case .DH: return "DH"
        }
    }
}

enum HalfInning: String, Codable, CaseIterable, Identifiable {
    case top, bottom
    var id: String { rawValue }
}

enum InfieldAlignment: String, Codable, CaseIterable, Identifiable {
    case normal
    case shiftLeft
    case shiftRight
    case infieldIn
    var id: String { rawValue }
}

enum ThrowHomePolicy: String, Codable, CaseIterable, Identifiable {
    case never
    case always
    case situational // based on outs/score
    var id: String { rawValue }
}

enum GameStatus: String, Codable {
    case inProgress
    case finished
}

// MARK: - Codable Structs (stored as JSON String in SwiftData models)

struct GameState: Codable {
    var inning: Int = 1
    var half: HalfInning = .top
    var outs: Int = 0
    var balls: Int = 0
    var strikes: Int = 0

    /// bases bitmask: 1=1B, 2=2B, 4=3B
    var bases: Int = 0

    var awayScore: Int = 0
    var homeScore: Int = 0

    var awayLineupIndex: Int = 0
    var homeLineupIndex: Int = 0

    var lastMessage: String? = nil
}

struct TraceStep: Codable, Identifiable {
    var id = UUID()
    var title: String
    var details: [String: String]
    var roll: Int
    var range: Int
    var threshold: Int
    var picked: String
}

struct PitchEvent: Codable, Identifiable {
    var id = UUID()
    var pitchNumberInPA: Int
    var label: String           // e.g. "Ball", "Called Strike", "Foul", "In Play", "Wild Pitch"
    var endedPA: Bool
    var trace: [TraceStep]
}

struct PAResult: Codable {
    var outcome: String         // e.g. "K", "BB", "1B", "2B", "HR", "GO", "FO", "E", "FC", "DP"
    var pitches: [PitchEvent]
}

// MARK: - SwiftData Models

@Model
final class Player {
    @Attribute(.unique) var id: UUID
    var name: String
    var bats: BatHand
    var throwsHand: ThrowHand

    // Batting
    var zSwing: Double
    var oSwing: Double
    var zContact: Double
    var oContact: Double

    // Batted-ball distribution (should sum to 1.0)
    var gbRate: Double
    var fbRate: Double
    var ldRate: Double
    var puRate: Double

    // Hit / XBH
    var hitRate: Double         // base chance of hit on ball in play (before defense/alignment)
    var hrShare: Double         // among hits, share that are HR (only for air-type resolution)
    var doubleShare: Double
    var tripleShare: Double

    // Speed (0..1) used for infield hits / DP avoidance etc (simplified)
    var speed: Double

    // Pitching
    var zoneRate: Double        // chance pitch is in zone
    var whiffInduce: Double     // increases whiff probability (simplified)

    // Defense (0..1)
    var fielding: Double
    var throwing: Double
    var catching: Double

    init(
        id: UUID = UUID(),
        name: String,
        bats: BatHand = .right,
        throwsHand: ThrowHand = .right,
        zSwing: Double = 0.65,
        oSwing: Double = 0.25,
        zContact: Double = 0.80,
        oContact: Double = 0.60,
        gbRate: Double = 0.45,
        fbRate: Double = 0.30,
        ldRate: Double = 0.20,
        puRate: Double = 0.05,
        hitRate: Double = 0.30,
        hrShare: Double = 0.10,
        doubleShare: Double = 0.22,
        tripleShare: Double = 0.03,
        speed: Double = 0.50,
        zoneRate: Double = 0.52,
        whiffInduce: Double = 0.50,
        fielding: Double = 0.60,
        throwing: Double = 0.60,
        catching: Double = 0.50
    ) {
        self.id = id
        self.name = name
        self.bats = bats
        self.throwsHand = throwsHand

        self.zSwing = zSwing
        self.oSwing = oSwing
        self.zContact = zContact
        self.oContact = oContact

        self.gbRate = gbRate
        self.fbRate = fbRate
        self.ldRate = ldRate
        self.puRate = puRate

        self.hitRate = hitRate
        self.hrShare = hrShare
        self.doubleShare = doubleShare
        self.tripleShare = tripleShare

        self.speed = speed

        self.zoneRate = zoneRate
        self.whiffInduce = whiffInduce

        self.fielding = fielding
        self.throwing = throwing
        self.catching = catching
    }
}

@Model
final class Team {
    @Attribute(.unique) var id: UUID
    var name: String

    @Relationship var players: [Player] = []
    @Relationship(deleteRule: .cascade) var lineup: [LineupSlot] = []

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    func ensureNineLineupSlots(modelContext: ModelContext) {
        if lineup.count >= 9 { return }
        let existing = lineup.count
        for i in existing..<9 {
            let slot = LineupSlot(order: i, position: .DH)
            slot.team = self
            modelContext.insert(slot)
            lineup.append(slot)
        }
        lineup.sort { $0.order < $1.order }
    }

    func sortedLineup() -> [LineupSlot] {
        lineup.sorted { $0.order < $1.order }
    }
}

@Model
final class LineupSlot {
    @Attribute(.unique) var id: UUID
    var order: Int
    var position: Position

    @Relationship var player: Player?
    @Relationship(inverse: \Team.lineup) var team: Team?

    init(id: UUID = UUID(), order: Int, position: Position) {
        self.id = id
        self.order = order
        self.position = position
    }
}

@Model
final class RuleSet {
    @Attribute(.unique) var id: UUID
    var name: String

    // Count rules
    var twoStrikeFoulKeepsTwoStrikes: Bool

    // Contact -> foul vs in-play
    var foulRateOnContact: Double  // e.g. 0.60

    // Wild pitch / passed ball (only matters with runner on base)
    var wildPitchChanceOnTake: Double   // when oZone + take
    var wildPitchChanceOnSwing: Double  // when oZone + swing (lower)
    var passedBallShare: Double         // share of WP/PB that are PB (catcher fault)

    // Defense & alignment
    var defaultAlignment: InfieldAlignment
    var shiftGBHitMultiplier: Double    // shift reduces GB hit chance if aligned correctly (simplified)
    var infieldInGBHitMultiplier: Double // infield in increases GB hit chance (holes)

    // Strategy policies (resolve ambiguity)
    var throwHomePolicy: ThrowHomePolicy
    var runnerAggressiveness: Double    // 0..1, impacts taking extra base / scoring on contact
    var tryDoublePlayPolicy: Bool

    // Game length
    var innings: Int

    init(
        id: UUID = UUID(),
        name: String = "Default",
        twoStrikeFoulKeepsTwoStrikes: Bool = true,
        foulRateOnContact: Double = 0.60,
        wildPitchChanceOnTake: Double = 1.0 / 72.0,
        wildPitchChanceOnSwing: Double = 1.0 / 144.0,
        passedBallShare: Double = 0.10,
        defaultAlignment: InfieldAlignment = .normal,
        shiftGBHitMultiplier: Double = 0.90,
        infieldInGBHitMultiplier: Double = 1.15,
        throwHomePolicy: ThrowHomePolicy = .situational,
        runnerAggressiveness: Double = 0.50,
        tryDoublePlayPolicy: Bool = true,
        innings: Int = 9
    ) {
        self.id = id
        self.name = name
        self.twoStrikeFoulKeepsTwoStrikes = twoStrikeFoulKeepsTwoStrikes
        self.foulRateOnContact = foulRateOnContact
        self.wildPitchChanceOnTake = wildPitchChanceOnTake
        self.wildPitchChanceOnSwing = wildPitchChanceOnSwing
        self.passedBallShare = passedBallShare
        self.defaultAlignment = defaultAlignment
        self.shiftGBHitMultiplier = shiftGBHitMultiplier
        self.infieldInGBHitMultiplier = infieldInGBHitMultiplier
        self.throwHomePolicy = throwHomePolicy
        self.runnerAggressiveness = runnerAggressiveness
        self.tryDoublePlayPolicy = tryDoublePlayPolicy
        self.innings = innings
    }
}

@Model
final class Game {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var statusRaw: String

    @Relationship var awayTeam: Team?
    @Relationship var homeTeam: Team?
    @Relationship var ruleSet: RuleSet?

    var seed: UInt64
    var stateJSON: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        status: GameStatus = .inProgress,
        awayTeam: Team? = nil,
        homeTeam: Team? = nil,
        ruleSet: RuleSet? = nil,
        seed: UInt64 = UInt64.random(in: 1...UInt64.max),
        state: GameState = GameState()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.statusRaw = status.rawValue
        self.awayTeam = awayTeam
        self.homeTeam = homeTeam
        self.ruleSet = ruleSet
        self.seed = seed
        self.stateJSON = Game.encodeState(state)
    }

    var status: GameStatus {
        get { GameStatus(rawValue: statusRaw) ?? .inProgress }
        set { statusRaw = newValue.rawValue }
    }

    func getState() -> GameState {
        Game.decodeState(stateJSON) ?? GameState()
    }

    func setState(_ state: GameState) {
        self.stateJSON = Game.encodeState(state)
    }

    static func encodeState(_ state: GameState) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(state)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decodeState(_ json: String) -> GameState? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GameState.self, from: data)
    }
}

@Model
final class PlayLog {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var gameId: UUID

    var inning: Int
    var halfRaw: String

    var offenseTeam: String
    var defenseTeam: String

    var batterName: String
    var pitcherName: String

    var paOutcome: String
    var pitchesCount: Int

    /// Encoded PAResult JSON, includes pitch-by-pitch + trace.
    var detailJSON: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        gameId: UUID,
        inning: Int,
        half: HalfInning,
        offenseTeam: String,
        defenseTeam: String,
        batterName: String,
        pitcherName: String,
        paOutcome: String,
        pitchesCount: Int,
        detailJSON: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.gameId = gameId
        self.inning = inning
        self.halfRaw = half.rawValue
        self.offenseTeam = offenseTeam
        self.defenseTeam = defenseTeam
        self.batterName = batterName
        self.pitcherName = pitcherName
        self.paOutcome = paOutcome
        self.pitchesCount = pitchesCount
        self.detailJSON = detailJSON
    }

    var half: HalfInning { HalfInning(rawValue: halfRaw) ?? .top }
}

