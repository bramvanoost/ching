# CHING iOS, session handoff at end of Phase 1

**Written:** 2026-06-05
**By:** Claude (Opus 4.7)
**For:** the next Claude session that opens this repo

## TL;DR for the next session

Phase 1 is merged to main. The Swift engine + AI work, parity-verified against the TS engine, but **nothing is on screen yet**. Bram explicitly said "I thought we'd have something playable by now," so **Phase 2 is now: get a tappable, ugly-but-functional game running on the iOS simulator**. Visual polish, additional screens, and the 1-bit dither aesthetic are deferred until after playable.

Before you do anything, read this doc end to end. Then ask Bram what to start with (he may want to re-discuss Phase 2 scope, or just say "go").

## Project context (one paragraph)

CHING is a push-your-luck dice game (Heckmeck-inspired, original theme). The TypeScript terminal version (`src/`) is the v0 reference implementation: pure engine, ANSI renderer, working AI, SSH/TCP multiplayer daemon. The iOS app is being built as a portfolio piece (App Store launch, no commercial pressure). The design direction is 1-bit + dithered (Obra Dinn / printed-banknote energy), with two-font system, asymmetric ledger composition, no tilting. The chosen tech stack is pure native Swift / SwiftUI, with the TS engine ported (not bridged) and parity-tested. Game Center and multiplayer are explicitly out of v1.

## Locked decisions from brainstorming

See `docs/superpowers/specs/2026-06-05-ching-ios-design.md` for the full spec. Headlines:

- **Scope of v1**: solo vs 1-3 AI opponents on a single device. **No multiplayer, no Game Center, no Stats screen, no iPad, no localization, no IAP, no ads.** Optional tip jar only.
- **Screens (six total)**: Splash, Home (PLAY + CONTINUE + Settings), Game, Receipt, Settings, Onboarding. Onboarding is interactive (embedded in a real game), replayable from Settings. No separate "How to play" text screen.
- **Setup screen is deliberately cut.** PLAY uses last-used config. Changing opponents happens at the Receipt via "Change opponents" mini-sheet. Default is 1v2 (Jones + Bot 03) on Normal.
- **AI cast**: three named characters with discipline values. Jones (red, ~0.30, greedy), Merit (blue, ~0.55, balanced), Bot 03 (yellow, ~0.85, cold). Easy/Normal/Hard shifts all by ±0.15.
- **End condition**: center tiles depleted (same as TS engine; do NOT introduce a points-target or round-limit).
- **Visual direction (deferred to design-pass phase, but locked in principle)**: 1-bit + dither, display serif + system mono, asymmetric ledger layout, watermark lattice, stamp-style action buttons, **no tilting / no rotation**, no skeuomorphism, no gradients, no soft shadows.
- **Tech stack**: native Swift + SwiftUI, iOS 17+, iPhone only, portrait only. Hand-ported engine (not JSCore). Terminal version freezes as v0 and may drift.
- **Pricing**: free, no IAP, no ads, optional tip jar.

## What Phase 1 shipped (already merged to main)

Commit `ddbb398` on main. Files added (all new, nothing in existing terminal code touched):

- **Swift Package** at `ios/CHINGEngine/`. Pure, zero platform dependencies in engine sources. Three library files (Engine, AI, Types, Rng) plus one CLI executable target.
- **32 XCTest tests** covering ROLL/PICK/STOP/bust/steal/end-of-game/AI pick/AI continueOrStop/integration/200-game sim regression. All pass.
- **Cross-engine parity harness** at `parity/`: a Node runner of the TS engine, a Swift CLI runner (`ching-parity`), shared `cases.json`, and a `diff.mjs` that asserts byte-equivalent state traces. 4 cases pass including a 166-action full-game trace.
- **GitHub Actions CI** at `.github/workflows/engine-ci.yml`. Runs on macos-14, executes Swift tests, TS tests, parity diff, and TS sim regression on PRs touching engine/parity paths. Validated on PR #1.

To re-verify locally:

```bash
cd /Users/bramvanoost/Code/game-ching/ios/CHINGEngine && swift test
# expect: Executed 32 tests, with 0 failures

cd /Users/bramvanoost/Code/game-ching && node parity/diff.mjs
# expect: 4/4 parity cases passed

cd /Users/bramvanoost/Code/game-ching && npm run sim
# expect: OK: higher discipline beats lower discipline
```

## Dev environment (already set up, don't re-check)

- macOS Sequoia (Darwin 25.5+)
- **Xcode installed** at `/Applications/Xcode.app`. Bram installed this mid-Phase-1 after we discovered CLT alone wasn't enough.
- `xcode-select -p` should return `/Applications/Xcode.app/Contents/Developer`.
- Swift bundled with Xcode (5.10+).
- Node 22+ via system. `tsx` is a devDependency in `package.json` for running the TS engine.

