# Shell Yes — tally festivity, active-card glow, bust-modal clarity, per-mode stats

**Written:** 2026-06-08
**By:** Claude (Opus 4.7, 1M)
**For:** the next Claude session
**Branch:** `theme-refinement` (still off `shell-yes-rebrand`, neither merged to main)
**HEAD before this session:** `94d48fe` — same as the prior two handoffs.
**Predecessors:**
- [[2026-06-07-shell-yes-ux-pass-handoff]] (afternoon)
- [[2026-06-07-shell-yes-testflight-prep-handoff]] (early evening)
- [[2026-06-07-shell-yes-evening-aptabase-handoff]] (late evening)

## TL;DR

Six things landed, all sitting on top of last night's still-uncommitted work:

1. **Tally screen actually celebrates** — `you win.` headline animates per-letter (bounce + continuous shimmer + breath lift) for the human win, and the winning card's edge sparkles now visibly shoot outward (room added between rows so they don't crash neighbours).
2. **Active player card has a steady warm-gold cue** — replaces the old coral subtle pulse. Iterated four times: gold halo → layered amber+cream halo → dialed back 35% → killed the pulse entirely (it pulsed on device but not sim; Bram preferred steady).
3. **`game_steal` Aptabase event** — canonical, fires from `detectSteal` for both directions so we can finally see how often the user gets robbed.
4. **Bust modal names the loss** — "You lose your top shell." with the player's returned shell rendered as a chip (labelled `yours`). The sand-burn only shows as a second chip when it's a different tile.
5. **Stats per mode** — `StatsStore` now tracks wins/games keyed by `Difficulty.rawValue` and `GameSpeed.rawValue`; Settings has two new cards (`by difficulty`, `by pace`) showing `wins/games · pct%`.
6. **App version finally matches Aptabase** — bundle was `1.0`, footer was hardcoded `v0.5`; fixed by setting `MARKETING_VERSION = 0.5` everywhere and reading `CFBundleShortVersionString` via `AppVersion.short` in `SettingsView` + About.

All committed at end of session. Still no TestFlight (Apple Dev Program enrollment still blocked on Belgian ID verification — see prior handoffs).

## What shipped this session

### Tally screen — festive `you win.` + working edge sparkles

`CountingCeremony.swift`.

**Festive headline (`WinHeadline` private view).** Replaces the static gold `Text` for the human-win case only. Renders each character in its own `Text` so each can animate independently:
- **Entry:** `.spring(response: 0.55, dampingFraction: 0.5)` with a 0.05s per-character delay; each glyph springs up from `offset y +22`, `scale 0.25`, `rotation -8°`.
- **Continuous shimmer:** shadow radius `12 ↔ 22` and opacity `0.55 ↔ 0.95` on `Color.coinGoldLight`, easeInOut 1.1s autoreverse forever.
- **Breath lift:** each glyph drifts `y: 0 ↔ -2pt` with a per-character delay so the row reads as a wave, not a metronome.
- Size bumped 30pt → **40pt bold italic** for the human-win path. Non-human win (rival wins, tie) keeps the original 30pt demiBold rendering — single `Text`, no per-letter dance.

