# CHING iOS Phase 4 — Visual System + Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the locked visual system (Bodoni `ching!` logo, Cochin body, paper/ink 1-bit palette, stamp buttons, "safes" vocabulary), extract a dedicated Settings screen reached from a gear icon on the Game screen, and ship light + dark mode together. Difficulty migrates off `GameStore` onto a new `SettingsStore`. No engine changes.

**Architecture:** Three new files (`SettingsStore.swift`, `DesignSystem.swift`, `SettingsView.swift`) plus modifications to `CHINGApp.swift`, `GameStore.swift`, `GameView.swift`, and `GameStoreTests.swift`. One new test file (`SettingsStoreTests.swift`). Settings persist via UserDefaults. Navigation via `NavigationStack` with `SettingsView` pushed from a gear icon. Light + dark mode handled by a `UIColor(dynamicProvider:)`-backed palette in `DesignSystem.swift` so `Color.paper` / `Color.ink` / `Color.dimInk` track the runtime `userInterfaceStyle` automatically.

**Tech Stack:** Swift 5.10 / SwiftUI / iOS 17+, `@Observable` macro, `NavigationStack`, `@Environment(\.colorScheme)`, `UIColor(dynamicProvider:)` for adaptive colors, `UserDefaults` for persistence, XCTest.

---

## Spec reference

Full design at `docs/superpowers/specs/2026-06-06-phase-4-visual-system-design.md`. Key facts the plan assumes:

- Palette: light = paper `#FAF8F3` / ink `#1A1A1A` / dim ink `#6B6B6B`; dark = inverse, dim ink `#9A9A9A`.
- Typography: Bodoni 72 (PostScript family `BodoniSvtyTwoITCTT`) for logo + stamp button text + Settings nav title; Cochin (PostScript family `Cochin`) for everything else.
- Three persisted user prefs: `ching.difficulty` (existing), `ching.colorMode` (new), `ching.reducedMotion` (new).
- Vocabulary: title `ching!`, section `Safes`, `Vaults` (unchanged), `Steal Jones's safe` for the bank-label-when-stealing, vault names mixed-case (`Jones`, `Bot 03`).
- Hand-rolled `StampSegmented` and `StampToggle` controls (do not use system `Picker(.segmented)` or `Toggle`).
- Press animation on stamp buttons is optional polish; ship without if fiddly.
- Engine untouched. All 32 engine tests stay green.

CSS mockups (layout/hierarchy reference only, not pixel truth) live at `.superpowers/brainstorm/29202-1780737747/content/` — `layout-direction-v2.html`, `typography-applied.html`, `safes-vocabulary.html`, `settings-screen.html`.

---

## File structure

```
ios/CHING/CHING/
├── CHINGApp.swift           # modified: NavigationStack + owns both stores + preferredColorScheme
├── DesignSystem.swift       # NEW: palette, fonts, stampButton ButtonStyle
├── GameStore.swift          # modified: difficulty migrates out, settings: SettingsStore injected
├── SettingsStore.swift      # NEW: ColorMode enum + SettingsStore @Observable
├── GameView.swift           # modified: vocabulary + layout + stamp treatment + gear nav link
└── SettingsView.swift       # NEW: SettingsView + StampSegmented + StampToggle + AboutSheet

ios/CHING/CHINGTests/
├── GameStoreTests.swift     # modified: difficulty tests move out, makeStore() helper
└── SettingsStoreTests.swift # NEW: 6 tests (default + round-trip for each of 3 properties)
```

The Phase 3 single-file-per-major-concern pattern continues. `GameView.swift` and `SettingsView.swift` each contain multiple nested `View` types; that's fine because they all serve a single screen.

---

## Test command reference

```bash
cd /Users/bramvanoost/Code/game-ching && xcodebuild test \
  -project ios/CHING/CHING.xcodeproj \
  -scheme CHING \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:CHINGTests \
  2>&1 | grep -E "Test Case|passed|failed|TEST|error:" | tail -20
```

Build command (no tests):

```bash
cd /Users/bramvanoost/Code/game-ching && xcodebuild \
  -project ios/CHING/CHING.xcodeproj \
  -scheme CHING \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  build 2>&1 | grep -E "error:|BUILD" | tail -5
```

Install + relaunch:

```bash
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name CHING.app -path "*Debug-iphonesimulator*" -print -quit)
xcrun simctl install booted "$APP_PATH"
xcrun simctl terminate booted com.fastronaut.CHING 2>/dev/null
xcrun simctl launch booted com.fastronaut.CHING
```

If simulator not booted:

```bash
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
open -a Simulator
```

---

## Task 1: Create `SettingsStore` + `ColorMode` + persistence tests

**Files:**
- Create: `ios/CHING/CHING/SettingsStore.swift`
- Create: `ios/CHING/CHINGTests/SettingsStoreTests.swift`

At this point `GameStore` still owns its `difficulty` property and persistence. The new `SettingsStore` owns its own copy of all three prefs and is ready to be wired in Task 2. Both stores coexist briefly; Task 2 removes the duplication.

- [ ] **Step 1: Create `SettingsStoreTests.swift` with the full test suite**

Write `ios/CHING/CHINGTests/SettingsStoreTests.swift`:

```swift
import XCTest
@testable import CHING

@MainActor
final class SettingsStoreTests: XCTestCase {
    private static let difficultyKey = "ching.difficulty"
    private static let colorModeKey = "ching.colorMode"
    private static let reducedMotionKey = "ching.reducedMotion"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
        UserDefaults.standard.removeObject(forKey: Self.colorModeKey)
        UserDefaults.standard.removeObject(forKey: Self.reducedMotionKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
        UserDefaults.standard.removeObject(forKey: Self.colorModeKey)
        UserDefaults.standard.removeObject(forKey: Self.reducedMotionKey)
        super.tearDown()
    }

    func test_difficulty_defaultIsNormal() {
        let store = SettingsStore()
        XCTAssertEqual(store.difficulty, .normal)
    }

    func test_difficulty_persistsAcrossInstances() {
        let a = SettingsStore()
        a.difficulty = .hard
        let b = SettingsStore()
        XCTAssertEqual(b.difficulty, .hard)
    }

    func test_colorMode_defaultIsSystem() {
        let store = SettingsStore()
        XCTAssertEqual(store.colorMode, .system)
    }

    func test_colorMode_persistsAcrossInstances() {
        let a = SettingsStore()
        a.colorMode = .dark
        let b = SettingsStore()
        XCTAssertEqual(b.colorMode, .dark)
    }

    func test_reducedMotion_defaultIsFalse() {
        let store = SettingsStore()
        XCTAssertFalse(store.reducedMotion)
    }

    func test_reducedMotion_persistsAcrossInstances() {
        let a = SettingsStore()
        a.reducedMotion = true
        let b = SettingsStore()
        XCTAssertTrue(b.reducedMotion)
    }
}
```

- [ ] **Step 2: Run tests, watch them fail**

Run the canonical test command. Expected: compile failure (`SettingsStore` and `ColorMode` are not yet defined).

- [ ] **Step 3: Create `SettingsStore.swift`**

Write `ios/CHING/CHING/SettingsStore.swift`:

