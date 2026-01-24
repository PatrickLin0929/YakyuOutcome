import Foundation
import SwiftData

// MARK: - RNG (deterministic)
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextInt(_ upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(nextUInt64() % UInt64(upperBound))
    }

    mutating func nextDouble() -> Double {
        let x = nextUInt64() >> 11
        return Double(x) / Double(1 << 53)
    }
}

// MARK: - Engine

enum EngineError: Error, LocalizedError {
    case invalidTeamsOrLineup
    case missingRuleSet
    case gameFinished

    var errorDescription: String? {
        switch self {
        case .invalidTeamsOrLineup:
            return "Teams or lineups are not ready. Ensure both teams exist and have 9 lineup slots with assigned players."
        case .missingRuleSet:
            return "RuleSet missing. Create or assign a RuleSet first."
        case .gameFinished:
            return "Game has finished."
        }
    }
}

final class BaseballEngine {

    // MARK: Public API

    /// Simulate ONE pitch (advances state; may or may not end the PA).
    /// This returns a PitchEvent, but the caller typically uses simulatePA for logging.
    static func nextPitch(game: Game) throws -> PitchEvent {
        if game.status == .finished { throw EngineError.gameFinished }
        guard let away = game.awayTeam, let home = game.homeTeam else { throw EngineError.invalidTeamsOrLineup }
        guard let rules = game.ruleSet else { throw EngineError.missingRuleSet }

        var state = game.getState()
        try validateLineups(away: away, home: home)

        let inningPart  = UInt64(state.inning) &* 1000
        let outsPart    = UInt64(state.outs) &* 100
        let ballsPart   = UInt64(state.balls) &* 10
        let strikesPart = UInt64(state.strikes)

        let stateKey = inningPart &+ outsPart &+ ballsPart &+ strikesPart
        var rng = SplitMix64(seed: game.seed ^ stateKey)


        let (offense, defense, offenseLineupIndex) = teamsForHalfInning(state: state, away: away, home: home)
        let batterSlot = offense.sortedLineup()[offenseLineupIndex % 9]
        guard let batter = batterSlot.player else { throw EngineError.invalidTeamsOrLineup }

        // Pitcher: we treat defense slot at P if exists; otherwise first lineup slot as pitcher.
        let pitcher = defense.sortedLineup().first(where: { $0.position == .P })?.player
            ?? defense.sortedLineup().first?.player
        guard let pitcher else { throw EngineError.invalidTeamsOrLineup }

        let pitchNumberInPA = 1 // we don't track per-pitch in this method; simulatePA does.
        let pitch = simulateSinglePitch(
            pitchNumberInPA: pitchNumberInPA,
            state: &state,
            batter: batter,
            pitcher: pitcher,
            defenseTeam: defense,
            rules: rules,
            rng: &rng
        )

        // Update seed to keep future deterministic but varied
        game.seed = rng.nextUInt64()
        game.setState(state)
        return pitch
    }