If `swift test` fails with "no such module 'XCTest'", the active developer dir got reset. Run:
```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Important mid-Phase-1 deviations (not blockers, just context)

1. **XCTest, not Swift Testing.** The original plan called for Swift Testing (`import Testing`, `@Test`, `#expect`). On Bram's machine, that framework needed Xcode infrastructure that wasn't present pre-Xcode-install. The cleaner solve was to use XCTest, which works ubiquitously. **The spec at `docs/superpowers/specs/2026-06-05-ching-ios-design.md` still says Swift Testing in places — that wording is stale; XCTest is canonical.** Don't switch back.
2. **`import Foundation` removed from 3 of 4 engine sources** during cleanup. Only `AI.swift` keeps it (uses `pow`). Engine + Types + Rng are stdlib-only.
3. **Tip jar amount, character final names, display serif family, exact onboarding flow** are all explicitly deferred from the design doc to build-phase. The placeholders (Jones/Merit/Bot 03, Cochin/Hoefler/Bodoni candidates, ~$2.99 tip) are not final.
4. The repo `bramvanoost/ching` is **public** on GitHub. Bram is fine with that for now; no action needed.

## Phase 2: revised framing — get something playable

**Original plan from the design doc had 7 phases:** engine → SwiftUI scaffolding → game loop → visual system → onboarding → sound/haptics → polish. After Phase 1 shipped, Bram's signal was: "I thought we'd have something playable by now." Original Phase 2 (scaffolding all 6 screens with no logic) would have continued the invisible-work pattern. So:

### Phase 2 v2 — Minimum Playable

**Goal:** open Xcode, hit run on a simulator, see a single screen with all game elements (dice, tiles, vaults, roll/bank/pick buttons), play a complete game vs one AI bot from start to game-over. No styling beyond SwiftUI defaults. Ugly is fine. Tappable is the bar.

**Out of scope for Phase 2 v2** (push to Phase 3+):
- 1-bit dither visual system
- Display serif typography
- All non-Game screens (Splash, Home, Receipt, Settings, Onboarding)
- Multiple AI characters / character selection
- Settings persistence (sound, haptics, etc.)
- App icon, splash, App Store screenshots
- Sound or haptics

**In scope for Phase 2 v2:**
- Xcode iOS app project at `ios/CHING/` (target name: `CHING`), depending on the `CHINGEngine` Swift Package
- `GameView.swift` — the only screen
- `GameStore.swift` — `@Observable` view model wrapping `State`, drives the engine via `step`, surfaces actions to the view
- Hardcoded 1v1 vs Jones at Normal difficulty (no setup)
- All six game zones rendered as plain SwiftUI: vault row, dice row, center tile row, pick buttons (1-5, coin), Roll button, Bank button
- The AI takes its turns automatically when control rotates to it
- End-of-game shows a simple alert ("You won / You lost / Tie") with a "New Game" button that reinitializes
- Run on iOS simulator, play a complete game, screenshot or screen-record proof of life

That's it. Should be one focused plan with ~10-15 TDD-style tasks, achievable in a single session.

## How the next session should start

1. Read `/Users/bramvanoost/.claude/projects/-Users-bramvanoost-Code-game-ching/memory/MEMORY.md` (auto-loaded) and the linked memory files.
2. Read this handoff doc.
3. Greet Bram briefly: "Phase 1 is merged. Ready to start Phase 2 (minimum playable iOS app), or want to revisit scope first?"
4. If "go": invoke `superpowers:writing-plans` to create the Phase 2 plan along the lines outlined above.
5. If he wants to revisit scope: invoke `superpowers:brainstorming` for a focused mini-brainstorm on Phase 2 only.

## Pointers

- **Design spec** (locked): `docs/superpowers/specs/2026-06-05-ching-ios-design.md`
- **Phase 1 plan** (executed): `docs/superpowers/plans/2026-06-05-phase-1-engine-port.md`
- **CLAUDE.md** (project rules, edited mid-Phase-1 — no, it wasn't, original wording stands)
- **Engine code**: `ios/CHINGEngine/Sources/CHINGEngine/`
- **Parity harness**: `parity/`
- **TS engine reference**: `src/engine.ts`, `src/ai.ts`
- **TS terminal version**: `src/cli.ts`, `src/render.ts` (frozen, may drift)

## Working preferences Bram has signaled

- Terse responses. Don't summarize at the end of every reply.
- No em-dashes (CLAUDE.md global rule). Commas, periods, or restructure instead.
- Visible momentum over invisible rigor (see [[playable-over-rigor]] memory).
- Verify dev environment before locking a plan (see [[dev-environment-verification]] memory).
- He'll typically accept your recommendation. When recommending an option, lead with the recommended one and explain briefly.
- He'll skim long docs. Don't ask "did you read the spec." Assume he didn't, summarize the relevant parts when needed.
