# CHING iOS Phase 4, Visual System + Settings Screen Design

**Status:** approved for planning
**Date:** 2026-06-06
**Owner:** Bram

## Context

Phase 3 shipped a tappable, gameplay-feel-correct iOS app: paced AI turns, 1v2 cast, difficulty picker, three-row vaults, three-way game over alert. Visually it still uses default SwiftUI styling. Phase 4 locks the visual language and adds a dedicated Settings surface so subsequent phases (Home, Receipt, Onboarding, sound, haptics, polish) inherit a stable design.

Phase 4 deliberately does not extend the cast (Merit stays out), does not add sound or haptics (toggles are placeholders), does not add other screens beyond Settings, and does not introduce isometric 3D depth on safes/dice (deferred to a polish phase). The visible delta is large: typography, color, vocabulary, a new screen, and a new navigation pattern.

## Goals and non-goals

### In Phase 4

- **Game screen redesigned** with the locked visual system: typography, color palette, layout, stamp buttons, vocabulary.
- **Settings screen** as a dedicated pushed view from a gear icon on the Game screen. Difficulty (live), Color mode (live), Reduced motion (live), placeholder rows for Sound, Haptics, Replay tutorial, Tip jar; live About link to a small sheet.
- **Vocabulary rename** in user-facing copy: "tile" becomes "safe", section label `Center` becomes `Safes`, the title becomes `ching!` with an exclamation mark, vault names render mixed-case (`Jones`, `Bot 03`) instead of `JONES`/`BOT 03`.
- **Light + dark mode** both designed and shipped together. Dark mode is paper-on-ink inversion, not dim-ink-on-grey.
- **Color mode persistence** via UserDefaults (System / Light / Dark), default System.
- **Reduced motion persistence** as an in-app toggle, OR'd with `@Environment(\.accessibilityReduceMotion)` to compute effective behaviour.
- **Architecture cleanup:** extract `SettingsStore` (@Observable) to own all persisted user prefs, separate from `GameStore` (the in-flight game). Migrate `difficulty` from `GameStore` to `SettingsStore`.
- **File split:** introduce `DesignSystem.swift`, `SettingsStore.swift`, `SettingsView.swift` alongside the existing `CHINGApp.swift`, `GameStore.swift`, `GameView.swift`.

### Explicitly out of Phase 4

- 3D / isometric / dithered-cube depth treatment on safes or dice. Phase 4 ships flat stamped (1px ink border + 2px hard offset shadow). Depth is a polish phase.
- Watermark lattice. Decorative; deferred.
- Play log on the Game screen. Phase 5+ when there's a real visual home for it.
- Splash, Home, Receipt, Onboarding screens. Phase 5+.
- Sound and haptics. Settings has disabled placeholder rows so the visual hierarchy is locked.
- Merit (the middle character) and opponent selection UI.
- Resume-game persistence.
- App icon and splash screen artwork.
- Animations on dice rolling, ka-ching invert, bust peel — all defer to a motion phase.
- Localisation. English only.

### Deferred to build phase (decided during implementation)

- The exact small-secondary ink (used for "soon" labels and empty placeholders). Spec says ~`#6B6B6B` light / ~`#9A9A9A` dark; final pick during a typography pass.
- About sheet body text. Spec says "version + ching by Fastronaut + a one-line description"; final copy during build.
- The exact iOS font fallback chain if Bodoni 72 isn't system-available on a target iOS version. Hardcoded fallback: Bodoni 72 → Didot → system serif.

## Visual system

### Color palette

**Light mode:**
- Paper: `#FAF8F3` (warm cream)
- Ink: `#1A1A1A` (near-black, deliberately not pure `#000000`)
- Dim ink: ~`#6B6B6B` (used sparingly: empty vault placeholder text, "soon" tags on disabled Settings rows, secondary labels)

**Dark mode:**
- Paper: `#1A1A1A`
- Ink: `#FAF8F3`
- Dim ink: ~`#9A9A9A`

True paper-on-ink inversion. No "dim grey ink on darker grey" treatment. All borders, text, and dither swap swap together.

### Typography