```swift
import Foundation
import Observation
import SwiftUI

enum ColorMode: String, Codable, CaseIterable {
    case system, light, dark

    var preferredScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    private static let difficultyKey = "ching.difficulty"
    private static let colorModeKey = "ching.colorMode"
    private static let reducedMotionKey = "ching.reducedMotion"

    var difficulty: Difficulty {
        didSet {
            UserDefaults.standard.set(difficulty.rawValue, forKey: Self.difficultyKey)
        }
    }

    var colorMode: ColorMode {
        didSet {
            UserDefaults.standard.set(colorMode.rawValue, forKey: Self.colorModeKey)
        }
    }

    var reducedMotion: Bool {
        didSet {
            UserDefaults.standard.set(reducedMotion, forKey: Self.reducedMotionKey)
        }
    }

    init() {
        let rawDiff = UserDefaults.standard.string(forKey: Self.difficultyKey) ?? ""
        self.difficulty = Difficulty(rawValue: rawDiff) ?? .normal

        let rawMode = UserDefaults.standard.string(forKey: Self.colorModeKey) ?? ""
        self.colorMode = ColorMode(rawValue: rawMode) ?? .system

        // Bool default returns false when key is absent; explicitly use that.
        self.reducedMotion = UserDefaults.standard.bool(forKey: Self.reducedMotionKey)
    }
}
```

- [ ] **Step 4: Run tests, watch them pass**

Run the canonical test command. Expected: 6 new `SettingsStoreTests` pass plus all 10 existing `GameStoreTests`.

- [ ] **Step 5: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/SettingsStore.swift ios/CHING/CHINGTests/SettingsStoreTests.swift && \
  git commit -m "ios: SettingsStore with difficulty + colorMode + reducedMotion"
