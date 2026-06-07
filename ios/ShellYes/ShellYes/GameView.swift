import SwiftUI
import ShellYesEngine

struct GameView: View {
    let store: GameStore
    let settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var iosReduceMotion
    @SwiftUI.State private var bustFlash: Bool = false
    @SwiftUI.State private var bustReason: BustReason = .rolled
    @SwiftUI.State private var burnedTile: Int? = nil
    @SwiftUI.State private var stolenFromIdx: Int? = nil
    @SwiftUI.State private var bustProgress: CGFloat = 1.0
    @SwiftUI.State private var bustGeneration: Int = 0
    /// Fake roll values used to fill the dice slot for ~1s after a roll
    /// that produced a bust. Without this the bust banner punches in
    /// instantly — the engine clears `state.rolled` when the turn ends,
    /// so there's nothing for DiceStage to animate. Overriding the
    /// `rolled` prop with these values lets the player at least feel
    /// the dice land before "Oh, shell no" arrives.
    @SwiftUI.State private var bustAnimatedRoll: [Face]? = nil
    private let bustHoldSeconds: Double = 8.0
    /// How long the fake post-bust roll stays on screen before the
    /// flash takes over. Matches the dice animation duration roughly.
    private let rollBustVisualDelayNs: UInt64 = 1_000_000_000

    enum BustReason {
        case greedy   // tried to bank without a coin
        case rolled   // roll produced no new pickable face
        case stranded // picked the last die without a pearl: no dice left, no bank possible
    }
    @SwiftUI.State private var revealChrome: Bool = false
    @SwiftUI.State private var revealScoreboard: Bool = false
    @SwiftUI.State private var revealShells: Bool = false
    @SwiftUI.State private var revealStage: Bool = false
    @SwiftUI.State private var revealAction: Bool = false

