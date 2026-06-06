import SwiftUI
import CHINGEngine

struct GameView: View {
    let store: GameStore
    let settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var iosReduceMotion
    @SwiftUI.State private var bankFlash: Bool = false
    @SwiftUI.State private var bustFlash: Bool = false

    private func act(_ action: Action) {
        let humanSeat = GameStore.humanSeat
        let wasHumanTurn = store.isHumanTurn
        let beforeVault = store.state.players[humanSeat].tiles.count

        store.apply(action)

        // Detect end-of-turn outcomes for the human player.
        if wasHumanTurn && !store.isHumanTurn && !store.isOver {
            let afterVault = store.state.players[humanSeat].tiles.count
            if afterVault > beforeVault {
                triggerBankFlash()
            } else {
                triggerBustFlash()
            }
        }

        let reduce = settings.reducedMotion || iosReduceMotion
        Task { await store.runAIIfNeeded(reduceMotion: reduce) }
    }

    private func triggerBankFlash() {
        guard !settings.reducedMotion, !iosReduceMotion else { return }
        bankFlash = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            bankFlash = false
        }
    }

    private func triggerBustFlash() {
        guard !settings.reducedMotion, !iosReduceMotion else { return }
        bustFlash = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            bustFlash = false
        }
    }

    private var gameOverMessage: String {
        let ranked = zip(store.state.players, store.scores)
            .map { (id: $0.id, score: $1) }
            .sorted { $0.score > $1.score }

        let top = ranked.first!.score
        let leaders = ranked.filter { $0.score == top }

        let headline: String
        if leaders.count == 1 {
            headline = "\(leaders[0].id.capitalized) wins."
        } else {
            headline = "Tie at the top."
        }

        let body = ranked
            .map { "\($0.id.capitalized) \($0.score)" }
            .joined(separator: " · ")

        return "\(headline)\n\(body)"
    }

    var body: some View {
        ZStack {
            Background()

            VStack(spacing: 0) {
                ChromeBar(settings: settings, onNewGame: { store.newGame() })

                Scoreboard(
                    players: store.state.players,
                    scores: store.scores,
                    current: store.state.current
                )

                SafesGrid(
                    availableSafes: store.state.centerTiles,
                    remainingCount: store.state.centerTiles.count
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
            }
        }
        .overlay {
            if bankFlash {
                LinearGradient(
                    colors: [
                        Color.coinGoldLight.opacity(0.85),
                        Color.coinGoldDark.opacity(0.7)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .overlay {
            if bustFlash {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 40/255, green: 28/255, blue: 50/255).opacity(0.85),
                            Color(red: 60/255, green: 40/255, blue: 78/255).opacity(0.78)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    Text("bust.")
                        .font(.avenir(56, weight: .ultraLight, italic: true))
                        .tracking(4)
                        .foregroundStyle(Color.paper)
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
                    .font(.system(size: 18))
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .padding(8)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .overlay(Circle().strokeBorder(Color.ink.opacity(0.25), lineWidth: 1))
                    )
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
            } else if hasSetAside {
                HStack(spacing: 10) {
                    Button("Roll Again") { onRoll() }
                        .stampButton(primary: true)
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
                        .stampButton(primary: true)
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
    }
}

#Preview {
    GameView(store: GameStore(settings: SettingsStore()), settings: SettingsStore())
}
