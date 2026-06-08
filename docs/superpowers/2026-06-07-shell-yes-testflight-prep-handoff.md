# Shell Yes evening session — TestFlight prep + brand polish handoff

**Written:** 2026-06-07 (evening)
**By:** Claude (Opus 4.7, 1M)
**For:** the next Claude session
**Branch:** `theme-refinement` (off `shell-yes-rebrand`, also not yet merged to main)
**HEAD:** `94d48fe` (last committed point; everything in this handoff is **uncommitted** on top of that)

## TL;DR

This session sat on top of the earlier UX pass and turned the corner toward **getting the app onto TestFlight**. Two threads:

1. **Brand and feel polish** — shell medallion redesign with golden pearls + soft shading, splash wordmark dropped its coral accent, the New Game / Roll On invite animation is stronger and tighter, Keep is now instant (no 800ms hold), settings card is readable in dark mode.
2. **Distribution prep** — full app icon pipeline (`IconExporter`), 1024×1024 sunset icon, `ITSAppUsesNonExemptEncryption = NO` for export compliance.

**Open blocker:** Bram can't sign up for the Apple Developer Program. Apple's verification flow refuses his Belgian paper driver's license and gives no other UI option. He's opened a support ticket. **Until that's resolved there's no TestFlight.** Tine's phone is paired over USB for free-team sideload as a stopgap (symbols were copying when the session paused).

Nothing was committed this session — `git status` shows ~13 modified files + 4 new files. Ask Bram before committing; the work spans multiple concerns and he may want them split.

## What shipped (uncommitted)

### Brand / medallion

- **`shell-icon.svg` replaced** with a user-provided integrated SVG that bundles the scallop silhouette, lobe-divider cutouts, and three pearl cutouts as one path. The old separate `ShellSilhouette.imageset` is still in the project but no longer used by the medallion.
- **`ShellMedallion`** simplified and re-layered (`ShellGlyph.swift`):
  - 3 `Pearl`s behind the shell at the SVG cutout positions (centers normalized: x = 0.372 / 0.500 / 0.627, y = 0.698; diameter 0.105·size, oversized so the icon rim hides sub-pixel edges).
  - The template-tinted shell on top with two overlay layers masked to the icon shape: a vertical sheen (white at the very top, treasureInk at the bottom 8%) and a `.plusLighter` radial highlight in the upper-left quadrant for specular pop.
  - Drop shadow underneath.
- **`Pearl`** gained four optional color params (`highlight`, `core`, `edge`, `glow`) so the icon can use a brighter saturated gold without affecting the in-game pearls.

### Splash + wordmark

- **`shell yes` wordmark** swapped from Avenir UltraLight with a coral DemiBold `y` to **Optima semibold at 64pt, tracking 1, uniform `ink`**. No accent letter. Reads as one calm wordmark.
- **Splash logo medallion** unchanged structurally (still `ShellMedallion(size: 124)` with a soft gold halo). The Optima wordmark sits directly below.

### Action button animation

- **`StampButtonStyle` invite animation** tuned stronger + faster + immediate:
  - Halo opacity range 0.15–0.7 → **0.22–0.88**, radius 24 → **28**
  - Halo pulse 1.4s → **1.1s**, shine sweep 2.6s → **2.0s**
  - Peak hold 2.7s → **1.8s**, trough hold 1.4s → **0.8s**
  - Cycle ~5.5s → **~3.7s** (~33% faster, qualifies as "lightly more frequent")
- **New parameter `inviteHalo: Bool = true`** so the halo can be suppressed independently of the shine.
- **Roll On (in-game)** now uses `invite: canRoll, inviteHalo: false`. The shine is on whenever the engine is waiting for the player to roll (fresh turn OR between picks) and off during rolling/picking. No halo at all on Roll On.
- **New Game / Play Again** still use the default `inviteHalo: true` (full breathing halo + shine).
- The `isTurnFresh` prop on `ActionBar` was added then removed in the same session — current signal is `canRoll`, which is precisely "phase is `.roll`, dice in hand, human's turn."

### Keep button → instant feedback

- `DiceStage`'s Keep tap used to hold for **800ms** while a sparkle field played around the still-visible Keep card, then call `onBank()`. Removed the hold per request — `onBank()` now fires synchronously on tap so `playBank()` SFX and `presentTurnEvent(.took/.stole)` land on the same frame. Sparkles still trigger; they play in parallel as the AI event modal takes over the dice area. The `bankPending` flag was removed (now unused).

### Settings — dark-mode readability

The settings card was unreadable in dark mode: `Color.ink` adapts to cream in dark mode, but the card itself was `Color.white.opacity(0.7)` which produces a pale lavender over the dark purple sky → cream-on-cream. Fixed with two new adaptive surface tokens in `DesignSystem.swift`:

- **`cardSurface`** — light mode: white opacity 0.7 (unchanged). Dark mode: deep plum **(32, 22, 44) opacity 0.78**. Used by the main settings section card.
- **`insetSurface`** — light mode: white opacity 0.4 (unchanged). Dark mode: slightly lighter plum **(58, 42, 76) opacity 0.78**. Used by `StampSegmented` and the `StampToggle` track.

Light mode is byte-identical. Dark mode gets a real dark surface so cream ink labels (Difficulty, Pace, New game, Color mode, etc.) read with proper contrast.

- **Credits line** on settings (`v0.5 · shell yes by fastronaut`) bumped 10pt → **13pt**, `dimInk` opacity 0.7 → `ink` opacity 0.65, tracking 1.5 → 1. Reads as text rather than a watermark.

