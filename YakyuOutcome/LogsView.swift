import SwiftUI
import SwiftData

struct LogsView: View {
    @Query(sort: \PlayLog.timestamp, order: .reverse) private var logs: [PlayLog]

    var body: some View {
        NavigationStack {
            List {
                ForEach(logs) { log in
                    NavigationLink {
                        LogDetailView(log: log)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localizedFormat("%@ • Inning %lld %@", log.offenseTeam, log.inning, halfLabel(log.half, includeArrow: false)))
                                .font(.headline)
                            HStack(spacing: 6) {
                                Text(localizedFormat("%@ vs %@ • %@ • %lld pitches", log.batterName, log.pitcherName, log.paOutcome, log.pitchesCount))
                                if let score = scoreSnapshot(for: log) {
                                    Text(localizedFormat("Score %lld-%lld", score.away, score.home))
                                }
                            }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(localized("Logs"))
        }
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
    guard let pa = BaseballEngine.decodePAResult(log.detailJSON) else { return nil }
    guard let last = pa.pitches.last else { return nil }
    for step in last.trace.reversed() {
        if step.title == "Score Snapshot" {
            let away = Int(step.details["awayScore"] ?? "")
            let home = Int(step.details["homeScore"] ?? "")
            if let away, let home {
                return (away, home)
            }
        }
    }
    return nil
}