- **Bodoni 72** (Apple-bundled `Bodoni 72` family) — used for: the `ching!` logo (title and Settings nav back link), stamp button text (`Roll`, `Bank`, `Steal Jones's safe`), Settings nav title. Used for large, declarative, identity-carrying type only.
- **Cochin** (Apple-bundled) — used for everything else: numerals on safes and dice, scores line, body text, section labels (italic small caps treatment at ~10pt with ~1.5pt letter-spacing), player names in mixed case, About sheet body.
- iOS fallback chain documented in code: Bodoni 72 → Didot → system serif; Cochin → Hoefler Text → Times → system serif.
- Numerals use `lnum` (lining figures) and `tnum` (tabular figures) consistently via `font-feature-settings`. The Swift equivalent is `.font(.custom(...).monospacedDigit())` or explicit `Font.Configuration` modifiers.

### Borders and surfaces

- Standard border: 1.5px solid ink. No rounded corners anywhere. No gradients. No soft shadows. No blur.
- Section separators: 1px ink, used to underline section labels (e.g. `Safes`, `Vaults`, `Dice`).
- Active vault row indicator: a single `▸` glyph prefixed to the player name, no background pill. Background-pill treatment was tested and rejected (it shifted the tile alignment column).

### Stamp buttons

- 2px solid ink border, no inner padding asymmetry, no rounding.
- 2px hard offset drop shadow: solid ink rectangle offset `(2, 2)` with zero blur radius. SwiftUI: `.shadow(color: ink, radius: 0, x: 2, y: 2)`.
- Primary action (Roll, Bank): fills with ink, text inverted to paper.
- Secondary action (in Settings: About): paper fill, ink text.
- Tap state: the button visually depresses by 2px (shadow effectively absorbed into the button frame). Implemented via `.scaleEffect` or an animated `offset` modifier on press. Phase 4 ships this as a static `.buttonStyle` modifier; tuning the animation curve is deferred.
- Button text uses Bodoni 72 in uppercase with ~2pt letter-spacing.

### Dice and safes (flat stamped, depth deferred)

- Both render as 1.5px-ink-bordered rectangles with paper fill and a 2px offset hard ink shadow. No isometric faces in Phase 4.
- Locked die: paper fill replaced with a 45-degree hatched fill (~1px ink stripes spaced 3px apart) generated programmatically via `Canvas` or as a small repeating image. Identical treatment whether light or dark mode (the hatch lines are ink in light, paper in dark — i.e. they invert with the rest of the palette).
- Coin die face: solid ink fill, Cochin `C` glyph in paper color.
- Safe rendering: 1.5px ink border, paper fill, Cochin numeral (21–36). Same treatment in the Safes row (unclaimed) and in the Vaults rows (banked).
- Burned safe (Heckmeck depletion): no visual indicator in Phase 4; the safe simply vanishes from the Safes row. A "blown" microcopy line will arrive in a polish phase.

## Visual surface

### Game screen layout

Top to bottom, all sections share the screen's horizontal padding (~18pt) except where noted:

1. **Gear icon** top-right, ~20pt size, taps to push Settings.
2. **`ching!` logo**, Bodoni 72, italic, ~44pt. Top-left.
3. **Status block:** italic small-caps Cochin label `"Turn · You · roll phase"`, then a Cochin scores line `"You 0 · Jones 0 · Bot 03 0"` with bold tabular numerals.
4. **Safes section**, label `"Safes"`. Horizontal scrolling row of safe rectangles. (Section was previously labelled `Center`.)
5. **Vaults section**, label `"Vaults"`. Three rows, one per player. Each row: 70pt-wide name column on the left (italic Cochin small caps, mixed case), then the player's banked safes left-aligned to the same x-position across all three rows. Current seat prefixed with `▸`.
6. **Dice tray (horizontally centred):** label `"Dice"`, the rolled dice row centred, then label `"Set aside · sum N"`, then the set-aside row centred.
7. **Pick row:** the six pick buttons `1 2 3 4 5 C` (existing from Phase 2/3). Each button is a small stamp: ~28pt square, 1.5px ink border, paper fill, 2px hard offset shadow, Cochin numeral inside. Disabled buttons drop the shadow and dim the border to `dimInk`. Same stamp vocabulary as `Roll`/`Bank` but smaller.
8. **Action bar** pinned to bottom: `Roll` and `Bank` stamp buttons, 50/50 split, ~18pt horizontal padding. `Bank` switches to `Steal Jones's safe` when a steal is available (existing Phase 2 logic).
9. **Thinking footer** (existing from Phase 3): `"Jones is thinking…"` shown only when an AI is current. Cochin italic, dim ink.