    /// Simulate a FULL plate appearance and return PAResult (with pitch-by-pitch + trace), updating game state.
    static func simulatePA(game: Game, modelContext: ModelContext) throws -> PAResult {
        if game.status == .finished { throw EngineError.gameFinished }
        guard let away = game.awayTeam, let home = game.homeTeam else { throw EngineError.invalidTeamsOrLineup }
        guard let rules = game.ruleSet else { throw EngineError.missingRuleSet }
        var state = game.getState()
        try validateLineups(away: away, home: home)

        var rng = SplitMix64(seed: game.seed ^ UInt64(Date().timeIntervalSince1970.bitPattern))
        let (offense, defense, offenseLineupIndex) = teamsForHalfInning(state: state, away: away, home: home)

        let lineup = offense.sortedLineup()
        let batterSlot = lineup[offenseLineupIndex % 9]
        guard let batter = batterSlot.player else { throw EngineError.invalidTeamsOrLineup }

        let pitcher = defense.sortedLineup().first(where: { $0.position == .P })?.player
            ?? defense.sortedLineup().first?.player
        guard let pitcher else { throw EngineError.invalidTeamsOrLineup }

        // Reset count for new PA if not already reset
        if state.balls < 0 || state.strikes < 0 { state.balls = 0; state.strikes = 0 }

        var pitches: [PitchEvent] = []
        var ended = false
        var paOutcome = "?"

        var pitchNo = 0
        while !ended {
            pitchNo += 1
            var pitchEvent = simulateSinglePitch(
                pitchNumberInPA: pitchNo,
                state: &state,
                batter: batter,
                pitcher: pitcher,
                defenseTeam: defense,
                rules: rules,
                rng: &rng
            )

            // Determine PA end conditions
            if pitchEvent.endedPA {
                ended = true
                paOutcome = normalizeOutcomeFromLabel(pitchEvent.label)
            } else {
                // Count-based ends (BB / K)
                if state.balls >= 4 {
                    ended = true
                    paOutcome = "BB"
                    pitchEvent.endedPA = true
                    pitchEvent.label = "Ball (BB)"
                } else if state.strikes >= 3 {
                    ended = true
                    paOutcome = "K"
                    pitchEvent.endedPA = true
                    pitchEvent.label = "Strikeout"
                }
            }

            pitches.append(pitchEvent)
            if pitchNo > 40 { // safety
                ended = true
                paOutcome = "UNKNOWN"
            }
        }

        // Apply BB/K if ended by count but label not set
        if paOutcome == "BB" {
            applyWalk(state: &state)
        } else if paOutcome == "K" {
            state.outs += 1
        } else {
            // InPlay outcome already applied inside simulateSinglePitch
        }

        // Walk-off: bottom of last inning, home takes lead immediately ends game
        let isWalkOff = (state.half == .bottom &&
                         state.inning == rules.innings &&
                         state.homeScore > state.awayScore)
        if isWalkOff { game.status = .finished }

        // Advance lineup index on PA completion
        if state.half == .top {
            state.awayLineupIndex = (state.awayLineupIndex + 1) % 9
        } else {
            state.homeLineupIndex = (state.homeLineupIndex + 1) % 9
        }

        // Half-inning / inning transitions
        if !isWalkOff && state.outs >= 3 {
            state.outs = 0
            state.balls = 0
            state.strikes = 0
            state.bases = 0
            if state.half == .top {
                if state.inning >= rules.innings && state.homeScore > state.awayScore {
                    game.status = .finished
                } else {
                    state.half = .bottom
                }
            } else {
                if state.inning >= rules.innings && state.homeScore != state.awayScore {
                    game.status = .finished
                } else {
                    state.half = .top
                    state.inning += 1
                }
            }
        } else {
            // reset count between batters
            state.balls = 0
            state.strikes = 0
        }

        game.seed = rng.nextUInt64()
        game.setState(state)

        // Log PA (one line per PA)
        let offenseName = (state.half == .top) ? away.name : home.name
        let defenseName = (state.half == .top) ? home.name : away.name
        var scoredPitches = pitches
        if var last = scoredPitches.last {
            last.trace.append(TraceStep(
                title: "Score Snapshot",
                details: [
                    "awayScore": "\(state.awayScore)",
                    "homeScore": "\(state.homeScore)"
                ],
                roll: 0,
                range: 0,
                threshold: 0,
                picked: "\(state.awayScore)-\(state.homeScore)"
            ))
            scoredPitches[scoredPitches.count - 1] = last
        }
        let detail = encodePAResult(PAResult(outcome: paOutcome, pitches: scoredPitches))

        let log = PlayLog(
            gameId: game.id,
            inning: max(1, state.inning),
            half: state.half,
            offenseTeam: offenseName,
            defenseTeam: defenseName,
            batterName: batter.name,
            pitcherName: pitcher.name,
            paOutcome: paOutcome,
            pitchesCount: pitches.count,
            detailJSON: detail
        )
        modelContext.insert(log)

        return PAResult(outcome: paOutcome, pitches: pitches)
    }

    /// Simulate a half-inning (until 3 outs).
    static func simulateHalfInning(game: Game, modelContext: ModelContext) throws {
        var state = game.getState()
        let startHalf = state.half
        while game.status != .finished {
            let before = game.getState()
            _ = try simulatePA(game: game, modelContext: modelContext)
            let after = game.getState()
            if before.half != after.half || (before.half == startHalf && after.outs == 0 && after.bases == 0 && before.outs > 0) {
                // half-inning switched
                break
            }
            state = after
        }
    }

