# CHING for iOS, v1 Design

**Status:** approved for planning
**Date:** 2026-06-05
**Owner:** Bram

## Context

CHING is a push-your-luck dice game already shipping as a terminal app (TypeScript engine + ANSI renderer + AI + SSH/TCP multiplayer daemon). The engine and AI were deliberately built pure so that future shells could reuse them. This document specifies an iOS shell.

The iOS version is a portfolio piece. Commercial success is not a goal; ship-quality polish is. App Store launch is the target.

## Goals and non-goals

### In v1

- Solo vs 1 to 3 AI opponents on a single device.
- Three AI characters with distinct play personalities.
- Global Easy / Normal / Hard difficulty modifier on top of characters.
- Full game loop: pick, score, push, bank, bust, steal, depletion, end.
- Interactive in-game onboarding for first-time users, replayable from Settings.
- Local persistence: settings, in-progress game resume, last-used opponents/difficulty.
- Sound and haptics on key events, both globally toggleable.
- Light mode and dark mode, both designed deliberately.
- iPhone only, portrait only, iOS 17+.
- Free in the App Store, no IAP, no ads, optional tip jar.

### Explicitly out of v1

- All multiplayer (pass-and-play, Game Center async, LAN).
- Game Center leaderboards and achievements.
- A Stats screen (deferred to v1.1 alongside Game Center).
- iPad layout.
- Landscape orientation.
- Localization beyond English.
- iCloud cross-device save.
- Custom rule variants or house rules.
- A dedicated "How to play" text screen. Tutorial is the only rules surface; replay from Settings if needed.

### v1.1 and beyond (informational)

- Game Center: leaderboards (best single-game score, longest non-bust streak) and achievements.
- Stats screen, surfaced alongside Game Center sign-in.
- Optional async multiplayer via Game Center (the Words With Friends model).
- Possibly iPad, landscape, additional characters, localization.

## Visual and motion language

The direction is **1-bit with ordered dithering**: ink on paper, two colors, no gradient, no skeuomorphism. References: Obra Dinn, Patrick's Parabox, Mark Ferrari's stippling work, early Macintosh System 1 UI, classical engraving plates. Density carries hierarchy; type carries personality.

### Composition principles

- **Asymmetric, ledger-like layout.** The game screen is not centered-and-stacked. Title at top-left, metadata stack top-right, vault ledger strip below, dice tray center stage, center tile rack, play log, action bar at the bottom.
- **Watermark lattice** fading from the top of the screen, evoking printed banknote stock. Subtle.
- **Stamp-style action buttons** at the bottom edge of the game screen, heavy weight, hard borders. Bank inverts to ink-on-paper to signal commitment.
- **Live play log** as a signature element. The last few game events render as one-line ledger entries on the game screen, giving the play a sense of unfolding history.

### Type system

- **Display serif** for expressive characters: app title, dice numerals, tile numerals. Uses tabular and lining figures. The exact family is finalized during build, candidates include Cochin, Hoefler Text, Didot, Bodoni 72.
- **System monospace** for labels, log timestamps, button text, system metadata.
- The title is set lowercase italic with a period as an identity mark: `ching.`

### Density vocabulary

Dither density is the primary tool for hierarchy. A small fixed scale, used consistently:

- 0% (paper): live, available, foreground.
- ~25% (light stipple): subtle texture, fake-shading the lit faces of dice for a hint of 3D.
- ~50% (mid hatching): locked dice fill.
- ~75% (dense): dimmed center tiles, burned-out states.
- 100% (ink): primary action, coin face, the active vault accent.

The active vault row sits on a 25% stippled bed. The "reachable" highlighted tile inverts to 100% ink. The coin die is solid ink with a dotted ring around the symbol.

### Design rules

- No tilting, no rotation. Straight lines, snap to grid. Tilting reads as cute; the design is decisive.
- No gradients, no soft shadows. Drop shadows are stamped: a hard 2px offset block, no blur.
- No skeuomorphic textures. No paper texture beyond the dot-noise baseline. No leather, no wood, no felt.
- Tabular figures everywhere numerals appear.
- Light and dark mode swap ink for paper consistently. Dark mode is paper-on-ink, not dim-ink-on-grey.