**Headline sparkle cadence.** A `SparkleField(count: 44, startRadius: 18, spread: 95, duration: 1.4)` overlay re-fires on `humanWinHeadlineSparkle` which increments every 2.1s (offset from the card sparkle wave at 1.5s so the screen doesn't pulse in unison).

**Winning-card edge sparkles — the "still. not." fix.** The previous tuning (count 110, inset 2, spread 38, duration 1.5) was deliberately tight so flying particles didn't overlap the adjacent player cards in the VStack (which had `spacing: 14`). Bram pointed out they didn't read as sparkles "shooting from edges" — they died at the border. Fix:
- `EdgeSparkleField`: `count 130, inset 0, spread 80, duration 1.1` — actually escapes the card.
- VStack `spacing: 14 → 28` on winner-reveal, with `.easeOut(duration: 0.5)` animation, so the cards spread apart and give the louder sparkles somewhere to go.

State plumbing: `@SwiftUI.State humanWinHeadlineSparkle: Int`, ticked in a `Task { @MainActor … }` loop spawned during `runCeremony()` just before the existing card sparkle loop.

### Active player card — steady warm-gold glow

`Scoreboard.swift`.

**The brief:** Bram pointed at the New Game button's golden breathing halo and wanted that cue behind the active player's card.

**Iteration log (worth keeping — UX exploration that's now closed):**

1. **First try** — replaced the active card's coral shadow with `Color.coinGoldLight.opacity(pulse ? 0.88 : 0.22)`, radius `16 ↔ 26`. Same `pulse` state the New Game button uses. Active border tinted gold. Applied to all active seats, not only AI. *Result:* invisible. Background was too light to register cream gold as anything but white.
2. **Second try** — layered shadows: outer `Color.gold @ 0.45 ↔ 0.85` radius `22 ↔ 32` plus inner `coinGoldLight @ 0.5 ↔ 0.9` radius `8 ↔ 12`. Amber for contrast against the sky, cream for hot core. *Result:* still subtle.
3. **Third try** — escalated to all-of-the-above: tinted card fill (`coinGoldLight.opacity(0.55 ↔ 0.78)` instead of `white.opacity(0.45)`), solid gold border @ 2pt, `scale 1.06`, `lift -4pt`, `zIndex 1`. *Result:* "too harsh."
4. **Fourth try** — dialed all values back ~35%: fill `0.30 ↔ 0.48`, border `gold @ 0.7` 1.5pt, scale `1.03`, lift `-2pt`, halos toned down. *Result:* good visually, but on physical iPhone the pulse was distracting (sim didn't show it because of the throttled animation loop). "Not pulsing is better. Less distracting."
5. **Final** — removed the `pulse` `@State` and its `.task` loop entirely. All previously-ternaried values collapsed to the midpoint:
   - Fill: `coinGoldLight @ 0.40`
   - Outer halo: `gold @ 0.45`, radius `22`
   - Inner halo: `coinGoldLight @ 0.55`, radius `8`
   - Border: `gold @ 0.7`, 1.5pt
   - Scale: `1.03`
   - Lift: `y: -2pt`
   - `zIndex(1)` so the halo doesn't get clipped by neighbouring columns.

**Steal / active interplay:** coral stays *exclusively* the steal-flash cue. Coral and gold can't both render on the same column (steal target ≠ active player), so the rules don't collide.

**One-shot sparkle on AI turn-start** (`activeSparkleTriggers`) is preserved as the discrete "they're up" cue. Only the continuous pulse is gone.

### `game_steal` telemetry event (canonical steal)

`GameView.swift:detectSteal`.

Before: only the human-side steal got tracked, via `game_bank` with `stole_from_rival: true/false`. AI-steals-from-human was visible as the `stolenFromIdx` coral flash but didn't reach Aptabase.

New event, fires once per transfer for both directions:

```
game_steal {
  actor:            "you" | "sage" | "marlow" | ... (player.id at the moment)
  victim:           same shape
  tile_value:       21–36 (engine: tiles.last on the actor after apply)
  actor_was_human:  Bool
  victim_was_human: Bool
}
```

`game_bank.stole_from_rival` is left in place for dashboard backward compat. Dashboard panel needed: "Times user got robbed" = `count(game_steal where victim_was_human = true)`. **Telemetry checklist memory:** dashboard work pending; add to Debug env first, then Release.

### Bust modal — "you lose this shell" made unambiguous

`ExplainerView.swift` (rules page) + `GameView.swift` (in-flight bust banner).

**Why:** Bram asked "When does one lose a tile without it being stolen?" — testing whether the rule was communicated. Answer: only when you bust. The explainer's "busting" page already mentioned it but in poetic language; the in-game bust banner showed the burned sand-tile but never named the player's own returned shell.

**Explainer changes:**
- Bust page headline: `"No pickable face?"` → `"Bust = lose your top shell."`
- Bust page body: rewritten to be plain-spoken about the loss: "Roll into nothing pickable, or stop without a pearl in hand. Your top shell drifts back to the beach — and the largest shell on the sand washes away with it. No rival took it; the tide did."

**Bust banner changes (`bustLossSection()`):**
- New `@SwiftUI.State bustReturnedTile: Int?` captures the human's pre-bust top shell when `afterVault < beforeVault`. Reset on restart.
- Section logic:
  - **Returned shell + distinct burned sand-shell:** caption "You lose your top shell.", two chips side by side (`yours` / `sand`), follow-up line "And the largest shell on the sand drifts away."
  - **Returned shell that IS the burned tile** (player's returned top was the new pool max, so it returns and immediately burns — same physical shell): single chip labelled `yours`, no double-counting.
  - **No returned shell** (busted with empty vault), burned-only: existing "A shell drifts away." behaviour.
- Replaces the old "A shell drifts away." block in the bust overlay's VStack.

### Stats — per Difficulty / per Pace breakdown

`StatsStore.swift`, `GameView.swift`, `SettingsView.swift`.

**New persisted dicts** (UserDefaults round-trip via `[String: Int]`):
- `gamesByDifficulty`, `winsByDifficulty` — keyed by `Difficulty.rawValue` (`easy` / `normal` / `hard`)
- `gamesByPace`, `winsByPace` — keyed by `GameSpeed.rawValue` (`slow` / `fast`)

`recordGameOver` signature changed: `recordGameOver(humanWon:humanScore:difficulty:pace:)`. Call site in `GameView` (game-ended onChange) passes `settings.difficulty.rawValue` and `settings.gameSpeed.rawValue`.

**Settings UI:** two new `glassCard` sections under the main `stats` card:
- **by difficulty** — one row per `Difficulty.allCases`, value formatted via new `modeValue(wins:games:)` helper: `"wins/games · pct%"` (e.g. `"3/8 · 38%"`) or `"—"` if zero games in that mode.
- **by pace** — same pattern for `GameSpeed.allCases`.

The Aptabase `game_ended` event already carried `difficulty` and `pace` props, so local stats now mirror what's already tracked remotely.

### App version sync (Aptabase 1.0 ↔ in-app v0.5)

`SettingsView.swift`, `ShellYes.xcodeproj/project.pbxproj`.

**Problem:** Aptabase reported `app_version: 1.0` (bundle's `CFBundleShortVersionString`, set via `MARKETING_VERSION` in the project — defaulted to `1.0` when the target was created). In-app footer + About sheet hardcoded `"v0.5"`.

**Fix:**
- `MARKETING_VERSION = 1.0;` → `MARKETING_VERSION = 0.5;` across all configurations (5 places in `project.pbxproj`).
- New `AppVersion.short` enum in `SettingsView.swift` reads `Bundle.main.infoDictionary["CFBundleShortVersionString"] as? String ?? "?"`.
- Footer line + About sheet now use `"v\(AppVersion.short)"`. Next time `MARKETING_VERSION` bumps, the in-app strings update automatically; they can't drift again.

## Files touched

- `ios/ShellYes/ShellYes.xcodeproj/project.pbxproj` — `MARKETING_VERSION` 1.0 → 0.5
- `ios/ShellYes/ShellYes/CountingCeremony.swift` — `WinHeadline`, headline sparkle wave, edge sparkle tuning, VStack spacing
- `ios/ShellYes/ShellYes/Scoreboard.swift` — gold halo (steady), removed `pulse` state + task, scale/lift/zIndex
- `ios/ShellYes/ShellYes/GameView.swift` — `bustReturnedTile` state, `bustLossSection()`, `game_steal` event, `recordGameOver` call site
- `ios/ShellYes/ShellYes/ExplainerView.swift` — bust page headline + body
- `ios/ShellYes/ShellYes/StatsStore.swift` — per-mode dicts + UserDefaults persistence, `recordGameOver` signature
- `ios/ShellYes/ShellYes/SettingsView.swift` — `by difficulty` / `by pace` sections, `modeValue()` helper, `AppVersion.short`, dynamic version strings

## What did NOT change

- `ShellYesEngine` — no engine changes this session. All work was iOS app layer.
- Aptabase dashboards — the new `game_steal` event needs a panel added in the Debug env, then promoted to Release. **Telemetry checklist** applies.
- Build target / scheme / signing — untouched.

## Open follow-ups

1. **Dashboard panels** for `game_steal` (Debug env first, then Release). See [[shell-yes-debug-vs-release-aptabase]].
2. **Apple Dev Program enrollment** still blocked. Carryover from prior handoffs.
3. **None of this is committed yet** as of writing — covered by the end-of-session commit.

## Verification

- `xcodebuild -project ShellYes.xcodeproj -scheme ShellYes -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build` → **BUILD SUCCEEDED** after each change.
- Visual checks performed by Bram on physical iPhone (which is what surfaced the pulse-distraction; sim didn't show it). The "still. not." edge-sparkle fix and the bust-modal rewrite were also iPhone-verified.