    /// Simulate full game (9 innings; extras not implemented).
    static func simulateGame(game: Game, modelContext: ModelContext) throws {
        guard let rules = game.ruleSet else { throw EngineError.missingRuleSet }
        while game.status != .finished {
            try simulatePA(game: game, modelContext: modelContext)
            _ = rules
        }
    }

    /// Reset a game to initial state (keeps teams, rules; clears logs via UI action).
    static func resetGame(game: Game) {
        game.status = .inProgress
        game.seed = UInt64.random(in: 1...UInt64.max)
        game.setState(GameState())
    }

    // MARK: - Pitch simulation core

    private static func simulateSinglePitch(
        pitchNumberInPA: Int,
        state: inout GameState,
        batter: Player,
        pitcher: Player,
        defenseTeam: Team,
        rules: RuleSet,
        rng: inout SplitMix64
    ) -> PitchEvent {

        var trace: [TraceStep] = []

        // 1) Zone?
        let zoneRoll = rng.nextInt(10_000) + 1
        let zoneThreshold = Int((pitcher.zoneRate.clamped01()) * 10_000.0)
        let isZone = zoneRoll <= max(0, min(10_000, zoneThreshold))
        trace.append(TraceStep(
            title: "Zone Check",
            details: [
                "pitcher.zoneRate": String(format: "%.3f", pitcher.zoneRate),
                "threshold": "\(zoneThreshold)/10000"
            ],
            roll: zoneRoll,
            range: 10_000,
            threshold: zoneThreshold,
            picked: isZone ? "IN ZONE" : "OUT OF ZONE"
        ))

        // 2) Swing decision (count adjustment: two strikes -> +10% swing, clamp)
        let baseSwing = isZone ? batter.zSwing : batter.oSwing
        let countAdj = (state.strikes >= 2) ? 1.10 : 1.00
        let swingProb = (baseSwing * countAdj).clamped01()
        let swingRoll = rng.nextInt(10_000) + 1
        let swingTh = Int(swingProb * 10_000.0)
        let didSwing = swingRoll <= swingTh
        trace.append(TraceStep(
            title: "Swing Decision",
            details: [
                "baseSwing": String(format: "%.3f", baseSwing),
                "countAdj": String(format: "%.2f", countAdj),
                "swingProb": String(format: "%.3f", swingProb)
            ],
            roll: swingRoll,
            range: 10_000,
            threshold: swingTh,
            picked: didSwing ? "SWING" : "TAKE"
        ))

        // 3) Wild pitch / passed ball (only if runners on base + out of zone)
        if !isZone && state.bases != 0 {
            let chance = didSwing ? rules.wildPitchChanceOnSwing : rules.wildPitchChanceOnTake
            let wpRoll = rng.nextInt(100_000) + 1
            let wpTh = Int(chance * 100_000.0)
            let isWP = wpRoll <= wpTh
            trace.append(TraceStep(
                title: "WP/PB Check",
                details: [
                    "bases": "\(state.bases)",
                    "chance": String(format: "%.5f", chance),
                    "policy": didSwing ? "SWING" : "TAKE"
                ],
                roll: wpRoll,
                range: 100_000,
                threshold: wpTh,
                picked: isWP ? "TRIGGERED" : "NO"
            ))

            if isWP {
                // Determine WP vs PB
                let pbRoll = rng.nextInt(10_000) + 1
                let pbTh = Int(rules.passedBallShare.clamped01() * 10_000.0)
                let isPB = pbRoll <= pbTh
                trace.append(TraceStep(
                    title: "WP vs PB",
                    details: [
                        "passedBallShare": String(format: "%.3f", rules.passedBallShare),
                        "catcher.catching": String(format: "%.3f", catcherRating(team: defenseTeam))
                    ],
                    roll: pbRoll,
                    range: 10_000,
                    threshold: pbTh,
                    picked: isPB ? "PASSED BALL" : "WILD PITCH"
                ))

                // Advance runners one base (simplified), score if runner on 3rd
                advanceAllRunnersOne(state: &state)

                return PitchEvent(
                    pitchNumberInPA: pitchNumberInPA,
                    label: isPB ? "Passed Ball" : "Wild Pitch",
                    endedPA: false,
                    trace: trace
                )
            }
        }

        // 4) If take:
        if !didSwing {
            if isZone {
                // Called strike
                state.strikes += 1
                return PitchEvent(pitchNumberInPA: pitchNumberInPA, label: "Called Strike", endedPA: false, trace: trace)
            } else {
                // Ball
                state.balls += 1
                return PitchEvent(pitchNumberInPA: pitchNumberInPA, label: "Ball", endedPA: false, trace: trace)
            }
        }

        // 5) Swing -> contact?
        let baseContact = isZone ? batter.zContact : batter.oContact
        // whiffInduce reduces contact (simple blend)
        let contactProb = (baseContact * (1.0 - 0.20 * pitcher.whiffInduce.clamped01())).clamped01()
        let contactRoll = rng.nextInt(10_000) + 1
        let contactTh = Int(contactProb * 10_000.0)
        let didContact = contactRoll <= contactTh
        trace.append(TraceStep(
            title: "Contact Check",
            details: [
                "baseContact": String(format: "%.3f", baseContact),
                "pitcher.whiffInduce": String(format: "%.3f", pitcher.whiffInduce),
                "contactProb": String(format: "%.3f", contactProb)
            ],
            roll: contactRoll,
            range: 10_000,
            threshold: contactTh,
            picked: didContact ? "CONTACT" : "SWING & MISS"
        ))

        if !didContact {
            state.strikes += 1
            if state.strikes >= 3 {
                return PitchEvent(pitchNumberInPA: pitchNumberInPA, label: "Swinging Strike (K)", endedPA: true, trace: trace)
            }
            return PitchEvent(pitchNumberInPA: pitchNumberInPA, label: "Swinging Strike", endedPA: false, trace: trace)
        }

        // 6) Contact -> foul vs in-play
        let foulProb = rules.foulRateOnContact.clamped01()
        let foulRoll = rng.nextInt(10_000) + 1
        let foulTh = Int(foulProb * 10_000.0)
        let isFoul = foulRoll <= foulTh
        trace.append(TraceStep(
            title: "Foul vs In-Play",
            details: [
                "foulRateOnContact": String(format: "%.3f", foulProb)
            ],
            roll: foulRoll,
            range: 10_000,
            threshold: foulTh,
            picked: isFoul ? "FOUL" : "IN PLAY"
        ))

        if isFoul {
            // strikes increment unless already 2 and rule keeps it at 2
            if state.strikes < 2 {
                state.strikes += 1
            } else if !rules.twoStrikeFoulKeepsTwoStrikes {
                state.strikes += 1
            }
            return PitchEvent(pitchNumberInPA: pitchNumberInPA, label: "Foul Ball", endedPA: false, trace: trace)
        }

        // 7) In play resolution (ends PA)
        let inPlayLabel = resolveBallInPlay(state: &state, batter: batter, pitcher: pitcher, defenseTeam: defenseTeam, rules: rules, rng: &rng, trace: &trace)
        return PitchEvent(pitchNumberInPA: pitchNumberInPA, label: inPlayLabel, endedPA: true, trace: trace)
    }