```

---

## Task 2: Migrate `difficulty` off `GameStore` onto `SettingsStore`

**Files:**
- Modify: `ios/CHING/CHING/GameStore.swift`
- Modify: `ios/CHING/CHINGTests/GameStoreTests.swift`

`GameStore` drops its own difficulty property and persistence. `init` takes a `SettingsStore` reference. `currentAIDifficulty` reads from the injected `SettingsStore`. Existing `GameStoreTests` adjust to inject a fresh `SettingsStore`. The two Phase 3 difficulty tests on `GameStoreTests` (default-is-normal, persists-across-instances) are deleted (already covered by `SettingsStoreTests`). `CHINGApp.swift` and `GameView.swift` break at this task; Task 3 fixes them.

- [ ] **Step 1: Update `GameStoreTests` to inject `SettingsStore`**

Edit `ios/CHING/CHINGTests/GameStoreTests.swift`. Replace the class opening:

```swift
@MainActor
final class GameStoreTests: XCTestCase {
    private static let difficultyKey = "ching.difficulty"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
        super.tearDown()
    }

    func test_init_setsUpThreePlayersHumanTurnRollPhase() {
```

with:

```swift
@MainActor
final class GameStoreTests: XCTestCase {
    private static let difficultyKey = "ching.difficulty"
    private static let colorModeKey = "ching.colorMode"
    private static let reducedMotionKey = "ching.reducedMotion"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
        UserDefaults.standard.removeObject(forKey: Self.colorModeKey)
        UserDefaults.standard.removeObject(forKey: Self.reducedMotionKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
        UserDefaults.standard.removeObject(forKey: Self.colorModeKey)
        UserDefaults.standard.removeObject(forKey: Self.reducedMotionKey)
        super.tearDown()
    }

    private func makeStore(seed: UInt32 = 1) -> GameStore {
        GameStore(seed: seed, settings: SettingsStore())
    }

    func test_init_setsUpThreePlayersHumanTurnRollPhase() {
```

Delete the two Phase 3 difficulty tests (their replacements live in `SettingsStoreTests`):

```swift
    func test_difficulty_defaultIsNormalOnFirstLaunch() {
        let store = GameStore(seed: 1)
        XCTAssertEqual(store.difficulty, .normal)
    }

    func test_difficulty_persistsAcrossInstances() {
        let store1 = GameStore(seed: 1)
        store1.difficulty = .hard
        let store2 = GameStore(seed: 2)
        XCTAssertEqual(store2.difficulty, .hard)
    }
```

Replace every remaining `GameStore(seed: 1)` or `GameStore(seed:)` call inside test bodies with `makeStore(seed: 1)` (or `makeStore()`). The affected tests:

- `test_init_setsUpThreePlayersHumanTurnRollPhase`
- `test_apply_rollAdvancesPhaseOrTurn`
- `test_newGame_resetsState`
- `test_runAIIfNeeded_isNoOpOnHumanTurn`
- `test_runAIIfNeeded_reduceMotionRunsInstantly`
- `test_bankActionLabel_pointsAtFirstRivalWithMatchingTop`
- `test_fullThreePlayerGameTerminates`

For each, change `let store = GameStore(seed: 1)` → `let store = makeStore(seed: 1)` (or `makeStore()` for seedless). The body otherwise stays the same.

`test_difficulty_modifierTable` does not call `GameStore`, leave it.

- [ ] **Step 2: Run tests, watch them fail**

Run the canonical test command. Expected: compile failure — `GameStore.init(seed:settings:)` does not exist yet.

- [ ] **Step 3: Refactor `GameStore.swift`**

In `ios/CHING/CHING/GameStore.swift`:

Delete this block:

```swift
    private static let difficultyKey = "ching.difficulty"

    var difficulty: Difficulty {
        didSet {
            UserDefaults.standard.set(difficulty.rawValue, forKey: Self.difficultyKey)
        }
    }
```

Add a private settings reference. Replace:

```swift
    private(set) var state: State
    private var rng: Mulberry32
```

with:

```swift
    private(set) var state: State
    private var rng: Mulberry32
    private let settings: SettingsStore
```

Replace the existing `init(seed:)`:

```swift
    init(seed: UInt32) {
        self.rng = Mulberry32(seed: seed)
        self.state = initialState(playerIds: ["YOU", "JONES", "BOT 03"])
        let raw = UserDefaults.standard.string(forKey: Self.difficultyKey) ?? ""
        self.difficulty = Difficulty(rawValue: raw) ?? .normal
    }

    convenience init() {
        self.init(seed: UInt32.random(in: 1...UInt32.max))
    }
```

with:

```swift
    init(seed: UInt32, settings: SettingsStore) {
        self.rng = Mulberry32(seed: seed)
        self.settings = settings
        self.state = initialState(playerIds: ["YOU", "JONES", "BOT 03"])
    }

    convenience init(settings: SettingsStore) {
        self.init(seed: UInt32.random(in: 1...UInt32.max), settings: settings)
    }
```

Update `currentAIDifficulty` to read from `settings`:

```swift
    var currentAIDifficulty: CHINGEngine.Difficulty? {
        guard !isHumanTurn else { return nil }
        let base = baseDiscipline[state.current] ?? 0.5
        let adjusted = max(0, min(1, base + settings.difficulty.modifier))
        return CHINGEngine.Difficulty(discipline: adjusted)
    }
```

- [ ] **Step 4: Run tests, watch the test target pass and the app target build break**

Run the canonical test command. Expected: tests pass. The `CHING` app target may print compile errors for `GameView.swift` and `CHINGApp.swift` (the old `GameStore()` zero-arg init is no longer present). These are fixed in Task 3.

If the test command fails because the app target doesn't compile, that's expected — the test target compiles independently. If the test errors specifically mention `GameStoreTests`, fix those before moving on.

- [ ] **Step 5: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/GameStore.swift ios/CHING/CHINGTests/GameStoreTests.swift && \
  git commit -m "ios: GameStore reads difficulty from injected SettingsStore"
```

---

## Task 3: `DesignSystem.swift` — palette, fonts, stamp button

**Files:**
- Create: `ios/CHING/CHING/DesignSystem.swift`

Adaptive light/dark colors backed by `UIColor(dynamicProvider:)`. Font helpers with Apple PostScript names for the bundled families. `StampButtonStyle` for primary + secondary stamp buttons.

- [ ] **Step 1: Create the file**

Write `ios/CHING/CHING/DesignSystem.swift`:

```swift
import SwiftUI
import UIKit

extension Color {
    /// Warm cream in light mode, near-black in dark mode.
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)
            : UIColor(red: 250/255, green: 248/255, blue: 243/255, alpha: 1)
    })

    /// Near-black in light mode, warm cream in dark mode. The inverse of `paper`.
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 250/255, green: 248/255, blue: 243/255, alpha: 1)
            : UIColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)
    })

    /// Muted secondary text. Used for empty placeholders, "soon" tags, dim labels.
    static let dimInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 154/255, green: 154/255, blue: 154/255, alpha: 1)
            : UIColor(red: 107/255, green: 107/255, blue: 107/255, alpha: 1)
    })
}

extension Font {
    /// Cochin, the body face for numerals + labels + names.
    static func cochin(_ size: CGFloat) -> Font {
        .custom("Cochin", size: size)
    }

    /// Cochin Italic, used for italic small-caps labels and the active-seat indicator.
    static func cochinItalic(_ size: CGFloat) -> Font {
        .custom("Cochin-Italic", size: size)
    }

    /// Bodoni 72 Book, the display face for the logo + stamp button text + Settings nav title.
    static func bodoni(_ size: CGFloat) -> Font {
        .custom("BodoniSvtyTwoITCTT-Book", size: size)
    }

    /// Bodoni 72 Book Italic, used for the `ching!` title.
    static func bodoniItalic(_ size: CGFloat) -> Font {
        .custom("BodoniSvtyTwoITCTT-BookIta", size: size)
    }
}

/// 2pt hard offset shadow with no blur. The signature "stamp on paper" effect.
struct StampShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: Color.ink, radius: 0, x: 2, y: 2)
    }
}

extension View {
    /// Apply the stamp shadow to any opaque shape.
    func stampShadow() -> some View {
        modifier(StampShadowModifier())
    }
}

/// ButtonStyle producing the standard CHING stamp button. Primary = ink fill, paper text.
/// Secondary = paper fill, ink text. Both have the 2pt hard offset shadow and the 1.5pt
/// ink border.
struct StampButtonStyle: ButtonStyle {
    var primary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodoni(16))
            .textCase(.uppercase)
            .tracking(2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .foregroundStyle(primary ? Color.paper : Color.ink)
            .background(primary ? Color.ink : Color.paper)
            .overlay(
                Rectangle().strokeBorder(Color.ink, lineWidth: 1.5)
            )
            .stampShadow()
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

extension View {
    func stampButton(primary: Bool = false) -> some View {
        self.buttonStyle(StampButtonStyle(primary: primary))
    }
}
```

- [ ] **Step 2: Build (no app code uses these yet, just verifies compile)**

Run the canonical build command. Expected: `** BUILD SUCCEEDED **`. If the build target still fails because `CHINGApp.swift` and `GameView.swift` are still broken from Task 2, switch to building the engine package as the dependency target instead, or skip this verification step until Task 4 lands. The intent is just to confirm `DesignSystem.swift` compiles.

(If the build fails specifically with errors about `GameStore()` or `GameView()` from `CHINGApp.swift`, those are pre-existing breakage from Task 2 and don't indicate a `DesignSystem.swift` problem. Move on.)

- [ ] **Step 3: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/DesignSystem.swift && \
  git commit -m "ios: DesignSystem with palette + Bodoni/Cochin + stampButton"
```

---

## Task 4: `CHINGApp` NavigationStack + inject stores, remove difficulty picker from `GameView`

**Files:**
- Modify: `ios/CHING/CHING/CHINGApp.swift`
- Modify: `ios/CHING/CHING/GameView.swift`

`CHINGApp` owns both stores and applies `.preferredColorScheme`. `GameView` accepts them via init, removes the Phase 3 internal `@SwiftUI.State private var store = GameStore()` line and the top-of-screen difficulty picker. The `act` helper computes effective reduce-motion as `settings.reducedMotion || env.accessibilityReduceMotion`.

After this task the app compiles and runs, but the new vocabulary, layout, gear icon, and SettingsView don't exist yet. The Game screen still looks like Phase 3 minus the difficulty picker.

- [ ] **Step 1: Rewrite `CHINGApp.swift`**

Replace `ios/CHING/CHING/CHINGApp.swift` (currently 9 lines) with:

```swift
import SwiftUI

@main
struct CHINGApp: App {
    @SwiftUI.State private var settings: SettingsStore
    @SwiftUI.State private var store: GameStore

    init() {
        let s = SettingsStore()
        _settings = .init(initialValue: s)
        _store = .init(initialValue: GameStore(settings: s))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                GameView(store: store, settings: settings)
            }
            .preferredColorScheme(settings.colorMode.preferredScheme)
        }
    }
}
```

- [ ] **Step 2: Rewire `GameView` to accept injected stores and drop the Phase 3 difficulty picker**

In `ios/CHING/CHING/GameView.swift`:

Replace:

```swift
struct GameView: View {
    @SwiftUI.State private var store = GameStore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func act(_ action: Action) {
        store.apply(action)
        let reduce = reduceMotion
        Task { await store.runAIIfNeeded(reduceMotion: reduce) }
    }
```

with:

```swift
struct GameView: View {
    let store: GameStore
    let settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var iosReduceMotion

    private func act(_ action: Action) {
        store.apply(action)
        let reduce = settings.reducedMotion || iosReduceMotion
        Task { await store.runAIIfNeeded(reduceMotion: reduce) }
    }
```

Then in the `body` of `GameView`, remove the Phase 3 difficulty picker block:

```swift
            DifficultyPicker(difficulty: Binding(
                get: { store.difficulty },
                set: { store.difficulty = $0 }
            ))

```

(Delete those four lines including the blank line after them. The `Text("CHING")` line should now be the first child of the outer `VStack`.)

Also delete the entire `struct DifficultyPicker: View { ... }` definition further down the file. It's no longer used. The Settings screen will get its own segmented picker in Task 6.

- [ ] **Step 3: Build + run**

Run the canonical build command. Expected: `** BUILD SUCCEEDED **`.

Then install + launch:

```bash
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name CHING.app -path "*Debug-iphonesimulator*" -print -quit)
xcrun simctl install booted "$APP_PATH"
xcrun simctl terminate booted com.fastronaut.CHING 2>/dev/null
xcrun simctl launch booted com.fastronaut.CHING
```

Expected: app launches. Game screen looks like Phase 3 minus the difficulty picker at top. AI pacing still works.

- [ ] **Step 4: Run tests**

Run the canonical test command. Expected: all 16 tests pass (10 `GameStoreTests` + 6 `SettingsStoreTests`).

- [ ] **Step 5: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/CHINGApp.swift ios/CHING/CHING/GameView.swift && \
  git commit -m "ios: CHINGApp owns stores via NavigationStack; remove Phase 3 difficulty picker"
```

---

## Task 5: `SettingsView` shell + gear-icon `NavigationLink` from `GameView`

**Files:**
- Create: `ios/CHING/CHING/SettingsView.swift`
- Modify: `ios/CHING/CHING/GameView.swift`

Skeletal `SettingsView` showing just the nav bar + a placeholder body. Gear icon at the top-right of the Game screen pushes it. Confirms the navigation pattern works end-to-end before filling in the Settings content.

- [ ] **Step 1: Create `SettingsView.swift` shell**

Write `ios/CHING/CHING/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    let settings: SettingsStore

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.bodoni(24))
                    .foregroundStyle(Color.ink)

                Text("Section bodies land in Task 8.")
                    .font(.cochinItalic(14))
                    .foregroundStyle(Color.dimInk)

                Spacer()
            }
            .padding(20)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
```

- [ ] **Step 2: Wire a `NavigationLink` gear icon in `GameView`**

In `ios/CHING/CHING/GameView.swift`, find the opening of `body`:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CHING")
                .font(.largeTitle)
                .bold()
```

and replace it with:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                NavigationLink {
                    SettingsView(settings: settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.ink)
                }
            }

            Text("CHING")
                .font(.largeTitle)
                .bold()
```

(The `Text("CHING")` line is kept as-is for now; Task 7 replaces it with the Bodoni `ching!` logo.)

Also hide the navigation bar on the Game screen so it doesn't compete with the in-screen `CHING` title. At the end of the outer `VStack` chain, find:

```swift
        .padding()
        .alert("Game over", isPresented: .constant(store.isOver)) {
```

and insert before the `.padding()`:

```swift
        .navigationBarHidden(true)
        .padding()
        .alert("Game over", isPresented: .constant(store.isOver)) {
```

(`.navigationBarHidden(true)` is deprecated but works on iOS 17+. The replacement `.toolbar(.hidden, for: .navigationBar)` may be used instead if preferred; both work.)

- [ ] **Step 3: Build + launch + verify**

Run the canonical build + install + launch chain.

Expected:
- App launches, Game screen looks unchanged from Task 4 except for a small gear icon top-right.
- Tap the gear icon: Settings screen slides in from the right with a nav bar showing `‹ Back`, title `Settings`, and the placeholder body.
- Tap `‹ Back` (or swipe right from the left edge): return to Game.

- [ ] **Step 4: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/SettingsView.swift ios/CHING/CHING/GameView.swift && \
  git commit -m "ios: SettingsView shell pushed via gear icon NavigationLink"
```

---

## Task 6: `StampSegmented` control

**Files:**
- Modify: `ios/CHING/CHING/SettingsView.swift`

Hand-rolled segmented control matching the 1-bit aesthetic. Used in Settings for Difficulty and Color mode.

- [ ] **Step 1: Add `StampSegmented` to `SettingsView.swift`**

Append below the closing `}` of `SettingsView` in `ios/CHING/CHING/SettingsView.swift`:

```swift
struct StampSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let labelFor: (T) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { idx in
                let value = options[idx]
                Button {
                    selection = value
                } label: {
                    Text(labelFor(value))
                        .font(.cochin(13))
                        .foregroundStyle(value == selection ? Color.paper : Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(value == selection ? Color.ink : Color.paper)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(labelFor(value)))
                .accessibilityAddTraits(value == selection ? .isSelected : [])

                if idx < options.count - 1 {
                    Rectangle()
                        .fill(Color.ink)
                        .frame(width: 1.5)
                }
            }
        }
        .overlay(
            Rectangle().strokeBorder(Color.ink, lineWidth: 1.5)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}
```

- [ ] **Step 2: Wire a sanity-check usage into the `SettingsView` body**

To verify the control renders and is tappable, temporarily replace the placeholder `Text("Section bodies land in Task 8.")` in `SettingsView.body` with:

```swift
                Text("Difficulty (preview)")
                    .font(.cochinItalic(10))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(Color.dimInk)

                StampSegmented(
                    selection: Binding(
                        get: { settings.difficulty },
                        set: { settings.difficulty = $0 }
                    ),
                    options: Difficulty.allCases,
                    labelFor: { $0.rawValue.capitalized }
                )
```

This preview will be fully integrated into the sections layout in Task 8.

- [ ] **Step 3: Build + launch + verify**

Run the canonical build + install + launch chain. Open Settings via the gear icon.

Expected:
- A segmented row with three cells `Easy`, `Normal`, `Hard` appears under the `Difficulty (preview)` label.
- `Normal` is selected by default (filled with ink, paper text).
- Tap `Hard`. The selection moves.
- Quit and relaunch. Hard is still selected (SettingsStore persistence works through this UI).

- [ ] **Step 4: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/SettingsView.swift && \
  git commit -m "ios: StampSegmented hand-rolled segmented control"
```

---

## Task 7: `StampToggle` control

**Files:**
- Modify: `ios/CHING/CHING/SettingsView.swift`

Hand-rolled toggle matching the 1-bit aesthetic. Used in Settings for Reduced motion and the disabled Sound / Haptics placeholders.

- [ ] **Step 1: Add `StampToggle` to `SettingsView.swift`**

Append at the bottom of `ios/CHING/CHING/SettingsView.swift`:

```swift
struct StampToggle: View {
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        Button {
            if !disabled { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle()
                    .fill(Color.paper)
                    .frame(width: 34, height: 20)
                    .overlay(
                        Rectangle()
                            .strokeBorder(disabled ? Color.dimInk : Color.ink, lineWidth: 1.5)
                    )
                Rectangle()
                    .fill(disabled ? Color.dimInk : Color.ink)
                    .frame(width: 14, height: 14)
                    .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Toggle")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(disabled ? [.isStaticText] : [])
    }
}
```

- [ ] **Step 2: Temporarily wire a `StampToggle` for Reduced motion preview**

In the `SettingsView.body`, just after the `StampSegmented` block from Task 6, append:

```swift
                Text("Reduced motion (preview)")
                    .font(.cochinItalic(10))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(Color.dimInk)
                    .padding(.top, 12)

                HStack {
                    Text("Reduced motion")
                        .font(.cochin(14))
                        .foregroundStyle(Color.ink)
                    Spacer()
                    StampToggle(isOn: Binding(
                        get: { settings.reducedMotion },
                        set: { settings.reducedMotion = $0 }
                    ))
                }
```

- [ ] **Step 3: Build + launch + verify**

Run the canonical build + install + launch chain. Open Settings.

Expected:
- Below the segmented Difficulty preview, a `Reduced motion` row appears with a small toggle on the right.
- Toggle starts off (thumb at left). Tap it. Thumb snaps to right.
- Quit and relaunch. State persists.

- [ ] **Step 4: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/SettingsView.swift && \
  git commit -m "ios: StampToggle hand-rolled toggle"
```

---

## Task 8: `SettingsView` full content (sections + About sheet)

**Files:**
- Modify: `ios/CHING/CHING/SettingsView.swift`

Replace the preview wiring from Tasks 6-7 with the final Settings layout: 4 sections (Play, Appearance, Feedback, Other), placeholder rows for unfinished features, About sheet.

- [ ] **Step 1: Add `SettingsSection` and `SettingsRow` helpers**

Append to `ios/CHING/CHING/SettingsView.swift`:

```swift
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.ink).frame(height: 1)
                }
            content()
        }
        .padding(.top, 18)
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    var disabled: Bool = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.cochin(14))
                .foregroundStyle(disabled ? Color.dimInk : Color.ink)
            if disabled {
                Text("soon")
                    .font(.cochinItalic(9))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Color.dimInk)
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 6)
    }
}
```

- [ ] **Step 2: Add the `AboutSheet`**

Append:

```swift
private struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("ching!")
                    .font(.bodoniItalic(48))
                    .foregroundStyle(Color.ink)
                Text("A push-your-luck dice game.\nv0.4 — ching by Fastronaut.")
                    .font(.cochin(14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.dimInk)
                Spacer()
                Button("Close") { dismiss() }
                    .stampButton()
                    .frame(maxWidth: 200)
            }
            .padding(40)
        }
    }
}
```

- [ ] **Step 3: Replace the `SettingsView.body` content with the full layout**

Replace the entire body of `SettingsView` with:

```swift
struct SettingsView: View {
    let settings: SettingsStore
    @SwiftUI.State private var showAbout = false
    // Static placeholder toggles, never mutate — used so disabled StampToggles render in their default off position.
    @SwiftUI.State private var placeholderOff = false

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.bodoni(28))
                        .foregroundStyle(Color.ink)
                        .padding(.top, 8)

                    SettingsSection(title: "Play") {
                        SettingsRow(title: "Difficulty") {
                            StampSegmented(
                                selection: Binding(
                                    get: { settings.difficulty },
                                    set: { settings.difficulty = $0 }
                                ),
                                options: Difficulty.allCases,
                                labelFor: { $0.rawValue.capitalized }
                            )
                            .frame(maxWidth: 220)
                        }
                    }

                    SettingsSection(title: "Appearance") {
                        SettingsRow(title: "Color mode") {
                            StampSegmented(
                                selection: Binding(
                                    get: { settings.colorMode },
                                    set: { settings.colorMode = $0 }
                                ),
                                options: ColorMode.allCases,
                                labelFor: { $0.rawValue.capitalized }
                            )
                            .frame(maxWidth: 220)
                        }
                        SettingsRow(title: "Reduced motion") {
                            StampToggle(isOn: Binding(
                                get: { settings.reducedMotion },
                                set: { settings.reducedMotion = $0 }
                            ))
                        }
                    }

                    SettingsSection(title: "Feedback") {
                        SettingsRow(title: "Sound", disabled: true) {
                            StampToggle(isOn: $placeholderOff, disabled: true)
                        }
                        SettingsRow(title: "Haptics", disabled: true) {
                            StampToggle(isOn: $placeholderOff, disabled: true)
                        }
                    }

                    SettingsSection(title: "Other") {
                        SettingsRow(title: "Replay tutorial", disabled: true) {
                            Text("tap")
                                .font(.cochinItalic(13))
                                .underline()
                                .foregroundStyle(Color.dimInk)
                        }
                        SettingsRow(title: "Tip jar", disabled: true) {
                            Text("tap")
                                .font(.cochinItalic(13))
                                .underline()
                                .foregroundStyle(Color.dimInk)
                        }
                        Button {
                            showAbout = true
                        } label: {
                            SettingsRow(title: "About") {
                                Text("tap")
                                    .font(.cochinItalic(13))
                                    .underline()
                                    .foregroundStyle(Color.ink)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 40)

                    Text("v0.4 · ching by fastronaut")
                        .font(.cochinItalic(10))
                        .foregroundStyle(Color.dimInk)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showAbout) {
            AboutSheet()
        }
    }
}
```

- [ ] **Step 4: Build + launch + verify**

Run the canonical build + install + launch chain. Open Settings.

Expected:
- Title `Settings` in Bodoni at the top.
- Section `Play` with `Difficulty` row + segmented `Easy | Normal | Hard` aligned right.
- Section `Appearance` with `Color mode` row + `System | Light | Dark` and `Reduced motion` row + toggle.
- Section `Feedback` with `Sound` and `Haptics` rows, both with "soon" tag and disabled toggles.
- Section `Other` with `Replay tutorial`, `Tip jar`, `About` rows. The first two are disabled, About is tappable.
- Footer at the bottom: `v0.4 · ching by fastronaut`.
- Tap `About`. The sheet appears with `ching!` italic Bodoni + description + Close button. Tap Close.
- Tap `Color mode > Dark`. The whole UI inverts to paper-on-ink immediately. Tap `Light`, back to light. Tap `System`, follows iOS appearance.
- Quit and relaunch. Color mode + Difficulty + Reduced motion all persist.

- [ ] **Step 5: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/SettingsView.swift && \
  git commit -m "ios: SettingsView full sections + About sheet"
```