### Settings screen layout

Pushed from the Game screen's gear icon. Standard `NavigationStack` push (system back gesture works).

- **Nav bar:** 1px bottom border. Left: `‹ ching!` (Bodoni back link, italic). Center: `Settings` (Bodoni 72 title). Right: empty.
- **Sections** (each section title is italic Cochin small caps underlined with a 1px ink rule):
  - **Play** — Difficulty (Easy / Normal / Hard segmented).
  - **Appearance** — Color mode (System / Light / Dark segmented) + Reduced motion (toggle).
  - **Feedback** — Sound (disabled toggle, "soon") + Haptics (disabled toggle, "soon").
  - **Other** — Replay tutorial (disabled "tap", "soon") + Tip jar (disabled "tap", "soon") + About (live "tap" opens a small sheet).
- **Footer** pinned to bottom: `"v0.4 · ching by fastronaut"`. Cochin italic, dim ink, centered.

Segmented control style: hand-rolled, not SwiftUI's `Picker(.segmented)`, because the default style doesn't match the 1-bit aesthetic. Implementation: a three-cell HStack of equal-width tappable cells with 1px ink borders, the selected cell fills with ink and inverts its text to paper.

Toggle style: hand-rolled. A 1.5px-bordered ink rectangle 34pt × 20pt with a 14pt ink square thumb that snaps left/right. Same in light + dark (palette inverts).

About sheet: presented modally via `.sheet`. Plain text: app name, version, `"ching by Fastronaut"`, one-line description. Dismissable.

## Vocabulary changes

Engine internals are untouched. All changes are user-facing string literals or labels in SwiftUI views.

| Old (Phase 3) | New (Phase 4) | Where |
|---------------|---------------|-------|
| `"CHING"` | `"ching!"` | Logo, Bodoni 72, italic |
| `"CENTER"` section label | `"Safes"` | Game screen, italic Cochin small caps |
| `"VAULTS"` section label | `"Vaults"` | Game screen, italic Cochin small caps |
| `"YOU"` / `"JONES"` / `"BOT 03"` in vault names | `"You"` / `"Jones"` / `"Bot 03"` | Game screen vault row names. Engine `state.players[i].id` stays `"YOU"`/`"JONES"`/`"BOT 03"`; conversion to mixed case happens in the view. |
| `"STEAL FROM JONES"` (Bank label) | `"Steal Jones's safe"` | `GameStore.bankActionLabel`, lowercase except names |
| `"Bank"` | `"Bank"` (unchanged) | Stamp button, Bodoni uppercase |
| `"Roll"` | `"Roll"` (unchanged) | Stamp button, Bodoni uppercase |
| `"Phase: roll"`, `"Turn: YOU"`, `"Scores: …"` separate lines | Compact: `"Turn · You · roll phase"` (italic Cochin label) then `"You 0 · Jones 0 · Bot 03 0"` (Cochin numerals) | Game screen header |
| `"Game over"` alert title | `"Game over"` (unchanged) | Alert title |
| `"<NAME> wins."` / `"Tie at the top."` body | unchanged | Alert body |

Internally:
- `state.players[i].id` strings stay uppercase (`"YOU"`/`"JONES"`/`"BOT 03"`). Vocabulary mapping is a single helper in the view (e.g. `displayName(_ id: String) -> String`).
- `state.centerTiles` (engine field name) is unchanged. The view layer renders this as a "Safes" row.

## Architecture

### `ColorMode` enum

New app-local enum, lives in `SettingsStore.swift` (since `SettingsStore` is its only consumer).

```swift
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
```

### `SettingsStore`

New `@MainActor @Observable` reference type owning all persisted user prefs. Backed by UserDefaults under the `ching.*` key namespace.

```swift
@MainActor
@Observable
final class SettingsStore {
    var difficulty: Difficulty { didSet { persist } }
    var colorMode: ColorMode { didSet { persist } }
    var reducedMotion: Bool { didSet { persist } }

    init() {
        // Load each from UserDefaults with sensible defaults:
        // difficulty: .normal
        // colorMode: .system
        // reducedMotion: false
    }
}
```

UserDefaults keys:
- `"ching.difficulty"` — already used by Phase 3, value semantics preserved.
- `"ching.colorMode"` — new.
- `"ching.reducedMotion"` — new.