    private static func resolveBallInPlay(
        state: inout GameState,
        batter: Player,
        pitcher: Player,
        defenseTeam: Team,
        rules: RuleSet,
        rng: inout SplitMix64,
        trace: inout [TraceStep]
    ) -> String {
        // Choose batted-ball type
        let total = batter.gbRate + batter.fbRate + batter.ldRate + batter.puRate
        let gb = (batter.gbRate / max(0.0001, total))
        let fb = (batter.fbRate / max(0.0001, total))
        let ld = (batter.ldRate / max(0.0001, total))
        let pu = (batter.puRate / max(0.0001, total))

        let tRoll = rng.nextInt(10_000) + 1
        let gbTh = Int(gb * 10_000.0)
        let fbTh = gbTh + Int(fb * 10_000.0)
        let ldTh = fbTh + Int(ld * 10_000.0)
        let type: String
        if tRoll <= gbTh { type = "GB" }
        else if tRoll <= fbTh { type = "FB" }
        else if tRoll <= ldTh { type = "LD" }
        else { type = "PU" }

        trace.append(TraceStep(
            title: "Batted Ball Type",
            details: [
                "GB": String(format: "%.3f", gb),
                "FB": String(format: "%.3f", fb),
                "LD": String(format: "%.3f", ld),
                "PU": String(format: "%.3f", pu)
            ],
            roll: tRoll,
            range: 10_000,
            threshold: type == "GB" ? gbTh : (type == "FB" ? fbTh : (type == "LD" ? ldTh : 10_000)),
            picked: type
        ))

        // Determine hit chance (alignment affects GB only, simplified)
        var hitChance = batter.hitRate.clamped01()
        let alignment = rules.defaultAlignment
        if type == "GB" {
            switch alignment {
            case .normal:
                break
            case .shiftLeft, .shiftRight:
                hitChance *= rules.shiftGBHitMultiplier.clamped(0.50, 1.20)
            case .infieldIn:
                hitChance *= rules.infieldInGBHitMultiplier.clamped(0.80, 1.60)
            }
        }

        // defense overall reduces hit chance (simplified)
        let defenseFactor = (0.85 + 0.30 * (1.0 - avgDefenseFielding(team: defenseTeam))).clamped(0.70, 1.10)
        hitChance *= defenseFactor
        hitChance = hitChance.clamped01()

        let hitRoll = rng.nextInt(10_000) + 1
        let hitTh = Int(hitChance * 10_000.0)
        let isHit = hitRoll <= hitTh
        trace.append(TraceStep(
            title: "Hit Check",
            details: [
                "batter.hitRate": String(format: "%.3f", batter.hitRate),
                "alignment": alignment.rawValue,
                "defFactor": String(format: "%.3f", defenseFactor),
                "hitChanceFinal": String(format: "%.3f", hitChance)
            ],
            roll: hitRoll,
            range: 10_000,
            threshold: hitTh,
            picked: isHit ? "HIT" : "NO HIT"
        ))

        if isHit {
            // Resolve 1B/2B/3B/HR (more likely HR on FB/LD, rare on GB)
            if type == "FB" || type == "LD" {
                let hrShare = batter.hrShare.clamped(0.0, 0.60)
                let dblShare = batter.doubleShare.clamped(0.0, 0.80)
                let tplShare = batter.tripleShare.clamped(0.0, 0.20)

                let xRoll = rng.nextInt(10_000) + 1
                let hrTh = Int(hrShare * 10_000.0)
                let dblTh = hrTh + Int(dblShare * 10_000.0)
                let tplTh = dblTh + Int(tplShare * 10_000.0)

                let outcome: String
                if xRoll <= hrTh { outcome = "HR" }
                else if xRoll <= dblTh { outcome = "2B" }
                else if xRoll <= tplTh { outcome = "3B" }
                else { outcome = "1B" }

                trace.append(TraceStep(
                    title: "Hit Type",
                    details: [
                        "hrShare": String(format: "%.3f", hrShare),
                        "doubleShare": String(format: "%.3f", dblShare),
                        "tripleShare": String(format: "%.3f", tplShare)
                    ],
                    roll: xRoll,
                    range: 10_000,
                    threshold: outcome == "HR" ? hrTh : (outcome == "2B" ? dblTh : (outcome == "3B" ? tplTh : 10_000)),
                    picked: outcome
                ))

                applyHit(outcome: outcome, state: &state, runnerAgg: rules.runnerAggressiveness, rng: &rng)
                addRunsFromStateToScore(state: &state, half: state.half, runs: 0) // runs already added in applyHit
                return "In Play: \(outcome)"
            } else {
                // GB hit tends to be 1B
                applyHit(outcome: "1B", state: &state, runnerAgg: rules.runnerAggressiveness, rng: &rng)
                return "In Play: 1B"
            }
        }

        // No hit -> possible error before out (simplified)
        // Error chance depends on defense fielding; if error then batter reaches.
        let errBaseChance = 0.02 + 0.06 * (1.0 - avgDefenseFielding(team: defenseTeam))
        let errRoll = rng.nextInt(10_000) + 1
        let errTh = Int(errBaseChance.clamped01() * 10_000.0)
        let isError = errRoll <= errTh
        trace.append(TraceStep(
            title: "Error Check",
            details: [
                "avgDefenseFielding": String(format: "%.3f", avgDefenseFielding(team: defenseTeam)),
                "errorChance": String(format: "%.3f", errBaseChance)
            ],
            roll: errRoll,
            range: 10_000,
            threshold: errTh,
            picked: isError ? "ERROR" : "NO ERROR"
        ))

        if isError {
            // batter reaches on error; runners may advance 1 base
            applyReachOnError(state: &state, runnerAgg: rules.runnerAggressiveness, rng: &rng)
            return "In Play: E"
        }

        // Out types: GB -> GO, FB/PU -> FO, LD -> LO
        if type == "GB" {
            // Handle force/double-play (simplified), and optional throw-home policy if runner on 3rd
            let label = resolveGroundOut(state: &state, rules: rules, rng: &rng, trace: &trace)
            return "In Play: \(label)"
        } else if type == "PU" || type == "FB" {
            state.outs += 1
            return "In Play: FO"
        } else {
            state.outs += 1
            return "In Play: LO"
        }
    }