---

## Task 9: `GameView` vocabulary rename + `bankActionLabel` update + `displayName` helper

**Files:**
- Modify: `ios/CHING/CHING/GameView.swift`
- Modify: `ios/CHING/CHING/GameStore.swift`

Pure string changes. No structural layout work yet (that's Task 10). Engine code untouched. Vault names render mixed-case via a helper.

- [ ] **Step 1: Update `bankActionLabel` to "Steal Jones's safe" wording**

In `ios/CHING/CHING/GameStore.swift`, replace the existing `bankActionLabel`:

```swift
    var bankActionLabel: String {
        guard canBank else { return "Bank" }
        for i in state.players.indices where i != state.current {
            if let top = state.players[i].tiles.last, top == setAsideSum {
                return "STEAL FROM \(state.players[i].id)"
            }
        }
        return "Bank"
    }
```

with:

```swift
    var bankActionLabel: String {
        guard canBank else { return "Bank" }
        for i in state.players.indices where i != state.current {
            if let top = state.players[i].tiles.last, top == setAsideSum {
                let name = state.players[i].id.capitalized
                return "Steal \(name)'s safe"
            }
        }
        return "Bank"
    }
```

(`"JONES".capitalized` evaluates to `"Jones"`; `"BOT 03".capitalized` evaluates to `"Bot 03"`. Swift's `capitalized` lowercases everything after the first letter of each whitespace-delimited word, which is what we want here.)

- [ ] **Step 2: Update the corresponding test assertion**

In `ios/CHING/CHINGTests/GameStoreTests.swift`, find:

```swift
        XCTAssertEqual(store.bankActionLabel, "STEAL FROM JONES")
```

and replace with:

```swift
        XCTAssertEqual(store.bankActionLabel, "Steal Jones's safe")
```

- [ ] **Step 3: Add a `displayName` helper inside `GameView`**

In `ios/CHING/CHING/GameView.swift`, inside `struct GameView: View { ... }` (after `private func act` and before `private var currentSeatName`), add:

```swift
    private func displayName(_ id: String) -> String {
        id.capitalized
    }
```

- [ ] **Step 4: Rewrite `currentSeatName` and visible vocabulary strings inside `body`**

In `GameView.body`, find:

```swift
            Text("CHING")
                .font(.largeTitle)
                .bold()

            Text("Phase: \(store.state.phase.rawValue)")
            Text("Turn: \(store.state.players[store.state.current].id)")
            Text("Scores: " + zip(store.state.players, store.scores)
                .map { "\($0.id) \($1)" }
                .joined(separator: "  "))
```

and replace with:

```swift
            Text("ching!")
                .font(.bodoniItalic(44))
                .foregroundStyle(Color.ink)

            Text("Turn · \(displayName(currentSeatName)) · \(store.state.phase.rawValue) phase")
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)

            Text(scoresLine)
                .font(.cochin(13))
                .foregroundStyle(Color.ink)
```

Add a `scoresLine` computed property to `GameView`, next to `currentSeatName`:

```swift
    private var scoresLine: String {
        zip(store.state.players, store.scores)
            .map { "\(displayName($0.id)) \($1)" }
            .joined(separator: " · ")
    }
```

In the thinking footer block, find:

```swift
            if !store.isHumanTurn && !store.isOver {
                Text("\(currentSeatName) is thinking…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
```

and replace with:

```swift
            if !store.isHumanTurn && !store.isOver {
                Text("\(displayName(currentSeatName)) is thinking…")
                    .font(.cochinItalic(13))
                    .foregroundStyle(Color.dimInk)
            }
```

In `CenterTileRow`, find:

```swift
            Text("CENTER").font(.caption).bold()
```

and replace with:

```swift
            Text("Safes")
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)
```

In `VaultRow`, find:

```swift
            Text("VAULTS").font(.caption).bold()
```

and replace with:

```swift
            Text("Vaults")
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)
```

In `VaultRow`'s `ForEach`, find:

```swift
                    Text(players[i].id)
                        .bold(i == current)
                        .frame(width: 70, alignment: .leading)
```

and replace with:

```swift
                    Text(players[i].id.capitalized)
                        .font(.cochinItalic(11))
                        .textCase(.uppercase)
                        .tracking(1)
                        .frame(width: 70, alignment: .leading)
                        .foregroundStyle(Color.ink)
                        .overlay(alignment: .leading) {
                            if i == current {
                                Text("▸ ").font(.cochin(11))
                                    .offset(x: -10)
                            }
                        }
```

In `DiceRow`, find:

```swift
            Text("DICE").font(.caption).bold()
```

and replace with:

```swift
            Text("Dice")
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)
```

In `DiceRow`'s "Rolled" / "Set aside" sub-labels, find:

```swift
                    Text("Rolled").font(.caption2)
```

and replace with:

```swift
                    Text("Rolled")
                        .font(.cochinItalic(9))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(Color.dimInk)
```

Same for:

```swift
                    Text("Set aside (sum \(setAsideSum))").font(.caption2)
```

→

```swift
                    Text("Set aside · sum \(setAsideSum)")
                        .font(.cochinItalic(9))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(Color.dimInk)
```

And `Text("In hand: \(diceInHand)").font(.caption2)` → 

```swift
            Text("In hand · \(diceInHand)")
                .font(.cochinItalic(9))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Color.dimInk)
```

In `PickBar`, find:

```swift
            Text("PICK").font(.caption).bold()
```

and replace with:

```swift
            Text("Pick")
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)
```

In `gameOverMessage`, find:

```swift
        let headline: String
        if leaders.count == 1 {
            headline = "\(leaders[0].id) wins."
        } else {
            headline = "Tie at the top."
        }

        let body = ranked
            .map { "\($0.id) \($0.score)" }
            .joined(separator: " · ")
```

and replace with:

```swift
        let headline: String
        if leaders.count == 1 {
            headline = "\(leaders[0].id.capitalized) wins."
        } else {
            headline = "Tie at the top."
        }

        let body = ranked
            .map { "\($0.id.capitalized) \($0.score)" }
            .joined(separator: " · ")
```

- [ ] **Step 5: Run tests + build + launch**

Run the canonical test command. Expected: all 16 tests pass (the steal-label test now asserts `"Steal Jones's safe"`).

Run the canonical build + install + launch chain. The Game screen should now show:
- `ching!` italic Bodoni title.
- Status line `Turn · You · roll phase` in italic small caps.
- Scores `You 0 · Jones 0 · Bot 03 0`.
- Section labels `Safes`, `Vaults`, `Dice`, `Pick` in italic small caps.
- Vault names render `You`, `Jones`, `Bot 03` mixed-case.
- Active seat marked with `▸` left of the name.
- Tile and dice borders/colors haven't been restyled yet (Task 11) — they still look like the Phase 3 default outlined boxes.

- [ ] **Step 6: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/GameStore.swift ios/CHING/CHING/GameView.swift ios/CHING/CHINGTests/GameStoreTests.swift && \
  git commit -m "ios: vocabulary rename — ching!, Safes, mixed-case names"
```

---

## Task 10: `GameView` layout refactor — compact header, centered dice tray, column-aligned vaults

**Files:**
- Modify: `ios/CHING/CHING/GameView.swift`

Layout changes only. The compact header (no separate Phase line, status condensed), dice tray horizontally centered, vault rows with the name column at fixed 70pt width, gear icon stays top-right.

- [ ] **Step 1: Center the `DiceRow` rolled and set-aside rows**

In `DiceRow.body`, the current layout has rolled on the left and set-aside on the right (a side-by-side `HStack`). Replace the existing `body`:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dice")
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)
            HStack {
                VStack(alignment: .leading) {
                    Text("Rolled")
                        .font(.cochinItalic(9))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(Color.dimInk)
                    HStack(spacing: 4) {
                        ForEach(Array(rolled.enumerated()), id: \.offset) { _, f in
                            Text(faceLabel(f))
                                .frame(width: 22, height: 22)
                                .overlay(Rectangle().stroke())
                        }
                        if rolled.isEmpty {
                            Text("(none)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Set aside · sum \(setAsideSum)")
                        .font(.cochinItalic(9))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(Color.dimInk)
                    HStack(spacing: 4) {
                        ForEach(Array(setAside.enumerated()), id: \.offset) { _, f in
                            Text(faceLabel(f))
                                .frame(width: 22, height: 22)
                                .overlay(Rectangle().stroke().opacity(0.5))
                        }
                        if setAside.isEmpty {
                            Text("(none)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("In hand · \(diceInHand)")
                .font(.cochinItalic(9))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Color.dimInk)
        }
    }
```

with:

```swift
    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Text("Dice")
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(Array(rolled.enumerated()), id: \.offset) { _, f in
                    Text(faceLabel(f))
                        .font(.cochin(15))
                        .foregroundStyle(Color.ink)
                        .frame(width: 28, height: 28)
                        .overlay(Rectangle().stroke(Color.ink, lineWidth: 1.5))
                }
                if rolled.isEmpty {
                    Text("(none)")
                        .font(.cochinItalic(11))
                        .foregroundStyle(Color.dimInk)
                }
            }

            Text("Set aside · sum \(setAsideSum)")
                .font(.cochinItalic(9))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Color.dimInk)
                .padding(.top, 4)

            HStack(spacing: 4) {
                ForEach(Array(setAside.enumerated()), id: \.offset) { _, f in
                    Text(faceLabel(f))
                        .font(.cochin(15))
                        .foregroundStyle(Color.ink)
                        .frame(width: 28, height: 28)
                        .overlay(Rectangle().stroke(Color.ink, lineWidth: 1.5).opacity(0.5))
                }
                if setAside.isEmpty {
                    Text("(none)")
                        .font(.cochinItalic(11))
                        .foregroundStyle(Color.dimInk)
                }
            }

            Text("In hand · \(diceInHand)")
                .font(.cochinItalic(9))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Color.dimInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
```

- [ ] **Step 2: Update `CenterTileRow` tile rendering**

In `CenterTileRow.body`, replace the inner `ForEach`:

```swift
                    ForEach(tiles, id: \.self) { tile in
                        VStack {
                            Text("\(tile)").font(.headline)
                            Text("\(tileCoins(tile))c").font(.caption2)
                        }
                        .padding(6)
                        .overlay(Rectangle().stroke())
                    }
```

with:

```swift
                    ForEach(tiles, id: \.self) { tile in
                        VStack(spacing: 0) {
                            Text("\(tile)")
                                .font(.cochin(14))
                                .foregroundStyle(Color.ink)
                            Text("\(tileCoins(tile))c")
                                .font(.cochinItalic(8))
                                .foregroundStyle(Color.dimInk)
                        }
                        .padding(6)
                        .overlay(Rectangle().stroke(Color.ink, lineWidth: 1.5))
                    }
```

- [ ] **Step 3: Update `VaultRow` tile rendering for consistency**

In `VaultRow.body`, replace the inner safe-rendering `ForEach`:

```swift
                        HStack(spacing: 4) {
                            ForEach(players[i].tiles, id: \.self) { tile in
                                VStack(spacing: 0) {
                                    Text("\(tile)")
                                    Text("\(tileCoins(tile))c").font(.caption2)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .overlay(Rectangle().stroke())
                            }
                        }
```

with:

```swift
                        HStack(spacing: 4) {
                            ForEach(players[i].tiles, id: \.self) { tile in
                                VStack(spacing: 0) {
                                    Text("\(tile)")
                                        .font(.cochin(13))
                                        .foregroundStyle(Color.ink)
                                    Text("\(tileCoins(tile))c")
                                        .font(.cochinItalic(8))
                                        .foregroundStyle(Color.dimInk)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .overlay(Rectangle().stroke(Color.ink, lineWidth: 1.5))
                            }
                        }
```

Replace the `Text("(empty)")` with:

```swift
                        Text("empty")
                            .font(.cochinItalic(11))
                            .foregroundStyle(Color.dimInk)
```

- [ ] **Step 4: Apply the paper background to the whole Game screen**

In `GameView.body`, wrap the outer `VStack` in a `ZStack` with a paper background. Find the opening:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
```

and replace with:

```swift
    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
```

Find the closing of the outer VStack:

```swift
            Spacer()
        }
        .navigationBarHidden(true)
        .padding()
        .alert("Game over", isPresented: .constant(store.isOver)) {
```

and replace with:

```swift
                Spacer()
            }
            .padding(20)
        }
        .navigationBarHidden(true)
        .alert("Game over", isPresented: .constant(store.isOver)) {
```

(Move `.padding(20)` inside, leave `.navigationBarHidden(true)` and `.alert` modifiers on the `ZStack`.)

- [ ] **Step 5: Build + launch + verify**

Run the canonical build + install + launch chain.

Expected:
- Game screen now has the cream paper background (or near-black in dark mode).
- Title `ching!` Bodoni italic, status line in italic small caps, scores compact.
- Safes row uses Cochin numerals + dim italic `Nc` annotations.
- Vault rows: 70pt name column with `You`, `Jones`, `Bot 03`, current seat prefixed with `▸`. Tile boxes use Cochin numerals.
- Dice tray is horizontally centered (rolled row above, set-aside row below, both centered).
- "In hand · 8" left-aligned below the tray.

Verify in both light and dark mode (toggle via Settings).

- [ ] **Step 6: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/GameView.swift && \
  git commit -m "ios: Game screen layout — paper background, centered dice, column vaults"
```

---

## Task 11: `GameView` stamp action bar + small stamp picks

**Files:**
- Modify: `ios/CHING/CHING/GameView.swift`

Restyle `ActionBar` to use `.stampButton(primary: true/false)` and `PickBar` to use small stamp toggles. The action bar gets pinned to the bottom of the screen.

- [ ] **Step 1: Restyle `ActionBar` with `.stampButton`**

Replace `ActionBar` entirely:

```swift
struct ActionBar: View {
    let store: GameStore
    let act: (Action) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Roll") {
                act(.roll)
            }
            .disabled(!store.canRoll)
            .buttonStyle(.borderedProminent)

            Button(store.bankActionLabel) {
                act(.stop)
            }
            .disabled(!store.canBank)
            .buttonStyle(.borderedProminent)
        }
    }
}
```

with:

```swift
struct ActionBar: View {
    let store: GameStore
    let act: (Action) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Roll") {
                act(.roll)
            }
            .stampButton(primary: true)
            .disabled(!store.canRoll)
            .opacity(store.canRoll ? 1.0 : 0.4)

            Button(store.bankActionLabel) {
                act(.stop)
            }
            .stampButton(primary: false)
            .disabled(!store.canBank)
            .opacity(store.canBank ? 1.0 : 0.4)
        }
    }
}
```

(The `.opacity` is a deliberate hand-rolled disabled state because `.stampButton` doesn't fade the button on `.disabled` by default.)

- [ ] **Step 2: Restyle `PickBar` with small stamps**

Replace `PickBar` entirely:

```swift
struct PickBar: View {
    let store: GameStore
    let act: (Action) -> Void

    private let faces: [Face] = [.one, .two, .three, .four, .five, .coin]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pick")
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)
            HStack(spacing: 6) {
                ForEach(faces, id: \.self) { face in
                    Button(faceLabel(face)) {
                        act(.pick(face: face))
                    }
                    .disabled(!store.canPick(face))
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
```

with:

```swift
struct PickBar: View {
    let store: GameStore
    let act: (Action) -> Void

    private let faces: [Face] = [.one, .two, .three, .four, .five, .coin]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pick")
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)
            HStack(spacing: 8) {
                ForEach(faces, id: \.self) { face in
                    Button(faceLabel(face)) {
                        act(.pick(face: face))
                    }
                    .frame(width: 36, height: 36)
                    .font(.cochin(15))
                    .foregroundStyle(store.canPick(face) ? Color.ink : Color.dimInk)
                    .background(Color.paper)
                    .overlay(Rectangle().strokeBorder(
                        store.canPick(face) ? Color.ink : Color.dimInk,
                        lineWidth: 1.5
                    ))
                    .stampShadow()
                    .opacity(store.canPick(face) ? 1.0 : 0.4)
                    .disabled(!store.canPick(face))
                }
            }
        }
    }
}
```

- [ ] **Step 3: Pin `ActionBar` to the bottom of the screen and clean up the spacing**

Currently `GameView.body` has `ActionBar` followed by the thinking footer and a `Spacer()`. The desired layout per spec: action bar pinned at the bottom edge, thinking footer above it. Replace the closing of the outer `VStack`:

```swift
                PickBar(store: store, act: act)
                ActionBar(store: store, act: act)

                if !store.isHumanTurn && !store.isOver {
                    Text("\(displayName(currentSeatName)) is thinking…")
                        .font(.cochinItalic(13))
                        .foregroundStyle(Color.dimInk)
                }

                Spacer()
            }
            .padding(20)
        }
```

with:

```swift
                PickBar(store: store, act: act)

                Spacer()

                if !store.isHumanTurn && !store.isOver {
                    Text("\(displayName(currentSeatName)) is thinking…")
                        .font(.cochinItalic(13))
                        .foregroundStyle(Color.dimInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                ActionBar(store: store, act: act)
            }
            .padding(20)
        }
```

- [ ] **Step 4: Build + launch + verify**

Run the canonical build + install + launch chain.

Expected:
- `Roll` button reads as a primary stamp: ink-filled rectangle, paper-colored uppercase Bodoni text, 2pt offset shadow.
- `Bank` reads as a secondary stamp: paper-filled, ink-colored uppercase text, same shadow.
- Pick row shows six small square stamps with Cochin numerals.
- Action bar is pinned to the bottom of the screen.
- Thinking footer appears just above the action bar when an AI is playing.
- Test in both light and dark mode.

Take a few turns. The Bank label should switch to "Steal Jones's safe" when the set-aside sum matches Jones's top safe.

- [ ] **Step 5: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/GameView.swift && \
  git commit -m "ios: stamp action bar (primary Roll, secondary Bank) + small stamp picks"
```

---

## Task 12: Manual playthrough + light/dark screenshots + PR

**Files:**
- Create: `docs/superpowers/2026-06-06-phase-4-screenshot-light.png`
- Create: `docs/superpowers/2026-06-06-phase-4-screenshot-dark.png`

End-to-end verification. Two screenshots: Game screen in light + Settings screen in dark (or vice versa), captured via simctl.

- [ ] **Step 1: Full test run + engine sanity**

```bash
cd /Users/bramvanoost/Code/game-ching && xcodebuild test \
  -project ios/CHING/CHING.xcodeproj \
  -scheme CHING \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:CHINGTests 2>&1 | grep -E "Executed|TEST" | tail -3

cd /Users/bramvanoost/Code/game-ching/ios/CHINGEngine && swift test 2>&1 | grep "Executed" | tail -2
```

Expected: `CHINGTests` 16/16 pass (10 `GameStoreTests` + 6 `SettingsStoreTests`); engine 32/32 pass.

- [ ] **Step 2: Light-mode Game screenshot**

Launch the app (canonical chain). Open Settings, set Color mode = Light. Back out to Game. From a fresh state:

```bash
xcrun simctl io booted screenshot /Users/bramvanoost/Code/game-ching/docs/superpowers/2026-06-06-phase-4-screenshot-light.png
```

Inspect the file. Expected content: `ching!` Bodoni title, `Turn · You · roll phase` status line, scores, safes row, three-row vault with `You ▸`, dice tray, pick row, `Roll` primary stamp + `Bank` secondary stamp.

- [ ] **Step 3: Dark-mode Settings screenshot**

In Settings, set Color mode = Dark. Stay in Settings.

```bash
xcrun simctl io booted screenshot /Users/bramvanoost/Code/game-ching/docs/superpowers/2026-06-06-phase-4-screenshot-dark.png
```

Expected content: `Settings` title at top, four sections with section labels, controls in dark inversion (near-black background, cream text).

- [ ] **Step 4: Full playthrough sanity**

Verify by tap-through:

- Difficulty change from Settings actually changes AI behaviour next decision.
- Reduced motion toggle, take a turn: AI plays instantly. Untoggle, pacing returns.
- Toggle iOS Reduce Motion in Simulator Settings while in-app toggle is off: AI plays instantly. Untoggle iOS setting, pacing returns. Tests OR logic.
- Bank a sum equal to Jones's top safe: Bank label reads `Steal Jones's safe`, tile transfers correctly.
- Game over alert: ranked names mixed-case, `<Name> wins.` or `Tie at the top.`
- Cold quit + relaunch: all three settings persist.

- [ ] **Step 5: Commit screenshots and open PR**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add docs/superpowers/2026-06-06-phase-4-screenshot-light.png \
          docs/superpowers/2026-06-06-phase-4-screenshot-dark.png && \
  git commit -m "ios: phase 4 visual system, light + dark screenshots"

git push -u origin phase-4-visual-system 2>&1 | tail -3

gh pr create --title "Phase 4: visual system + Settings screen" --body "$(cat <<'EOF'
## Summary

- New `SettingsStore` (@Observable) owning persisted `difficulty`, `colorMode`, `reducedMotion`. UserDefaults keys `ching.difficulty` (existing), `ching.colorMode` (new), `ching.reducedMotion` (new).
- Difficulty migrates off `GameStore` onto `SettingsStore`; `GameStore.init(seed:settings:)` takes a settings reference.
- `CHINGApp` wraps a `NavigationStack`, owns both stores, applies `.preferredColorScheme(settings.colorMode.preferredScheme)`.
- New `DesignSystem.swift`: adaptive `Color.paper` / `Color.ink` / `Color.dimInk` backed by `UIColor(dynamicProvider:)`; Bodoni 72 + Cochin font helpers; `StampButtonStyle` (primary + secondary).
- New `SettingsView` with hand-rolled `StampSegmented` and `StampToggle`. Four sections: Play (Difficulty live), Appearance (Color mode + Reduced motion live), Feedback (Sound + Haptics disabled "soon"), Other (Replay tutorial + Tip jar disabled, About live). About sheet shows the title + version + tagline + Close stamp.
- `GameView` refactored: gear icon top-right pushes Settings, Phase 3 difficulty picker removed (lives in Settings), compact header (`ching!` Bodoni italic + status line + scores), centered dice tray, column-aligned three-row vaults with `▸` active indicator, paper background, stamp action bar pinned bottom.
- Vocabulary rename in user-facing strings only: `CHING` → `ching!`, `CENTER` → `Safes`, `VAULTS` → `Vaults`, vault names mixed-case (`You`, `Jones`, `Bot 03`), `STEAL FROM JONES` → `Steal Jones's safe`. Engine unchanged.
- Light + dark mode designed together. Dark inverts paper-on-ink via the dynamic provider.

## Verification done

- `xcodebuild test -only-testing:CHINGTests`: 16/16 (10 `GameStoreTests` + 6 `SettingsStoreTests`)
- Engine `swift test`: 32/32, unchanged
- App builds and runs in both light and dark mode
- Screenshots: `docs/superpowers/2026-06-06-phase-4-screenshot-light.png` (Game, light), `docs/superpowers/2026-06-06-phase-4-screenshot-dark.png` (Settings, dark)

## Test plan (Bram, manual before merge)

- [ ] Game screen renders `ching!` Bodoni italic title, italic small-caps labels, Cochin numerals
- [ ] Gear icon → Settings pushes in with the system back gesture working
- [ ] Difficulty change → next AI decision uses new modifier
- [ ] Color mode Light/Dark/System all work, dark = paper-on-ink inversion
- [ ] Reduced motion in-app toggle ORs correctly with iOS Reduce Motion
- [ ] Bank-when-stealing button reads `Steal Jones's safe`
- [ ] Game-over alert uses mixed-case names
- [ ] Cold quit + relaunch: difficulty, color mode, reduced motion all persisted

## Out of scope (still deferred)

- Isometric/dithered depth on safes and dice (flat stamped only in Phase 4)
- Watermark lattice
- Play log
- Other screens (Splash, Home, Receipt, Onboarding)
- Sound, haptics (disabled placeholders only)
- Stamp button press-down animation (static stamp shipped)
- Merit, opponent selection
- App icon, splash artwork
- Resume-game persistence

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)" 2>&1 | tail -3
```

---

## Self-review notes

- **Spec coverage:** Every "In Phase 4" bullet maps to a task. SettingsStore + persistence: Tasks 1-2. ColorMode + scheme application: Tasks 1, 4. DesignSystem palette + typography + stamp: Task 3. NavigationStack + gear nav: Tasks 4-5. Hand-rolled controls: Tasks 6-7. SettingsView content + About: Task 8. Vocabulary rename: Task 9. Layout refactor: Tasks 10-11. Manual + screenshots + PR: Task 12.
- **Spec out-of-scope respected:** No depth/isometric work, no watermark, no play log, no other screens, no sound/haptics, no press animation, no Merit, no app icon, no resume-game persistence.
- **Type consistency:** `Difficulty` (Phase 3 enum) used unchanged. `ColorMode` defined in Task 1, consumed in Tasks 4, 8. `SettingsStore` defined Task 1, injected into `GameStore` Task 2, owned by `CHINGApp` Task 4, consumed by `GameView` Task 4 + `SettingsView` Tasks 5-8. `StampSegmented<T: Hashable>` in Task 6 consistent in Task 8. `StampToggle` in Task 7 consistent in Task 8. `displayName(_:)` introduced Task 9 used throughout.
- **No placeholders:** every code step has full code, every command has expected output, no TODOs.
- **CLAUDE.md global rule:** no em-dashes in plan body or code.
- **Known fragility:** Tasks 9-11 modify large stretches of `GameView.swift` via successive Edits; an implementer should verify the file compiles after each step (`xcodebuild build`) rather than trying to chain all the edits and only checking at the end.

---

## Execution handoff

**Plan complete and saved to `docs/superpowers/plans/2026-06-06-phase-4-visual-system.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — fresh subagent per task, two-stage review after each. Best fit here because Tasks 9-11 (`GameView` rewrites) benefit from clean-context per-task implementation that catches accidental over-edits.

**2. Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batch with checkpoints. Lower overhead, but the per-task verification surface is larger than Phase 3 (light + dark visual checks per view-touching task).

**Which approach?**
