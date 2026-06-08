# Shell Yes evening session — stats, app icon, Aptabase live

**Written:** 2026-06-07 (late evening)
**By:** Claude (Opus 4.7, 1M)
**For:** the next Claude session
**Branch:** `theme-refinement` (still off `shell-yes-rebrand`, neither merged to main)
**HEAD:** `94d48fe` — same as the earlier handoff. **Everything in this doc is still uncommitted** on top of that commit.
**Predecessors:**
- [[2026-06-07-shell-yes-ux-pass-handoff]] (afternoon)
- [[2026-06-07-shell-yes-testflight-prep-handoff]] (early evening — first half of today's session)

## TL;DR

Built on top of the testflight-prep handoff. Two big things landed:

1. **Brand polish closeout** — "Shell Yes" wordmark in Optima Title Case (splash + chrome), sundown app icon dialed in with calmer rays, ghost "How to Play" button, sundown tagline copy, two new credit lines, winner-card sparkles tuned to actually attach to the winner's card, a working "Home" button in Settings that pops the nav stack and resets the game.
2. **Telemetry pipeline live, end-to-end** — self-hosted Aptabase running on the Fastronaut Internal Hetzner box, iOS app emits `game_ended` / `game_bank` / `game_bust` / `app_opened` / `app_closed` events, full ClickHouse schema verified, queryable. Local lifetime stats (Settings → Stats card) update in parallel.

Still no commit. Still no TestFlight (Apple Dev Program enrollment blocked on Belgian ID verification — Bram opened a support ticket; see the testflight-prep doc).

The Aptabase setup is shared infrastructure — see `Administration/Aptabase setup.md` in Obsidian for the full runbook. Per-app analytics notes live at `Projects/Shell Yes/Analytics.md`.

## What shipped this session (still uncommitted)

### Wordmark — Optima Title Case

- **Splash** (`SplashView.swift`): `shell yes` (Avenir UltraLight, coral DemiBold "y" accent, 78pt) → **`Shell Yes`** (Optima Semibold 64pt, tracking 1, uniform `ink`, no accent letter).
- **In-game chrome** (`GameView.swift:ChromeBar`): same treatment at 22pt, tracking 0.5. Removed the `.textCase(.lowercase)` modifier since Title Case is the new identity.
- Why Title Case: Bram pushed back on lowercase reading too "diary-soft", asked to try caps. Title Case landed (not full ALL CAPS, which was discussed as a "two-line stamp" alternative).

### Splash polish

- **Tagline** copy: "A beachy soft think slow game." → **"A beachy soft slow thinky game."**
- **"How to Play"** button: filled card → **ghost button** (no background fill, stroke opacity 0.45 / width 1.5, text opacity 0.75).
- **Two new credit lines** (above the music attribution):
  - "Anti-doom-scrolling soft gaming by @ort." (11pt italic, `ink` opacity 0.6)
  - "UI sounds by [cadecomposer](https://github.com/cadecomposer)." (10pt italic, `ink` opacity 0.42 — matches music credit styling)

### App icon (final)

Dialed through several iterations. Final composition (`IconExporter.swift:AppIconView`):
- **Sundown gradient** — 5 stops top-to-bottom: `skyPlum` → `skyLavender` (22%) → `coralLight` (55%) → `coinGoldLight` (88%) → `coinGoldLight`. Reads purple-sky-to-orange-horizon.
- **Calm rays** — 12-spoke `AngularGradient`, opacity dropped to **0.22** with **`.softLight`** blend (the previous `.plusLighter` at 0.75 was "too heavy on the rays; calmth is the message"). Masked by a `RadialGradient` ring so they emerge from behind the shell and fade before the edge.
- **Soft golden bloom** behind the shell — `coinGoldLight` 0.55 → 0.25 → 0 out to 520pt.
- **Golden pearls** (icon-specific override on `ShellMedallion`) — highlight (255, 240, 190), core `coinGoldLight`, edge `gold`. In-game pearls untouched (still the muted pearlescent palette).

`IconExporter` is DEBUG-only and rewrites `Documents/AppIcon-1024.png` on first launch when missing. The exported PNG is then copied into the asset catalog. Re-render workflow: `rm` the file from the sim's Documents → relaunch → `cp` from container.

### Winner-card sparkles

User reported sparkles weren't attaching to the winner card. Root cause: previous `spread: 90 / 130` flung sparkles into the vertically-neighbouring cards. Tuned to stay close to the winner (`CountingCeremony.swift:147`):
- `EdgeSparkleField`: count 90 → **110**, spread **38**, duration 1.6
- `SparkleField` (radial inner burst): count 28 → **36**, spread 60, startRadius 14

### Settings — Stats section

New section between **play** and **appearance**. 8 stats, all backed by `UserDefaults` via the new `StatsStore.swift`:

| Stat | Display | Hook |
|------|---------|------|
| Games played | `n` | `recordGameOver` |
| Wins | `n · X%` (or `n`) | `recordGameOver` |
| Win streak | `n` or `n · best Y` | `recordGameOver` |
| Best score | `n` or `—` | `recordGameOver` |
| Biggest keep | `n` or `—` | `recordBank` |
| Steals | `n` | `recordBank` (when stoleATile) |
| Busts | `n` | `recordBust` |
| Hot face | `$` for coin / digit for numeric / `—` | `recordPicks` |

Layout: new `StatRow` view (label left, value right in demiBold + monospacedDigit) inside the same `glassCard` + `SettingsSection` shells as the other categories.

`StatsStore` is `@Observable @MainActor`, persists each field via `didSet`. `hotFace` is computed from `[Int: Int]` face-counts.

### Settings — Home button & nav refactor

User asked for a "Home" row in the **other** section that returns to splash and resets any in-progress game. Implementation needed a real navigation refactor:

- **Root cause of the "button doesn't do anything" bug:** the original `NavigationLink { Destination() } label: {…}` form doesn't update the bound `path` — it pushes destination views directly. So `path = NavigationPath()` from inside Settings cleared nothing.
- **Refactor:** value-based navigation throughout.
  - New `Route: Hashable` enum (`.game`, `.settings`).
  - `NavigationStack(path: $path)` in `ShellYesApp` has a single `.navigationDestination(for: Route.self)` that builds GameView (with the existing onAppear/onDisappear hooks) or SettingsView.
  - SplashView's New Game and Settings links → `NavigationLink(value: Route.game/.settings)`.
  - ChromeBar's gear → `NavigationLink(value: Route.settings)`. Its old `onNewGame` param was removed since the destination builder constructs SettingsView with the right closure.
- **`goHome` action injected via SwiftUI environment** (`EnvironmentKey + GoHomeAction` wrapper in `ShellYesApp.swift`). SettingsView reads it via `@Environment(\.goHome)` and calls `goHome()` from the new Home row. The closure body is `store.newGame(); path = NavigationPath()`.

### Telemetry pipeline (the big one)

End-to-end live as of ~22:50 local. The full setup runbook is in **Obsidian: `Administration/Aptabase setup.md`** (it was rewritten this session to reflect actual observed behavior — old version pointed at the SofaPlanner box, which Bram explicitly flagged as off-limits). Per-app notes at **`Projects/Shell Yes/Analytics.md`**.

**Server side:**
- **Host:** Hetzner `204.168.223.69` ("Fastronaut Internal", Ubuntu 24.04, 4GB/40GB). NOT the SofaPlanner box (`95.217.223.152`) or Networkx (`185.58.97.231`) — both are off-limits per Bram and now recorded in memory.
- **Stack:** Aptabase self-hosted via Docker Compose at `/opt/aptabase`. Three containers: `aptabase_app` (the .NET API + admin UI, bound to **`127.0.0.1:8000`** only), `aptabase_db` (Postgres 15-alpine), `aptabase_events_db` (ClickHouse 23.8.4.69-alpine).
- **Docker** had to be installed (the box was a static-only Caddy server before). Used the official Docker apt repo, no friction.
- **Caddy** — added a new block at the bottom of `/etc/caddy/Caddyfile` (single-file convention, no `conf.d`). Backup file at `/etc/caddy/Caddyfile.bak.20260607-203339`. Reverse-proxies `aptabase.fastronaut.com → 127.0.0.1:8000`.
- **TLS** — Let's Encrypt cert auto-issued on first request (`CN=aptabase.fastronaut.com`, expires Sep 5).
- **DNS** — `aptabase.fastronaut.com A → 204.168.223.69`. (First attempt pointed at `.152` because I'd recommended the SofaPlanner box; corrected once Bram flagged the no-go.)

**Compose file note:** the current Aptabase self-hosting repo has **no `.env.example`** — all config (BASE_URL, AUTH_SECRET, two passwords, port binding) lives inline in `docker-compose.yml`. The runbook documents this. Secrets are in the live compose file on the server; original upstream copy at `/opt/aptabase/docker-compose.yml.original` for reference.

**ClickHouse schema (observed, not what Aptabase docs suggest):**
- Database: **`default`** (NOT `aptabase` — a common gotcha; my first backup template had it wrong)
- Table: `default.events`
- String props (JSON) and numeric props (JSON) are split across `string_props` / `numeric_props` columns. Extract with `JSONExtractString` / `JSONExtractInt`. Full column list + sample queries in `Projects/Shell Yes/Analytics.md`.

**iOS side:**
- **SPM package** added: `https://github.com/aptabase/aptabase-swift`, Up to Next Major, target ShellYes. Bram did this through Xcode's GUI.
- **`Telemetry.swift`** — thin wrapper. `Telemetry.shared.track(...)` is the only call site convention. Gated with `#if canImport(Aptabase)` so the code builds even if the SPM dep is later removed.
- **`ShellYesApp.init`** — `Telemetry.shared.initialize(appKey: "A-SH-7882093279")`. App key is a public identifier (analogous to a Stripe publishable key); safe in source.
- **Events wired (in `GameView.act` and `.onChange(of: store.isOver)`):**
  - `game_bank` — every successful claim. Props: `tile_value` (Int), `stole_from_rival` (Bool).
  - `game_bust` — every human bust. Props: `reason` (`rolled` / `greedy` / `stranded`), `lost_tile`, `burned_tile`.
  - `game_ended` — fires once on the false→true transition of `store.isOver`, guarded by `gameEndedReported` flag. Props: `won`, `my_score`, `opponent_count`, `busts`, `steals`, `biggest_keep`, `duration_seconds`, `difficulty`, `pace`. Per-game counters live in `GameView` (`@State`), reset on `startNewGame()`.
- **Lifecycle events** (in `ShellYesApp` via `@Environment(\.scenePhase)`):
  - `app_opened` on `.active`, `app_closed` on `.background`. **2-second debounce** on `.active` because simulator (and some real-device transitions) can bounce `.active → .inactive → .active` and produce duplicate opens + 0-duration closes. Same-session bounces are now ignored.

### Memory recorded

`SofaPlanner servers off-limits` — `/Users/bramvanoost/.claude/projects/-Users-bramvanoost-Code-game-shell-yes/memory/sofaplanner-servers-off-limits.md`. Indexed in `MEMORY.md`. Rule: never deploy Fastronaut-internal services to `95.217.223.152` (SofaPlanner CMS/Preview) or `185.58.97.231` (SofaPlanner production via Networkx). Also avoid `95.217.232.252` (Nexxteq client). Default to **`204.168.223.69`** ("Fastronaut Internal") for any shared infra.

## What did NOT happen

- **No commit.** ~13 modified files + ~7 new files. See `git status` below. Bram has not asked to commit, and given the multi-concern spread (brand, nav refactor, stats, telemetry, app icon, docs) a single commit would be a mess. Suggest splitting by concern when ready.
- **No TestFlight upload.** Belgian eID enrollment blocker is unresolved. App icon, encryption flag, signing — all in place.
- **No SMTP on Aptabase.** Activation links go to container logs. Fine for single-user; the runbook documents adding SMTP later via inline compose env vars.
- **No nightly backup cron yet.** Runbook has a script template (`/opt/aptabase/backup.sh` pattern dumps Postgres + ClickHouse, rotates 14 days), but it's not deployed.
- **`didBank` unused warning** in `GameView.swift:117` still present. Leftover; harmless; safe to delete.

## Open threads / pending tasks

1. **Apple Developer Program enrollment** — still blocked. Suggested workarounds in previous handoff: Belgian eID card, passport, or Fastronaut Organization enrollment via D-U-N-S.
2. **Privacy policy URL** for App Store Connect. Aptabase is App-Store-safe (no PII, no IDFA, no ATT) but you need a 1-page policy that mentions: "We collect anonymous app usage stats (game outcomes, settings, app version, foreground duration) to improve the game. Data is stored on our own server in Germany and is never shared with third parties." Hosted anywhere (Notion public page, fastronaut.com).
3. **App Privacy nutrition label answers** — Usage Data → Diagnostics → Not Linked to User → Not Used for Tracking. Don't add an ATT prompt.
4. **Aptabase Aptabase backups** — copy/paste the script from the runbook (`Administration/Aptabase setup.md`) into `/opt/aptabase/backup.sh`, verify the volume paths, add a root crontab entry. Or wire it into Dropbox like SofaPlanner's nightly job does.
5. **Aptabase SMTP** — add when there's a second human user.
6. **Tine's device** — earlier in the day she was paired over USB and symbols were copying. Probably done by now; we never circled back to actually install on her phone. Free-team builds expire after 7 days, so this is a stopgap until the dev account opens.
7. **Commit strategy** — when Bram is ready, suggest splitting:
   - `brand:` wordmark + tagline + credits + ghost button
   - `nav:` value-based routes + Home button + GoHome environment
   - `feat:` Settings Stats section + StatsStore
   - `feat:` Aptabase telemetry (Telemetry.swift, scenePhase events, GameView hooks, SPM package)
   - `icon:` IconExporter + sundown AppIconView + final PNG + tinted icon Contents.json
   - `fx:` Winner-card sparkle tuning
   - `theme:` Adaptive cardSurface / insetSurface for dark mode (from the earlier evening handoff but not yet committed)

## Where things live

**Code (in repo):**
- `ShellYes/Telemetry.swift` — analytics wrapper (`canImport` gated)
- `ShellYes/StatsStore.swift` — local lifetime stats, UserDefaults-backed
- `ShellYes/IconExporter.swift` — DEBUG-only icon renderer
- `ShellYes/ShellYesApp.swift` — Aptabase init, scenePhase hooks, `Route` enum, `goHome` environment, `NavigationPath` state
- `ShellYes/ShellGlyph.swift:ShellMedallion` — pearl colour overrides
- `ShellYes/DesignSystem.swift` — Pearl colour params, `cardSurface` / `insetSurface` adaptive tokens, `StampButtonStyle` invite tuning
- `ShellYes/SettingsView.swift` — Stats section, Home row, environment goHome, `StatRow` view, `import ShellYesEngine`
- `ShellYes/GameView.swift` — per-game counters, telemetry hooks in `act()`, `.onChange(of: isOver)` for `game_ended`
- `ShellYes/SplashView.swift` — Optima wordmark, ghost button, new credits, `IconExporter` debug hook
- `ShellYes/CountingCeremony.swift:147` — winner sparkle config

**Code (added via SPM, not in repo):**
- `aptabase-swift` (Aptabase.framework reference in `project.pbxproj`)

**Docs (in Obsidian):**
- `Administration/Aptabase setup.md` — full server runbook (Docker install, compose config, Caddy block, ClickHouse schema, backup template, onboarding future apps)
- `Projects/Shell Yes/Analytics.md` — events + props table, privacy posture, ClickHouse query examples, "where it lives in the codebase"

**Docs (in repo):**
- `docs/superpowers/2026-06-07-shell-yes-ux-pass-handoff.md` (afternoon)
- `docs/superpowers/2026-06-07-shell-yes-testflight-prep-handoff.md` (early evening)
- `docs/superpowers/2026-06-07-shell-yes-evening-aptabase-handoff.md` (this file)

**Memory:**
- `MEMORY.md` (index) includes the new `sofaplanner-servers-off-limits` entry
- `sofaplanner-servers-off-limits.md` — full rule and rationale

## Bram preferences reinforced this session

- **"Calmth is the message"** — applies to icon, splash, the whole tone. Rays got dialled from 0.75 to 0.22 opacity after a single nudge. Default toward less, not more.
- **No SofaPlanner servers, ever.** Strict no-go zone. Use `204.168.223.69` for Fastronaut-internal shared infra.
- **Don't break what's running.** Before touching the Hetzner box this session, Bram explicitly said "check what already exists". The runbook now opens with a survey step.
- **Optima fits the brand.** The accent-letter (coral Y) wordmark idea is dead. Title Case landed.
- **Stats want to tell tiny stories** — going from 8 selected stats (4 core + 4 flavor) confirms the "story-not-spreadsheet" mental model. New stats added later should follow that ethos.
- He'll be away briefly tomorrow. No urgency on commit until he's back at the keyboard.