    // MARK: - Runner / scoring helpers

    private static func applyWalk(state: inout GameState) {
        // walk: force if needed
        // If 1B empty -> batter to 1B
        // else if 1B occupied -> force chain
        let on1 = (state.bases & 1) != 0
        let on2 = (state.bases & 2) != 0
        let on3 = (state.bases & 4) != 0

        if !on1 {
            state.bases |= 1
            return
        }

        // 1B occupied
        if on1 && !on2 {
            state.bases |= 2
            state.bases |= 1
            return
        }

        // 1B + 2B occupied
        if on1 && on2 && !on3 {
            state.bases |= 4
            state.bases |= 2
            state.bases |= 1
            return
        }

        // bases loaded -> score 1
        if on1 && on2 && on3 {
            addRuns(state: &state, runs: 1)
            state.bases |= 7
        }
    }

    private static func applyHit(outcome: String, state: inout GameState, runnerAgg: Double, rng: inout SplitMix64) {
        // Very simplified advancement model:
        // 1B: runners advance 1, runner on 2 may score depending on aggressiveness
        // 2B: runners advance 2; runner on 1 may score depending
        // 3B: all score, batter to 3
        // HR: all score, bases clear

        let on1 = (state.bases & 1) != 0
        let on2 = (state.bases & 2) != 0
        let on3 = (state.bases & 4) != 0

        func score(_ n: Int) { addRuns(state: &state, runs: n) }

        switch outcome {
        case "HR":
            var runs = 1
            if on1 { runs += 1 }
            if on2 { runs += 1 }
            if on3 { runs += 1 }
            score(runs)
            state.bases = 0
        case "3B":
            var runs = 0
            if on1 { runs += 1 }
            if on2 { runs += 1 }
            if on3 { runs += 1 }
            score(runs)
            state.bases = 4
        case "2B":
            // runner on 3 scores, runner on 2 scores, runner on 1 maybe to 3 or score
            var runs = 0
            if on3 { runs += 1 }
            if on2 { runs += 1 }

            var newBases = 0
            // batter to 2B
            newBases |= 2

            if on1 {
                // decide if runner scores from 1 on a double (aggressiveness)
                let pScore = (0.15 + 0.60 * runnerAgg.clamped01()).clamped01()
                let r = rng.nextDouble()
                if r < pScore {
                    runs += 1
                } else {
                    // to 3B
                    newBases |= 4
                }
            }

            score(runs)
            state.bases = newBases
        default: // "1B"
            var runs = 0
            var newBases = 0
            // batter to 1B
            newBases |= 1

            if on3 { runs += 1 } // score from 3
            if on2 {
                // decide if runner scores from 2 on single
                let pScore = (0.20 + 0.70 * runnerAgg.clamped01()).clamped01()
                if rng.nextDouble() < pScore { runs += 1 } else { newBases |= 4 }
            }
            if on1 {
                // runner from 1 to 2; sometimes to 3 (aggressive)
                let pTo3 = (0.05 + 0.35 * runnerAgg.clamped01()).clamped01()
                if rng.nextDouble() < pTo3 { newBases |= 4 } else { newBases |= 2 }
            }

            score(runs)
            state.bases = newBases
        }
    }

