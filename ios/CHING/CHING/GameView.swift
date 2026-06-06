import SwiftUI
import CHINGEngine

struct GameView: View {
    let store: GameStore
    let settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var iosReduceMotion
    @SwiftUI.State private var bustFlash: Bool = false
    @SwiftUI.State private var bustReason: BustReason = .rolled
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
                triggerBustFlash()
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
        case .rolled: return "a tile was burned"
        }
    }

    @ViewBuilder
    private func redCoinGlyph(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.coralLight, Color.coral, Color.coralDark],
                        center: UnitPoint(x: 0.4, y: 0.35),
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .overlay(
                    Circle().strokeBorder(Color.paper.opacity(0.9), lineWidth: 2)
                )
            Circle()
                .strokeBorder(Color.coralLight.opacity(0.75), lineWidth: 1.5)
                .padding(6)
        }
        .frame(width: size, height: size)
    }

    private func triggerBustFlash() {
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

                Spacer().frame(height: 18)

                SafesGrid(
                    availableSafes: store.state.centerTiles,
                    remainingCount: store.state.centerTiles.count,
                    revealed: revealSafes
                )

                DiceStage(
                    phaseHint: store.phaseHint,
                    setAsideSum: store.setAsideSum,
                    rolled: store.state.rolled,
                    locked: store.state.setAside,
                    diceInHand: store.state.diceInHand,
                    canPick: { store.canPick($0) },
                    onPick: { act(.pick(face: $0)) },
                    reduceMotion: settings.reducedMotion || iosReduceMotion
                )
                .opacity(revealStage ? 1 : 0)
                .offset(y: revealStage ? 0 : 12)

                Spacer(minLength: 0)

                ActionBar(
                    canRoll: store.canRoll,
                    canBank: store.canBank,
                    isHumanTurn: store.isHumanTurn,
                    isOver: store.isOver,
                    hasSetAside: !store.state.setAside.isEmpty,
                    bankLabel: store.bankActionLabel,
                    onRoll: { act(.roll) },
                    onBank: { act(.stop) }
                )
                .opacity(revealAction ? 1 : 0)
                .offset(y: revealAction ? 0 : 30)
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
                    LinearGradient(
                        colors: [
                            Color(red: 24/255, green: 16/255, blue: 34/255).opacity(0.95),
                            Color(red: 44/255, green: 28/255, blue: 60/255).opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    VStack(spacing: 18) {
                        if bustReason == .greedy {
                            redCoinGlyph(size: 80)
                                .shadow(color: Color.coral.opacity(0.6), radius: 24, x: 0, y: 0)
                                .shadow(color: Color.coralLight.opacity(0.4), radius: 10, x: 0, y: 0)
                        }
                        Text("bust.")
                            .font(.avenir(84, weight: .ultraLight, italic: true))
                            .tracking(6)
                            .foregroundStyle(Color.paper)
                            .shadow(color: Color.coral.opacity(0.4), radius: 18, x: 0, y: 0)
                        Text(bustSubline)
                            .font(.avenir(13, weight: .medium, italic: true))
                            .tracking(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.paper.opacity(0.75))
                            .padding(.horizontal, 30)
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
                Text("c")
                    .foregroundStyle(Color.ink)
                Text("h")
                    .foregroundStyle(Color.coral)
                    .font(.avenir(26, weight: .demiBold))
                Text("ing")
                    .foregroundStyle(Color.ink)
            }
            .font(.avenir(26, weight: .ultraLight))
            .tracking(3)
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
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

struct ActionBar: View {
    let canRoll: Bool
    let canBank: Bool
    let isHumanTurn: Bool
    let isOver: Bool
    let hasSetAside: Bool
    let bankLabel: String
    let onRoll: () -> Void
    let onBank: () -> Void

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
            }
            else if hasSetAside {
                HStack(spacing: 10) {
                    Button("Roll Again") { onRoll() }
                        .stampButton(primary: true, invite: canRoll)
                        .disabled(!canRoll)
                        .opacity(canRoll ? 1.0 : 0.4)

                    Button(bankLabel) { onBank() }
                        .stampButton(primary: false)
                        .disabled(!canBank)
                        .opacity(canBank ? 1.0 : 0.4)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 22)
            } else {
                HStack {
                    Spacer()
                    Button("Roll") { onRoll() }
                        .stampButton(primary: true, invite: canRoll)
                        .disabled(!canRoll)
                        .opacity(canRoll ? 1.0 : 0.4)
                        .frame(maxWidth: 280)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 22)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .bottom)
    }
}

#Preview {
    GameView(store: GameStore(settings: SettingsStore()), settings: SettingsStore())
}