### Motion language

- Dice **stamp** into place, they do not roll. Snap-based, no easing curve longer than ~150ms.
- Dither density transitions are the primary state change cue (e.g. a die going from live to locked animates from 0% to 50% density over ~120ms).
- The ka-ching moment is a full-screen invert (paper becomes ink, ink becomes paper) for ~80ms, then the banked tile slides home from the center rack to the vault row.
- The bust moment is a tile peeling off the vault with a paper-fold transform, then the highest center tile burns out with a dither-density ramp from 0% to 100%.
- Reduced motion (Settings toggle, also honored if iOS Reduce Motion is on): all of the above collapse to instant state changes with no transition, except the ka-ching invert which becomes a single quick flash.

## Screens and flow

Six screens total. No tab bar, no nav bar. Modal navigation from Home.

### 1. Splash

Cold open. Title (`ching.`) centered, the only element. Tap or short delay advances to Home. First-time users go from Splash to Onboarding instead.

### 2. Home

Three things stacked vertically: PLAY (primary), CONTINUE GAME (only shown if a resume game exists), then SETTINGS. Nothing else. No daily challenge, no live tile, no nag.

### 3. Game

The main play screen. Six zones, top to bottom: header (title + round/turn meta), vault ledger strip (you + opponents), dice tray, center tile rack, play log (last few events), action bar (Roll, Bank). PLAY from Home drops directly into a game using last-used opponents and difficulty.

### 4. Receipt

Shown at end of game. Printed-bill style: final scores ranked, highlights (longest non-bust streak, biggest single bank, ka-chings, busts). Two actions: HOME and PLAY AGAIN. A smaller "Change opponents" affordance reveals a mini-config sheet (which characters, what difficulty) before starting the next game.

### 5. Settings

Toggles: Sound, Haptics, Reduced motion, Dark mode. Links: Replay tutorial, Tip jar, About. Reached from Home, dismisses back to Home. (A "Reset" affordance is deliberately omitted in v1; without a Stats screen there is nothing meaningful to reset beyond manually-toggled preferences. Returns in v1.1 alongside Stats.)

### 6. Onboarding

Interactive, embedded in a real game versus a single tame bot (Jones at lowest difficulty). Coach overlays highlight the next move ("tap two dice with the same face to lock them"). Three or four total overlays cover: pick, score, bank, bust. Skippable at any point. Completing or skipping seeds the last-used config so the next PLAY just works. Replayable from Settings.

### Flow summary

- **First launch:** Splash → Onboarding → Receipt (tutorial complete) → Home
- **Returning, no game in progress:** Splash → Home
- **Returning, game in progress:** Splash → Home (CONTINUE GAME visible)
- **Main loop:** Home → Game → Receipt → (Play Again → Game) or (Home)
- **Utility:** Home → Settings → Home

## Game model

The rules are exactly the rules already implemented in `src/engine.ts`. The iOS version ports them, it does not redesign them. The engine port is mechanical: the same state shape, the same reducer signature `(state, action, rng) => state`, the same purity guarantees.