    private static func applyReachOnError(state: inout GameState, runnerAgg: Double, rng: inout SplitMix64) {
        // batter to 1B, runners advance 1 base; runner on 3 scores
        let on1 = (state.bases & 1) != 0
        let on2 = (state.bases & 2) != 0
        let on3 = (state.bases & 4) != 0

        var runs = 0
        if on3 { runs += 1 }

        var newBases = 1 // batter to 1B
        if on2 { newBases |= 4 }
        if on1 { newBases |= 2 }

        addRuns(state: &state, runs: runs)
        state.bases = newBases
    }

    private static func resolveGroundOut(state: inout GameState, rules: RuleSet, rng: inout SplitMix64, trace: inout [TraceStep]) -> String {
        // Simplified ground-out resolver:
        // - If runner on 3rd: decide throw home by policy (may get out at home or 1B)
        // - Double play attempt if runner on 1 and outs < 2 and policy allows

        let on1 = (state.bases & 1) != 0
        let on2 = (state.bases & 2) != 0
        let on3 = (state.bases & 4) != 0

        // Throw home decision
        if on3 {
            let decision = shouldThrowHome(state: state, rules: rules)
            trace.append(TraceStep(
                title: "Throw Home Decision",
                details: [
                    "throwHomePolicy": rules.throwHomePolicy.rawValue,
                    "outs": "\(state.outs)",
                    "scoreContext": scoreContextLabel(state: state)
                ],
                roll: decision ? 1 : 0,
                range: 1,
                threshold: 1,
                picked: decision ? "THROW HOME" : "TAKE SURE OUT"
            ))

            if decision {
                // 60% out at home, else safe at home + batter out at 1
                let roll = rng.nextInt(10_000) + 1
                let th = 6000
                let outAtHome = roll <= th
                trace.append(TraceStep(
                    title: "Play at Home",
                    details: ["outProb": "0.60"],
                    roll: roll,
                    range: 10_000,
                    threshold: th,
                    picked: outAtHome ? "OUT AT HOME" : "SAFE (RUN SCORES)"
                ))

                if outAtHome {
                    // runner from 3 out, batter out at 1 is not guaranteed; assume just 1 out total at home
                    state.outs += 1
                    // remove runner on 3
                    state.bases &= ~4
                    return "GO (Out at Home)"
                } else {
                    // run scores, batter out at 1
                    addRuns(state: &state, runs: 1)
                    state.outs += 1
                    // runner on 3 scored; clear 3
                    state.bases &= ~4
                    // other runners: advance? keep simple: hold
                    return "GO (RBI, Out at 1B)"
                }
            }
        }

        // Double play attempt
        if on1 && state.outs < 2 && rules.tryDoublePlayPolicy {
            let dpRoll = rng.nextInt(10_000) + 1
            // dp chance 35% baseline
            let dpTh = 3500
            let isDP = dpRoll <= dpTh
            trace.append(TraceStep(
                title: "Double Play Attempt",
                details: ["dpProb": "0.35"],
                roll: dpRoll,
                range: 10_000,
                threshold: dpTh,
                picked: isDP ? "DP" : "NO DP"
            ))

            if isDP {
                state.outs += 2
                // batter and runner on 1 out; clear 1
                state.bases &= ~1
                // other runners hold (simplified)
                return "DP"
            } else {
                // just batter out, runner on 1 forced to 2 if open
                state.outs += 1
                // force runner advance
                if (state.bases & 2) == 0 {
                    state.bases &= ~1
                    state.bases |= 2
                    return "GO (FC 2B)"
                }
                return "GO"
            }
        }

        // Otherwise, take sure out at 1B
        state.outs += 1
        // if runner on 1 and 2 empty, runner forced to 2
        if on1 && (state.bases & 2) == 0 {
            state.bases &= ~1
            state.bases |= 2
            return "GO (FC 2B)"
        }
        return "GO"
    }