### App icon pipeline (new)

- **`IconExporter.swift`** — new file. `AppIconView` is a 1024×1024 composition; `IconExporter.exportIfNeeded()` renders it via `ImageRenderer`, redraws into an RGB-only `CGBitmapContext` (`.noneSkipLast`), and writes via `ImageIO` so the encoded PNG has **no alpha channel** (Apple rejects icons with alpha, even all-opaque alpha).
- **Hook**: `SplashView.task` calls it under `#if DEBUG`, idempotent (skips if file exists in Documents). Manual workflow: delete the PNG from the sim's Documents → relaunch → exporter writes the new PNG → `cp` it into the asset catalog → rebuild → reinstall.
- **Asset catalog**: `AppIcon-1024.png` (1024×1024, hasAlpha: no, verified). `Contents.json` wires the same PNG into all three slots (universal / dark / tinted).
- **Current `AppIconView` composition** (after several iterations Bram dialed):
  - **Sundown gradient** (top → bottom): `skyPlum` → `skyLavender` (22%) → `coralLight` (55%) → `coinGoldLight` (88%) → `coinGoldLight`. Reads as a dusky purple sky settling into a warm gold horizon.
  - **Sun rays** — 24-stop `AngularGradient` (12 bright at `coinGoldLight` opacity **0.22**, 12 clear), rotated 7.5° so no ray points straight down through the medallion axis. Blend mode `.softLight` (toned down from `.plusLighter` after Bram said "calmth is the message"). Masked by a `RadialGradient` ring: clear at center (inside shell), peak black 0.50 at 35%, fading to clear at 95% — rays emerge from behind the shell and dissipate before the icon edge.
  - **Solar bloom** — radial `coinGoldLight` glow at **0.55 → 0.25 → 0.0** out to 520pt. Lifts the medallion without becoming the focal point.
  - **Shell medallion** at 720pt with **icon-only brighter pearls**: highlight (255, 240, 190), core `coinGoldLight`, edge `gold`, glow `coinGoldLight`. In-game pearls unchanged.

### TestFlight prep

- **`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`** added to both Debug and Release configs in `project.pbxproj`. App Store Connect will no longer prompt for export-compliance per upload.
- App icon now exists and is alpha-stripped (was the previous blocker).
- `DEVELOPMENT_TEAM = 86QYU585DZ` is already set (Bram's personal team).
- `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` — fine for a first archive.

## What did NOT happen

- **No commit.** Everything above is uncommitted. Bram may want to split: `icon:` and `theme:` and `ux:` are separate concerns.
- **No App Store Connect record created.** Bram doesn't have a paid developer account yet (Belgian ID verification blocker).
- **No Archive built.** Wait until the developer account is sorted.
- **Tine's phone setup is incomplete.** USB-paired, Developer Mode enabled, but Xcode is still "Copying shared cache symbols from iTine" at 2% when Bram switched contexts. This is normal first-pair behavior (15–45 min). Once symbols finish: Run with her phone as destination, accept dev profile on her phone (Settings → General → VPN & Device Management → Trust). Free-team builds expire after **7 days** so this is a temporary stopgap.

## Open threads / pending tasks

1. **Apple Developer Program enrollment** — blocked on ID verification. Bram opened a ticket. Workarounds suggested: try Belgian eID card (not driver's license), try passport, or enroll as an organization via Fastronaut with a D-U-N-S number. Once unblocked: create App Store Connect record for `com.fastronaut.ShellYes`, then archive.
2. **Tine's phone install** — waiting on symbol copy. Next action when she's around: change run destination in Xcode to her phone, hit ⌘R, walk her through the one-time profile trust step.
3. **Icon iteration** — Bram approved the current sundown look but it's worth checking on her physical phone vs the simulator render (colors can shift). Pearls were just made brighter (255, 240, 190) highlight, `gold` edge); if they read too brassy on-device, dial the edge back toward `pearlEdge`.
4. **Unused warning** — `var didBank = false` in `GameView.swift:105` is written but never read. Leftover from the bust-detection refactor. Safe to delete.

## Useful spots if you need them

- Icon composition: `ShellYes/IconExporter.swift:AppIconView`
- Shell medallion: `ShellYes/ShellGlyph.swift:ShellMedallion`
- Pearl with overridable colors: `ShellYes/DesignSystem.swift:Pearl`
- Adaptive surfaces: `ShellYes/DesignSystem.swift` (`cardSurface`, `insetSurface`)
- Invite animation timings: `ShellYes/DesignSystem.swift:StampButtonStyle`
- Roll On wiring: `ShellYes/GameView.swift:600` (`.stampButton(invite: canRoll, inviteHalo: false)`)
- Keep instant fire: `ShellYes/DiceStage.swift:59` (button action)
- Export-compliance flag: `ShellYes/ShellYes.xcodeproj/project.pbxproj` (both Debug + Release)
- Icon asset: `ShellYes/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (1024×1024, no alpha)

## Things Bram has said that should bias future decisions

- "Calmth is the message" — don't go heavy on effects on the icon. Soft, slow, beachy.
- Optima fits the brand. The previous coral-Y accent in the wordmark read as an error mid-word.
- He prefers tappable, immediate feedback over staged celebrations (Keep → instant sound + modal, not a held animation).
- In dark mode, the app should still feel like the same beachy world, just dusk. Adaptive surfaces, not flat dark theme.
- He's in a hurry tonight. Tight responses, no recapping.
