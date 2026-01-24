//
//  YakyuOutcomeApp.swift
//  YakyuOutcome
//
//  Created by 林沛宇 on 2026/1/17.
//

import SwiftUI
import SwiftData

@main
struct YakyuOutcomeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Player.self,
            Team.self,
            LineupSlot.self,
            RuleSet.self,
            Game.self,
            PlayLog.self
        ])
    }
}