Quick recap of the rules in scope:
- Roll 8 dice. Pick a face value (1 to 5, or coin = 5), lock all dice of that face.
- A face cannot be picked twice in a turn.
- After every pick, choose to roll again (push) or bank (stop).
- Bank: take the highest center tile (or steal a rival's top tile) whose number ≤ your locked total, provided you locked at least one coin face.
- Bust (no scoring face left, or cannot bank): return your top tile to the center and burn the highest remaining center tile.
- Game ends when no center tiles remain. Highest vault total wins (tile face values).

No mobile-specific rule additions in v1.

## AI and difficulty

### Characters

Three characters, each with a base discipline value. Discipline is inverted from "risk": higher discipline means harder, stops earlier, banks any reachable tile. Lower discipline means greedy, holds out for 4-coin tiles, busts more.

- **Jones** (red, ●). Base discipline 0.30. Greedy theatrical loser-and-occasional-big-winner. Holds out for 33 to 36, busts often, lands the occasional ka-ching that shifts the game.
- **Merit** (blue, ●). Base discipline 0.55. Balanced. Banks reasonable tiles, plays percentages. Hardest to read because there is no signature move.
- **Bot 03** (yellow, ●). Base discipline 0.85. Cold and relentless. Banks fast, low bust rate, accumulates by attrition.

(Character names and colors are placeholders, finalized during build. The personality model and base discipline values are spec.)

### Difficulty

A single global modifier shifts every character's effective discipline:

- **Easy:** all characters minus 0.15 discipline (clamped to ≥ 0).
- **Normal:** no modifier.
- **Hard:** all characters plus 0.15 discipline (clamped to ≤ 1).

Effective values:

| Character | Easy | Normal | Hard |
|-----------|------|--------|------|
| Jones     | 0.15 | 0.30   | 0.45 |
| Merit     | 0.40 | 0.55   | 0.70 |
| Bot 03    | 0.70 | 0.85   | 1.00 |

This keeps each character's personality readable across difficulties while letting the player tune overall heat.

### Opponent selection

- **Default cast:** 1v2 (Jones + Bot 03). The loud and the cold. Chosen because their personalities are maximally distinct.
- **Player override:** Receipt has "Change opponents," revealing a mini-sheet to toggle which characters (1 to 3) and pick difficulty. The chosen config persists as last-used and seeds future PLAY taps.
- The player does not pick characters during onboarding. Onboarding always faces Jones on Easy, so the player sees a forgiving but recognizable personality.
- **First-time PLAY (rare edge case where onboarding is skipped immediately and no last-used config exists)** falls back to the default: 1v2 with Jones + Bot 03 on Normal.

## Persistence

Plain `Codable` JSON files written to the app sandbox. Three files:

- `settings.json`. Sound, haptics, reduced motion, dark mode booleans.
- `last-config.json`. Opponents (which characters are active) + difficulty.
- `resume-game.json`. Serialized full game state if a game is in progress. Written after every state transition. Deleted on game completion.

No Core Data, no SwiftData, no iCloud sync in v1.

## Sound inventory

Seven cues, all short:

- `kaching.caf` — primary bank/score moment. Sacred per CLAUDE.md; do not water down.
- `pick.caf` — die selection.
- `lock.caf` — die locks after a pick (thunk).
- `bust.caf` — bust + center tile burn (combined sting).
- `steal.caf` — successful steal of a rival's tile (stamp).
- `receipt.caf` — end of game (printed receipt feeding through).
- `tap.caf` — generic UI button tap, used sparingly.

Globally muted by the Settings toggle. Honors the iOS silent switch.

## Haptics inventory

Five cues, mapped to UIImpactFeedbackGenerator and UINotificationFeedbackGenerator:

- Rigid impact on die lock.
- Soft impact on die pick.
- Success notification on ka-ching.
- Error notification on bust.
- Light impact on UI buttons (only the primary action; secondary buttons silent).

Globally muted by the Settings toggle.

## Pricing and distribution

- **Price:** free.
- **No IAP, no ads, no subscription.**
- **Optional tip jar** as a small consumable IAP, single tier, ~$2.99, accessible from Settings only. Never prompted, never blocking.
- **App Store:** standard submission. App Store listing copy, screenshots, and metadata done as part of v1 ship.

## Tech architecture

### Repo shape

Monorepo. Existing structure stays. New top-level directories:

- `/ios/` — Xcode project, Swift sources, assets, tests.
- `/parity/` — cross-engine parity test harness (Node + Swift CLI runners against shared fixtures).

The TypeScript terminal version in `/src/` freezes as v0. If iOS adds rules later, the terminal does not necessarily follow. The CLAUDE.md "swappable renderer" promise is retired in favor of "iOS is the canonical CHING from now on."

### Xcode project

- Single SwiftUI app target.
- iOS 17+ minimum (allows free use of `@Observable`).
- iPhone only, portrait only.
- Swift Package Manager for any dependencies. No third-party packages anticipated for v1.

### Engine port

Hand-port, not transpiled.

- `engine.ts` → `Engine.swift`. Pure structs for state, pure functions for the reducer. No `Foundation.Date`, no `Math.random`. Randomness via injected `RandomNumberGenerator`.
- `ai.ts` → `AI.swift`. Same purity guarantees, takes the engine state and a discipline value, returns a decision.
- Existing TS tests guide the port: each test in `tests/` has a Swift counterpart with the same fixtures.

### Parity testing

The safety net for two engines coexisting without silent drift.

- A small harness in `/parity/` that defines a sequence of (seed, action sequence) cases.
- Two runners: a Node script that feeds the cases into the TS engine and emits a JSON state trace, and a Swift CLI that feeds the same cases into the Swift engine and emits the equivalent trace.
- A diff script asserts trace equality.
- Runs in CI on every PR that touches the engine, and locally before any engine change.

### View layer

- `GameStore: ObservableObject` (or `@Observable` class) wraps the engine state and AI driver, exposes actions, drives SwiftUI views.
- Views are thin renderers. Game rules never live in views. Same architectural promise as the CLI.
- No Combine, no third-party state libraries (TCA, Redux, etc.) in v1.

### Testing

- XCTest (or Swift Testing) for Engine and AI unit tests, mirroring `tests/`.
- The 200-game AI-vs-AI simulation from `sim/` ports to Swift. CI asserts that higher-discipline characters still beat lower-discipline ones over the sample, the same regression that exists today.
- Snapshot tests skipped for v1. Visual review by eye.

### CI

- GitHub Actions: on every PR, run engine unit tests, run AI sim regression, run parity tests, build the app, run any UI smoke tests.
- No automated TestFlight deploy in v1. Manual archive and upload from Xcode.

## Definition of done for v1

- All six screens shipping at full polish, both light and dark modes.
- Engine and AI fully ported. All TS engine tests have Swift counterparts and pass.
- Parity tests green: TS and Swift engines produce identical state traces for the parity fixture set.
- 200-game sim ported. The regression passes: higher discipline beats lower discipline over the sample.
- All seven sound cues recorded, mastered, and wired. Mute toggle works.
- All five haptic cues wired. Mute toggle works.
- Reduced motion mode degrades all motion to instant state changes (or single flash, for ka-ching).
- App icon and splash designed in keeping with the visual language.
- App Store screenshots, listing copy, metadata complete.
- Manual TestFlight build passes Apple review.

## Risks and open questions

### Resolved during brainstorming

- Art direction (1-bit + dither), tech stack (native Swift), engine strategy (hand port, parity-tested), end condition (current depletion rule), opponent + difficulty model, pricing model. All settled above.

### Genuinely open, deferred to build phase

- Final display serif family selection. Candidates listed above; locked once a typography pass happens during the visual-design milestone.
- Final character names (placeholders: Jones, Merit, Bot 03). Naming pass during build.
- Final tip jar amount and copy.
- Exact onboarding flow (3 vs 4 coach overlays, exact prompts). Designed and playtested during build.
- Sound design: in-house vs licensed. Out of scope for design doc; addressed in implementation plan.

### Known risks

- **The TS engine is the source of truth during the port.** If a rules question arises during porting, the TS engine wins, not the Swift port. The parity harness enforces this.
- **Apple review** has rejected push-your-luck and dice games in the past for "encouraging gambling" framings. Mitigation: no IAP currency, no chance mechanics presented as wagers, no "real money" framing. The game uses tiles and coin tokens, not betting language.
- **Two-engine drift over time** is the primary maintenance risk. The terminal version is officially deprioritized but not deleted. If active terminal development resumes, the parity harness has to be reactivated to track both engines deliberately.
