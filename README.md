# YakyuOutcome

**YakyuOutcome** is a SwiftUI iOS app that simulates baseball games (not just a single pitch), with configurable rules, teams/players management, play-by-play logs, and a simple probability-driven outcome engine. It’s designed as a practical sandbox for iterating on baseball simulation logic while keeping the UI lightweight and test-friendly.

> Primary language support: **Traditional Chinese (zh-Hant)** via `Localizable.xcstrings`.

---

## Features

### Game Simulation
- Simulate a full game with inning / half-inning flow.
- Correct end-of-game behavior:
  - Game ends when not tied after 9 innings
  - Extra innings when tied after 9
  - Skip bottom of the 9th when the home team already leads
  - Walk-off ends immediately when the home team takes the lead in the bottom half

### Configuration
- Settings screen uses **numeric inputs** (TextField) instead of sliders.
- Input validation and clamping for supported ranges (e.g., innings limits, 0–1 probability style values).

### Teams & Players
- Manage teams and players (stored locally).
- Automatic **seed/default data restore** when Teams/Players/Rules are missing (prevents blank UI after a reset).

### Logs & Debugging
- Play-by-play log view.
- Each play can display a **score snapshot** (away/home score at that moment).
- Optional “detail” information for deeper debugging (implementation-dependent).

### UX
- Haptic feedback on key actions.
- Confetti celebration effect when a game ends.

### Localization
- Uses **String Catalog**: `Localizable.xcstrings`
- Traditional Chinese coverage for key UI text and game display strings (e.g., “Top/Bottom of inning”, labels, buttons).

---

## Tech Stack
- **SwiftUI**
- **SwiftData** (local persistence)
- iOS haptics (UIKit feedback generators where appropriate)
- Lightweight effects view(s) for confetti

---

## Requirements
- Xcode 15+ (recommended)
- iOS 17+ (recommended, if using SwiftData)
- macOS with Xcode toolchain installed

---

## Getting Started

1. **Clone** this repository.
2. Open `YakyuOutcome.xcodeproj` (or `.xcworkspace` if present) in Xcode.
3. Select a development team and set a valid **Signing & Capabilities** configuration.
4. Build and run on a simulator or device.

### Important: Localization Resource
Ensure `Localizable.xcstrings` is included in the app target:
- Xcode → select `Localizable.xcstrings` → **File Inspector** → **Target Membership** → check the app target

---

## Suggested Test Checklist

### Game Rules
- Home team leading after top of 9th → confirm bottom of 9th is skipped.
- Walk-off scenario → confirm the game ends immediately when home takes the lead.
- Tie after 9 innings → confirm extra innings begin and continue until a winner exists.

### Settings
- Type values outside valid ranges → confirm values clamp correctly.
- Confirm changes affect simulation behavior as expected.

### Logs
- Confirm each play shows the correct score snapshot.
- Confirm log list remains stable after restarting app.

### Seed Data Safety
- Delete all local data (or simulate empty persistence) → confirm default Teams/Players/Rules repopulate and UI doesn’t go blank.

---

## Project Structure (high level)

> Names may vary slightly depending on your current refactor, but the app typically includes:

- `Engine.swift`  
  Core simulation loop and rule evaluation (innings, outs, end conditions, extra innings).

- `Models.swift`  
  SwiftData models such as Team/Player/Game/PlayLog (and any enums/structs used by the engine).

- `SeedData.swift`  
  Default teams/players/rules creation; auto-restore logic if database is empty.

- `SettingsView.swift`  
  Config UI (numeric TextFields + validation/clamping).

- `LiveGameView.swift` / `GameHubView.swift`  
  Main gameplay UI and controls (advance, simulate, view status).

- `LogsView.swift`  
  Play-by-play history UI, score snapshot display.

- `ConfettiView.swift` (or similar)  
  End-of-game celebration overlay.

- `Localizable.xcstrings`  
  String Catalog for localization.

---

## Localization Notes

- Add new strings using SwiftUI `Text("key")` patterns or `String(localized:)`.
- Keep keys stable; add translations in `Localizable.xcstrings`.
- Recommended format for inning display:
  - “第 {n} 局 上半 / 下半” (zh-Hant)
  - “Inning {n} (Top/Bottom)” (en)

---

## Development Tips

- Make small, isolated changes and commit frequently (especially before engine rule changes).
- If you store additional debug fields, prefer forward-compatible formats (e.g., JSON in an existing “detail” field) to avoid frequent SwiftData migrations.
- When something “disappears” in UI, first check:
  - SwiftData container setup
  - seed data restoration paths
  - localization target membership

---

## Contributing

PRs and issues are welcome—especially around:
- More realistic probability models
- Better play outcome explanations
- UI polish and accessibility
- Tests (unit tests for engine rules / end-of-game behavior)

---

## License
Add your preferred license here (MIT / Apache-2.0 / proprietary).  
If you haven’t decided yet, you can temporarily mark it as “All rights reserved”.

---

## Acknowledgements
- Baseball rules references inspired by common professional baseball game flow.
- Built for rapid iteration and learning with SwiftUI + SwiftData.