    private static func shouldThrowHome(state: GameState, rules: RuleSet) -> Bool {
        switch rules.throwHomePolicy {
        case .never: return false
        case .always: return true
        case .situational:
            // If tie or behind in late innings OR outs < 2, more likely throw home
            let ctx = scoreContextLabel(state: state)
            if state.outs < 2 { return true }
            if ctx == "TIE" || ctx == "AWAY BEHIND" || ctx == "HOME BEHIND" { return true }
            return false
        }
    }

    private static func addRuns(state: inout GameState, runs: Int) {
        guard runs > 0 else { return }
        if state.half == .top { state.awayScore += runs }
        else { state.homeScore += runs }
    }

    private static func addRunsFromStateToScore(state: inout GameState, half: HalfInning, runs: Int) {
        // placeholder (kept for compatibility)
        _ = half
        _ = runs
    }

    private static func advanceAllRunnersOne(state: inout GameState) {
        let on1 = (state.bases & 1) != 0
        let on2 = (state.bases & 2) != 0
        let on3 = (state.bases & 4) != 0

        var newBases = 0
        if on3 { addRuns(state: &state, runs: 1) }
        if on2 { newBases |= 4 }
        if on1 { newBases |= 2 }
        state.bases = newBases
    }

    // MARK: - Team helpers