    private func act(_ action: Action) {
        let humanSeat = GameStore.humanSeat
        let wasHumanTurn = store.isHumanTurn
        let beforeVault = store.state.players[humanSeat].tiles.count
        let hadCoinBefore = store.state.setAside.contains(.coin)
        // Snapshot the pool the bust logic will burn from: current center +
        // the player's top tile (which returns to center on bust).
        let beforeCenter = store.state.centerTiles
        let beforeTopVaultTile = store.state.players[humanSeat].tiles.last
        // Snapshot every player's stack so we can detect whose tile the
        // human claimed (steal vs centre take) after apply.
        let beforeTileCounts = store.state.players.map { $0.tiles.count }
        let beforePlayerIds = store.state.players.map { $0.id }
        // Snapshot for the post-roll-bust fake dice display.
        let beforePickedFaces = store.state.pickedFaces
        let beforeDiceInHand = store.state.diceInHand

        store.apply(action)

        // Forced bust: after a pick the player has 0 dice left in hand AND
        // no pearl in set-aside. No valid move that isn't a bust, so the
        // engine takes the .stop for them. Reason is tagged .stranded so
        // the bust banner explains they were boxed in, not greedy.
        var forcedStop = false
        if wasHumanTurn && store.isHumanTurn && !store.isOver
            && store.state.diceInHand == 0
            && !store.state.setAside.isEmpty
            && !store.state.setAside.contains(.coin) {
            store.apply(.stop)
            forcedStop = true
        }

        // Detect end-of-turn outcomes for the human player — bust gets a flash;
        // bank/steal celebration is handled per-column (sparkles + steal pulse).
        var didBank = false
        var didBust = false
        if wasHumanTurn && !store.isHumanTurn && !store.isOver {
            let afterVault = store.state.players[humanSeat].tiles.count
            if afterVault <= beforeVault {
                if forcedStop {
                    bustReason = .stranded
                } else if case .stop = action, !hadCoinBefore {
                    bustReason = .greedy
                } else {
                    bustReason = .rolled
                }
                // The burned tile is the highest in (centerTiles + returned top).
                var pool = beforeCenter
                if let returned = beforeTopVaultTile, afterVault < beforeVault {
                    pool.append(returned)
                }
                burnedTile = pool.max()
                didBust = true
                // For "you rolled and the dice gave you nothing" busts,
                // fake a one-second dice roll so the player sees the
                // doomed faces land before the flash. Other bust reasons
                // (greedy stop, stranded post-pick) skip straight to flash.
                if case .roll = action, !forcedStop, !beforePickedFaces.isEmpty {
                    bustAnimatedRoll = (0..<beforeDiceInHand).map { _ in
                        beforePickedFaces.randomElement()!
                    }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: rollBustVisualDelayNs)
                        triggerBustFlash()
                        bustAnimatedRoll = nil
                    }
                } else {
                    triggerBustFlash()
                }
            } else {
                // Vault grew — successful bank or steal.
                GameSFX.shared.playBank()
                didBank = true
                // Present a turn-note banner for the human's claim. Detect
                // steal by checking if another seat lost a tile this apply.
                if let claimed = store.state.players[humanSeat].tiles.last {
                    var victim: String? = nil
                    for i in beforeTileCounts.indices where i != humanSeat {
                        if store.state.players[i].tiles.count < beforeTileCounts[i] {
                            victim = beforePlayerIds[i].capitalized
                            break
                        }
                    }
                    if let victim {
                        store.presentTurnEvent(.stole(actor: "You", victim: victim, shell: claimed))
                    } else {
                        store.presentTurnEvent(.took(actor: "You", shell: claimed))
                    }
                }
            }
        }

        let reduce = settings.reducedMotion || iosReduceMotion
        Task { @MainActor in
            // After a human bust, the AI loop must wait until the Oh-shell-no
            // banner is dismissed (tap or timer). Otherwise AI turns play out
            // underneath and their event banners stack on top of the bust.
            if didBust {
                // Hold the AI loop while the fake roll plays AND while
                // the flash is up. Combined into one poll so a brief
                // race between "fake roll clears" and "flash appears"
                // doesn't let the loop slip through.
                while bustAnimatedRoll != nil || bustFlash {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
            }
            // Same gate for the human's claim banner — wait until the
            // "Nice, you claimed shell N!" note is tapped away before any
            // AI seat picks up the dice.
            while store.aiEvent != nil {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            await store.runAIIfNeeded(reduceMotion: reduce)
        }
    }

    /// Reset every transient UI flag, then ask the store for a fresh
    /// game. Without this, a pending bust flash or turn-note banner
    /// from the previous game leaks into the new one (the symptom: tap
    /// "New Game" from the tie screen and land on a live board with a
    /// stale modal still open).
    private func startNewGame() {
        bustFlash = false
        bustAnimatedRoll = nil
        burnedTile = nil
        stolenFromIdx = nil
        store.dismissAIEvent()
        store.newGame()
    }

    private func detectSteal(oldCounts: [Int], newCounts: [Int]) {
        guard oldCounts.count == newCounts.count else { return }
        for i in 0..<newCounts.count {
            if newCounts[i] < oldCounts[i] {
                let someoneGained = (0..<newCounts.count).contains { j in
                    j != i && newCounts[j] > oldCounts[j]
                }
                if someoneGained {
                    stolenFromIdx = i
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        if stolenFromIdx == i { stolenFromIdx = nil }
                    }
                }
                return
            }
        }
    }

    private func runIntroAnimation() async {
        let reduce = settings.reducedMotion || iosReduceMotion
        if reduce {
            revealChrome = true
            revealScoreboard = true
            revealShells = true
            revealStage = true
            revealAction = true
            return
        }
        withAnimation(.easeOut(duration: 0.35)) { revealChrome = true }
        try? await Task.sleep(nanoseconds: 150_000_000)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { revealScoreboard = true }
        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(.easeOut(duration: 0.45)) { revealShells = true }
        try? await Task.sleep(nanoseconds: 650_000_000)
        withAnimation(.easeOut(duration: 0.35)) { revealStage = true }
        try? await Task.sleep(nanoseconds: 180_000_000)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { revealAction = true }
    }

    private var bustSubline: String {
        switch bustReason {
        case .greedy: return "you had no pearl in hand."
        case .rolled: return "the dice gave you nothing."
        case .stranded: return "no dice left, no pearl in hand."
        }
    }

    @ViewBuilder
    private func burnedTileChip(value: Int) -> some View {
        let coins = GameStore.safeCoins(value)
        ZStack {
            ShellCardShape()
                .fill(
                    LinearGradient(
                        colors: [Color.safePeachLight, Color.safePeachDark],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    ShellCardShape()
                        .strokeBorder(Color.stampText.opacity(0.95), lineWidth: 2)
                )
                .shadow(color: Color.coralDark.opacity(0.6), radius: 0, x: 0, y: 5)
                .shadow(color: Color.coralDark.opacity(0.3), radius: 14, x: 0, y: 0)
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.avenir(28, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
                PearlRow(count: coins, diameter: 7, spacing: 3)
            }
        }
        .frame(width: 64, height: 80)
    }

    /// Large pearl rendered on the coral bust wash — the prize that almost
    /// was. Cream halo carries contrast, hard offset shadow gives stamp depth.
    @ViewBuilder
    private func bustPearl(size: CGFloat) -> some View {
        Pearl(diameter: size)
            .shadow(color: Color.stampText.opacity(0.55), radius: 24, x: 0, y: 0)
            .shadow(color: Color.coralDark, radius: 0, x: 0, y: 6)
    }

    private func triggerBustFlash() {
        GameSFX.shared.playBust()
        guard !settings.reducedMotion, !iosReduceMotion else { return }
        bustGeneration += 1
        let thisGeneration = bustGeneration
        withAnimation(.easeOut(duration: 0.25)) {
            bustFlash = true
        }
        // Reset countdown to full, then animate it down. The withAnimation
        // wrappers must be on separate ticks so the start-value mutation
        // isn't bundled into the long animation.
        bustProgress = 1.0
        DispatchQueue.main.async {
            withAnimation(.linear(duration: bustHoldSeconds)) {
                bustProgress = 0
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(bustHoldSeconds * 1_000_000_000))
            guard thisGeneration == bustGeneration else { return }
            dismissBustFlash()
        }
    }

    private func dismissBustFlash() {
        guard bustFlash else { return }
        withAnimation(.easeIn(duration: 0.35)) {
            bustFlash = false
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Background()

            VStack(spacing: 0) {
                ChromeBar(settings: settings, onNewGame: { startNewGame() })
                    .opacity(revealChrome ? 1 : 0)
                    .offset(y: revealChrome ? 0 : -16)

                Scoreboard(
                    players: store.state.players,
                    scores: store.scores,
                    current: store.state.current,
                    revealed: revealScoreboard,
                    stolenFrom: stolenFromIdx
                )

                Spacer().frame(height: 10)

                ShellsGrid(
                    availableShells: store.state.centerTiles,
                    remainingCount: store.state.centerTiles.count,
                    revealed: revealShells
                )

                Spacer().frame(height: 12)

                DiceStage(
                    phaseHint: store.phaseHint,
                    setAsideSum: store.setAsideSum,
                    rolled: bustAnimatedRoll ?? store.state.rolled,
                    locked: store.state.setAside,
                    diceInHand: store.state.diceInHand,
                    isHumanTurn: store.isHumanTurn,
                    canPick: { store.canPick($0) },
                    onPick: { act(.pick(face: $0)) },
                    canBank: store.canBank && store.isHumanTurn,
                    bankPreview: store.bankActionLabel,
                    isSteal: store.isStealOpportunity,
                    onBank: { act(.stop) },
                    reduceMotion: settings.reducedMotion || iosReduceMotion,
                    speedFactor: settings.gameSpeed.factor
                )
                .opacity(revealStage ? 1 : 0)
                .offset(y: revealStage ? 0 : 12)

                Spacer().frame(height: 4)

                ActionBar(
                    canRoll: store.canRoll,
                    isHumanTurn: store.isHumanTurn,
                    isOver: store.isOver,
                    hasSetAside: !store.state.setAside.isEmpty,
                    activePlayerName: store.state.players[store.state.current].id.capitalized,
                    onRoll: { act(.roll) }
                )
                .opacity(revealAction ? 1 : 0)
                .offset(y: revealAction ? 0 : 30)

                Spacer().frame(height: 14)
            }
            .task {
                await runIntroAnimation()
            }
            .onChange(of: store.state.players.map { $0.tiles.count }) { oldCounts, newCounts in
                detectSteal(oldCounts: oldCounts, newCounts: newCounts)
            }
        }
        .overlay {
            if bustFlash {
                ZStack {
                    // Full coral wash — the danger color, with a vignette
                    // toward the corners so the center stays loudest.
                    RadialGradient(
                        colors: [Color.coral, Color.coralDark],
                        center: .center,
                        startRadius: 80,
                        endRadius: 540
                    )
                    .ignoresSafeArea()

                    // Subtle paper-flecked grain so the wash doesn't read as flat.
                    LinearGradient(
                        colors: [Color.coralLight.opacity(0.18), .clear, Color.coralDark.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .blendMode(.softLight)

                    VStack(spacing: 20) {
                        if bustReason == .greedy || bustReason == .stranded {
                            bustPearl(size: 84)
                        }
                        // Stamped headline — the inverse of the "shell yes"
                        // wordmark moment. Italic for the narrative tone.
                        Text("Oh, shell no.")
                            .font(.avenir(52, weight: .demiBold, italic: true))
                            .tracking(3)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.stampText)
                            .shadow(color: Color.coralDark, radius: 0, x: 2, y: 3)
                            .shadow(color: Color.stampText.opacity(0.25), radius: 26, x: 0, y: 0)

                        // Hairline rule beneath the headline — a printer's mark.
                        Capsule()
                            .fill(Color.stampText.opacity(0.55))
                            .frame(width: 64, height: 1.5)

                        Text(bustSubline)
                            .font(.avenir(18, weight: .medium, italic: true))
                            .tracking(2.5)
                            .textCase(.lowercase)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.stampText)
                            .shadow(color: Color.coralDark.opacity(0.6), radius: 0, x: 1, y: 1)
                            .padding(.horizontal, 30)

                        // The tile the bank just burned — show it so the player
                        // knows exactly what the supply lost.
                        if let burned = burnedTile {
                            VStack(spacing: 8) {
                                Text("A shell drifts away.")
                                    .font(.avenir(13, weight: .medium, italic: true))
                                    .tracking(2.5)
                                    .foregroundStyle(Color.stampText.opacity(0.95))
                                burnedTileChip(value: burned)
                            }
                            .padding(.top, 4)
                        }

                        // Countdown bar + "tap to continue" — anchored to the
                        // burned-shell stack so they read as part of the same
                        // composition rather than orphaned at the bottom.
                        VStack(spacing: 8) {
                            Capsule()
                                .fill(Color.stampText.opacity(0.7))
                                .frame(width: 180 * bustProgress, height: 2)
                                .frame(width: 180, alignment: .leading)
                            Text("tap to continue")
                                .font(.avenir(12, weight: .demiBold, italic: true))
                                .tracking(2)
                                .textCase(.lowercase)
                                .foregroundStyle(Color.stampText.opacity(0.9))
                        }
                        .padding(.top, 12)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { dismissBustFlash() }
                .transition(.opacity)
            }
        }
        .overlay {
            if let event = store.aiEvent {
                AIEventBanner(event: event) {
                    store.dismissAIEvent()
                }
                .animation(.easeOut(duration: 0.2), value: store.aiEvent)
            }
        }
        .fullScreenCover(isPresented: .constant(store.isOver)) {
            CountingCeremony(
                players: store.state.players,
                scores: store.scores,
                onNewGame: { startNewGame() }
            )
        }
        .navigationBarHidden(true)
    }
}

struct ChromeBar: View {
    let settings: SettingsStore
    let onNewGame: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 0) {
                Text("shell ")
                    .foregroundStyle(Color.ink)
                Text("y")
                    .foregroundStyle(Color.coral)
                    .font(.avenir(22, weight: .demiBold))
                Text("es")
                    .foregroundStyle(Color.ink)
            }
            .font(.avenir(22, weight: .ultraLight))
            .tracking(2)
            .textCase(.lowercase)

            Spacer()

            NavigationLink {
                SettingsView(settings: settings, onNewGame: onNewGame)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .padding(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 4)
    }
}

struct ActionBar: View {
    let canRoll: Bool
    let isHumanTurn: Bool
    let isOver: Bool
    let hasSetAside: Bool
    let activePlayerName: String
    let onRoll: () -> Void

    @SwiftUI.State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if isOver {
                Text("game over")
                    .font(.avenir(14, weight: .medium, italic: true))
                    .tracking(2)
                    .textCase(.lowercase)
                    .foregroundStyle(Color.dimInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if !isHumanTurn {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(activePlayerName) is playing")
                            .font(.avenir(15, weight: .medium, italic: true))
                            .foregroundStyle(Color.ink.opacity(0.55))
                        Text("…")
                            .font(.avenir(15, weight: .demiBold))
                            .foregroundStyle(Color.ink.opacity(pulse ? 0.85 : 0.3))
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 22)
                    .frame(maxWidth: 280, minHeight: 50)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.4))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.ink.opacity(0.2), lineWidth: 1)
                    )
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 4)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        pulse.toggle()
                    }
                }
            } else {
                // Single position-stable Roll button — never moves between
                // turns or phases. Bank is anchored to the running sum
                // inside DiceStage, so the bottom of the screen always
                // means "throw the dice."
                // No invite shine on the in-game Roll/Roll Again — once
                // you're playing you don't need the come-hither animation,
                // and the sweeping band reads as a stripe through the
                // button at any opacity.
                HStack {
                    Spacer()
                    Button("Roll On") { onRoll() }
                        .stampButton(primary: true, invite: false)
                        .disabled(!canRoll)
                        .opacity(canRoll ? 1.0 : 0.4)
                        .frame(maxWidth: 280)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .bottom)
    }
}

#Preview {
    GameView(store: GameStore(settings: SettingsStore()), settings: SettingsStore())
}
