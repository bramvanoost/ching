import SwiftUI
import CHINGEngine

struct GameView: View {
    let store: GameStore
    let settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var iosReduceMotion
    @SwiftUI.State private var bustFlash: Bool = false
    @SwiftUI.State private var bustReason: BustReason = .rolled
    @SwiftUI.State private var burnedTile: Int? = nil
    @SwiftUI.State private var stolenFromIdx: Int? = nil

    enum BustReason {
        case greedy  // tried to bank without a coin
        case rolled  // roll produced no new pickable face
    }
    @SwiftUI.State private var revealChrome: Bool = false
    @SwiftUI.State private var revealScoreboard: Bool = false
    @SwiftUI.State private var revealSafes: Bool = false
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

        store.apply(action)

        // Detect end-of-turn outcomes for the human player — bust gets a flash;
        // bank/steal celebration is handled per-column (sparkles + steal pulse).
        if wasHumanTurn && !store.isHumanTurn && !store.isOver {
            let afterVault = store.state.players[humanSeat].tiles.count
            if afterVault <= beforeVault {
                if case .stop = action, !hadCoinBefore {
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
                triggerBustFlash()
            } else {
                // Vault grew — successful bank or steal.
                GameSFX.shared.playBank()
            }
        }

        let reduce = settings.reducedMotion || iosReduceMotion
        Task { await store.runAIIfNeeded(reduceMotion: reduce) }
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
            revealSafes = true
            revealStage = true
            revealAction = true
            return
        }
        withAnimation(.easeOut(duration: 0.35)) { revealChrome = true }
        try? await Task.sleep(nanoseconds: 150_000_000)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { revealScoreboard = true }
        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(.easeOut(duration: 0.45)) { revealSafes = true }
        try? await Task.sleep(nanoseconds: 650_000_000)
        withAnimation(.easeOut(duration: 0.35)) { revealStage = true }
        try? await Task.sleep(nanoseconds: 180_000_000)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { revealAction = true }
    }

    private var bustSubline: String {
        switch bustReason {
        case .greedy: return "you had no coins and got greedy"
        case .rolled: return "the roll gave you nothing"
        }
    }

    @ViewBuilder
    private func burnedTileChip(value: Int) -> some View {
        let coins = GameStore.safeCoins(value)
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color.safePeachLight, Color.safePeachDark],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.stampText.opacity(0.95), lineWidth: 2)
                )
                .shadow(color: Color.coralDark.opacity(0.6), radius: 0, x: 0, y: 5)
                .shadow(color: Color.coralDark.opacity(0.3), radius: 14, x: 0, y: 0)
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.avenir(28, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
                CoinPips(count: coins, diameter: 7, spacing: 3)
            }
        }
        .frame(width: 64, height: 80)
    }

    /// A "cold coin" — a coin shape rendered in cream against the coral bust
    /// wash so it stays legible. The empty interior reinforces "no coin".
    @ViewBuilder
    private func redCoinGlyph(size: CGFloat) -> some View {
        ZStack {
            // Outer disc — cream so it pops on the coral background.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.stampText, Color.stampText.opacity(0.85)],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .overlay(
                    Circle().strokeBorder(Color.coralDark, lineWidth: 3)
                )
                .shadow(color: Color.coralDark.opacity(0.5), radius: 0, x: 0, y: 4)

            // Inner ring — echoes the live coin glyph elsewhere.
            Circle()
                .strokeBorder(Color.coralDark.opacity(0.55), lineWidth: 1.5)
                .padding(size * 0.13)

            // A coral "C" — visibly the right shape, visibly the wrong color.
            Text("C")
                .font(.avenir(size * 0.45, weight: .demiBold, italic: true))
                .foregroundStyle(Color.coralDark)
        }
        .frame(width: size, height: size)
    }

    private func triggerBustFlash() {
        GameSFX.shared.playBust()
        guard !settings.reducedMotion, !iosReduceMotion else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            bustFlash = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.easeIn(duration: 0.4)) {
                bustFlash = false
            }
        }
    }

    var body: some View {
        ZStack {
            Background()

            VStack(spacing: 0) {
                ChromeBar(settings: settings, onNewGame: { store.newGame() })
                    .opacity(revealChrome ? 1 : 0)
                    .offset(y: revealChrome ? 0 : -16)

                Scoreboard(
                    players: store.state.players,
                    scores: store.scores,
                    current: store.state.current,
                    revealed: revealScoreboard,
                    stolenFrom: stolenFromIdx
                )

                Spacer().frame(height: 8)

                SafesGrid(
                    availableSafes: store.state.centerTiles,
                    remainingCount: store.state.centerTiles.count,
                    revealed: revealSafes
                )

                Spacer().frame(height: 22)

                DiceStage(
                    phaseHint: store.phaseHint,
                    setAsideSum: store.setAsideSum,
                    rolled: store.state.rolled,
                    locked: store.state.setAside,
                    diceInHand: store.state.diceInHand,
                    isHumanTurn: store.isHumanTurn,
                    canPick: { store.canPick($0) },
                    onPick: { act(.pick(face: $0)) },
                    canBank: store.canBank && store.isHumanTurn,
                    bankPreview: store.bankActionLabel,
                    onBank: { act(.stop) },
                    reduceMotion: settings.reducedMotion || iosReduceMotion
                )
                .opacity(revealStage ? 1 : 0)
                .offset(y: revealStage ? 0 : 12)

                Spacer(minLength: 0)

                ActionBar(
                    canRoll: store.canRoll,
                    isHumanTurn: store.isHumanTurn,
                    isOver: store.isOver,
                    hasSetAside: !store.state.setAside.isEmpty,
                    onRoll: { act(.roll) }
                )
                .opacity(revealAction ? 1 : 0)
                .offset(y: revealAction ? 0 : 30)

                Spacer().frame(height: 32)
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
                        if bustReason == .greedy {
                            redCoinGlyph(size: 84)
                                .shadow(color: Color.stampText.opacity(0.35), radius: 22, x: 0, y: 0)
                                .shadow(color: Color.coralDark, radius: 0, x: 0, y: 6)
                        }
                        // "bust." as a stamped headline — hard offset shadow
                        // for stamp character, cream against the coral wash.
                        Text("bust.")
                            .font(.avenir(96, weight: .demiBold, italic: true))
                            .tracking(4)
                            .foregroundStyle(Color.stampText)
                            .shadow(color: Color.coralDark, radius: 0, x: 3, y: 4)
                            .shadow(color: Color.stampText.opacity(0.25), radius: 26, x: 0, y: 0)

                        // Hairline rule beneath the headline — a printer's mark.
                        Capsule()
                            .fill(Color.stampText.opacity(0.55))
                            .frame(width: 64, height: 1.5)

                        Text(bustSubline)
                            .font(.avenir(14, weight: .medium, italic: true))
                            .tracking(2.5)
                            .textCase(.lowercase)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.stampText.opacity(0.92))
                            .padding(.horizontal, 30)

                        // The tile the bank just burned — show it so the player
                        // knows exactly what the supply lost.
                        if let burned = burnedTile {
                            VStack(spacing: 8) {
                                Text("tile burned")
                                    .font(.avenir(10, weight: .medium, italic: true))
                                    .tracking(2.5)
                                    .textCase(.lowercase)
                                    .foregroundStyle(Color.stampText.opacity(0.7))
                                burnedTileChip(value: burned)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: .constant(store.isOver)) {
            CountingCeremony(
                players: store.state.players,
                scores: store.scores,
                onNewGame: { store.newGame() }
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
    let onRoll: () -> Void

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
                Text("waiting…")
                    .font(.avenir(14, weight: .medium, italic: true))
                    .tracking(2)
                    .textCase(.lowercase)
                    .foregroundStyle(Color.dimInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                // Single position-stable Roll button — never moves between
                // turns or phases. Bank is anchored to the running sum
                // inside DiceStage, so the bottom of the screen always
                // means "throw the dice."
                HStack {
                    Spacer()
                    Button(hasSetAside ? "Roll Again" : "Roll") { onRoll() }
                        .stampButton(primary: true, invite: canRoll)
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
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .bottom)
    }
}

#Preview {
    GameView(store: GameStore(settings: SettingsStore()), settings: SettingsStore())
}