    private static func teamsForHalfInning(state: GameState, away: Team, home: Team) -> (offense: Team, defense: Team, offenseLineupIndex: Int) {
        if state.half == .top {
            return (away, home, state.awayLineupIndex)
        } else {
            return (home, away, state.homeLineupIndex)
        }
    }

    private static func validateLineups(away: Team, home: Team) throws {
        let a = away.sortedLineup()
        let h = home.sortedLineup()
        guard a.count >= 9, h.count >= 9 else { throw EngineError.invalidTeamsOrLineup }
        for i in 0..<9 {
            if a[i].player == nil || h[i].player == nil { throw EngineError.invalidTeamsOrLineup }
        }
    }

    private static func catcherRating(team: Team) -> Double {
        let c = team.sortedLineup().first(where: { $0.position == .C })?.player
        return (c?.catching ?? 0.50).clamped01()
    }

    private static func avgDefenseFielding(team: Team) -> Double {
        let slots = team.sortedLineup().prefix(9)
        let vals = slots.compactMap { $0.player?.fielding }
        guard !vals.isEmpty else { return 0.60 }
        return (vals.reduce(0,+) / Double(vals.count)).clamped01()
    }

    private static func scoreContextLabel(state: GameState) -> String {
        if state.awayScore == state.homeScore { return "TIE" }
        if state.half == .top {
            // away batting
            return state.awayScore < state.homeScore ? "AWAY BEHIND" : "AWAY AHEAD"
        } else {
            // home batting
            return state.homeScore < state.awayScore ? "HOME BEHIND" : "HOME AHEAD"
        }
    }

    // MARK: - Encoding helpers

    static func encodePAResult(_ pa: PAResult) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = (try? enc.encode(pa)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decodePAResult(_ json: String) -> PAResult? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PAResult.self, from: data)
    }

    private static func normalizeOutcomeFromLabel(_ label: String) -> String {
        if label.contains("HR") { return "HR" }
        if label.contains("3B") { return "3B" }
        if label.contains("2B") { return "2B" }
        if label.contains("1B") { return "1B" }
        if label.contains("DP") { return "DP" }
        if label.contains("E") { return "E" }
        if label.contains("FO") { return "FO" }
        if label.contains("LO") { return "LO" }
        if label.contains("GO") { return "GO" }
        if label.contains("Strikeout") || label.contains("K") { return "K" }
        if label.contains("Ball (BB)") { return "BB" }
        return label
    }
}

// MARK: - Utils

extension Double {
    func clamped(_ a: Double, _ b: Double) -> Double { min(max(self, a), b) }
    func clamped01() -> Double { clamped(0.0, 1.0) }
}