### `GameStore` changes

- The `difficulty` property and its UserDefaults persistence are removed from `GameStore`.
- `GameStore.init(seed:, settings:)` takes a `SettingsStore` reference.
- `currentAIDifficulty` reads from `settings.difficulty` instead of an internal property.
- All other Phase 3 behaviour is unchanged.

### `CHINGApp` changes

- Wraps the root in `NavigationStack`.
- Owns a single `SettingsStore` instance and a single `GameStore` instance.
- Applies `.preferredColorScheme(settings.colorMode.preferredScheme)` on the root.

```swift
@main
struct CHINGApp: App {
    @SwiftUI.State private var settings = SettingsStore()
    @SwiftUI.State private var store: GameStore

    init() {
        let s = SettingsStore()
        _settings = .init(initialValue: s)
        _store = .init(initialValue: GameStore(seed: UInt32.random(in: 1...UInt32.max), settings: s))
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

(Exact init pattern resolved during implementation; the above shape is illustrative.)

### `GameView` changes

- Takes `store` and `settings` as constructor parameters (no more internal `@SwiftUI.State` creation).
- New top-right gear icon as a `NavigationLink(destination: SettingsView(settings: settings))`.
- The Phase 3 top-of-screen segmented difficulty picker is removed (lives in Settings now).
- Layout updates per the visual surface section above.
- `act` helper computes effective reduce-motion as `settings.reducedMotion || env.accessibilityReduceMotion` and passes to `store.runAIIfNeeded`.

### `SettingsView`

New file. Contains:
- `SettingsView` (the main view).
- The hand-rolled `StampSegmented<T>` view (used twice: Difficulty, Color mode).
- The hand-rolled `StampToggle` view (used three times: Reduced motion, disabled Sound, disabled Haptics).
- The `AboutSheet` subview.

### `DesignSystem.swift`

New file. Centralises tokens:
- `Color.paper`, `Color.ink`, `Color.dimInk` — palette functions that read the current `ColorScheme`.
- `Font.cochin(_ size:)` / `Font.bodoni(_ size:)` — typed font helpers with fallback chains.
- `View.stampShadow()` — `ViewModifier` applying the 2px hard offset shadow.
- `View.stampButton(primary:)` — `ButtonStyle` applying the full stamp look.

### Navigation

`NavigationStack` at the app root. Game is the always-visible root. Settings is pushed by a `NavigationLink`. Back gesture (swipe from left edge) returns to Game. No deep nav stack, no tab bar.

### Data flow

```
SettingsStore (root)
  ├── CHINGApp reads .colorMode → .preferredColorScheme
  ├── GameStore reads .difficulty → drives currentAIDifficulty
  └── SettingsView edits all three properties

GameStore (root)
  └── GameView reads state + dispatches actions
```

`SettingsStore` and `GameStore` are siblings under `CHINGApp`. `GameStore` holds a reference to `SettingsStore` for the difficulty read.

## Testing

### New `SettingsStoreTests`

- `test_settings_difficulty_defaultIsNormal`
- `test_settings_difficulty_persistsAcrossInstances`
- `test_settings_colorMode_defaultIsSystem`
- `test_settings_colorMode_persistsAcrossInstances`
- `test_settings_reducedMotion_defaultIsFalse`
- `test_settings_reducedMotion_persistsAcrossInstances`

All tests must clear `ching.difficulty`, `ching.colorMode`, `ching.reducedMotion` keys in `setUp` and `tearDown` to avoid bleed.

### Existing `GameStoreTests` adjustments

- The Phase 3 `test_difficulty_defaultIsNormalOnFirstLaunch` and `test_difficulty_persistsAcrossInstances` tests move into `SettingsStoreTests` and are renamed.
- All `GameStore(seed:)` instantiations gain a `settings:` parameter. Helper in the test file: `private func makeStore(seed: UInt32 = 1) -> GameStore { GameStore(seed: seed, settings: SettingsStore()) }`.
- `currentAIDifficulty` test stays: read it via the injected `SettingsStore`.

### Optional `GameViewVocabularyTests`

A tiny test file that asserts the user-facing string constants haven't drifted. Only worth adding if the vocabulary changes prove fragile; can be cut from Phase 4 if it feels like over-testing.

### Engine tests

`swift test` in `ios/CHINGEngine` must remain 32/32 green. No engine code changes.

### Manual verification on the simulator

- Game screen renders the new layout: Bodoni `ching!`, Cochin numerals, vault rows column-aligned, dice tray centered.
- Tap the gear icon, Settings screen pushes in. Tap back, Game returns.
- Change difficulty in Settings, back out, take a turn — AI uses new difficulty.
- Change Color mode to Dark, the app inverts to paper-on-ink immediately.
- Change Color mode to Light, immediate switch back. Change to System, the app honors the iOS appearance setting.
- Toggle Reduced motion in Settings to on, take a turn — AI plays instantly. Toggle off, take another, pacing returns.
- Toggle iOS Reduce Motion in `Settings > Accessibility > Motion` while the in-app toggle is off — AI plays instantly. Confirms the OR logic.
- Play to game over. Alert reads the new vocabulary (mixed-case names, ranked scores).
- Tap About in Settings. Sheet appears with version + tagline. Dismiss.
- Quit, relaunch. Difficulty + color mode + reduced motion all persisted.

## Definition of done for Phase 4

- Engine tests: 32/32 green, unchanged.
- `SettingsStoreTests`: 6 tests, all green.
- `GameStoreTests`: adjusted Phase 3 tests still pass with the new `SettingsStore` injection pattern.
- `xcodebuild -only-testing:CHINGTests` returns `** TEST SUCCEEDED **`.
- App builds for iPhone 17 Pro simulator under both light and dark mode.
- Manual checklist above passes end-to-end.
- A pair of proof-of-life screenshots in `docs/superpowers/`: one Game screen (light), one Settings screen (dark).
- Branch merged to `main` via PR.
- All file splits land cleanly: `DesignSystem.swift`, `SettingsStore.swift`, `SettingsView.swift` exist as new files.

## Risks and open questions

### Resolved during this brainstorm

- Layout: linear stack, centered dice tray, column-aligned vaults.
- Typography: Bodoni 72 logo + stamp buttons, Cochin everything else.
- Vocabulary: ching!, safes, vaults, mixed-case names.
- Visual treatment: flat stamped (depth deferred), 1.5px borders, 2px hard offset shadow, no gradients, no rounding.
- Color modes: light + dark together, paper-on-ink inversion.
- Settings shape: 4 sections, 3 live controls + 4 placeholders + 1 live About sheet.
- Navigation: NavigationStack push from gear icon.
- Architecture: `SettingsStore` extraction, `GameStore` slimmed.

### Genuinely open, deferred to build phase

- The exact dim-ink color hex (~`#6B6B6B` / ~`#9A9A9A` as starting points).
- About sheet body copy.
- The bordered segmented control + toggle styling at the pixel level; mockups in the brainstorm folder are CSS approximations.
- Whether to keep `GameViewVocabularyTests` as a real test file or rely on visual review.

### Known risks

- **Bodoni 72 availability on the iOS simulator.** Apple bundles Bodoni 72 on iOS, but a future iOS revision could drop it. The fallback chain (Didot → system serif) is the safety net. Visual check on the actual simulator is mandatory before merge.
- **Hand-rolled segmented + toggle styling.** Default SwiftUI `Picker(.segmented)` and `Toggle` carry iOS-system styling that fights the 1-bit aesthetic. Rolling our own is required, but they need to remain accessible (VoiceOver labels, focusable). Implementation must wire `.accessibilityLabel` correctly.
- **Color mode and `@Environment(\.colorScheme)`.** When `colorMode = .system`, we set `.preferredColorScheme(nil)` and read `@Environment(\.colorScheme)` inside views to pick palette colors. When `colorMode = .light` or `.dark`, the `.preferredColorScheme` modifier forces the environment value, so the same `@Environment(\.colorScheme)` read still works. This is the canonical pattern; flagging it here so the implementer doesn't try to hand-resolve the mode in a custom helper.
- **UserDefaults bleed between tests.** Same risk as Phase 3 — tests for `SettingsStore` must reset all three keys in `setUp`/`tearDown`.
- **Custom button press animation** (the 2px-depress on tap). Implementing this with `.buttonStyle` requires intercepting the press state via `GestureState` or `ButtonStyleConfiguration.isPressed`. Phase 4 may ship without the press animation if it proves fiddly; the static stamp look already reads as a stamp.
