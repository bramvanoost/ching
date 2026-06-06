import SwiftUI
import CHINGEngine

struct GameView: View {
    let store: GameStore
    let settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var iosReduceMotion

    private func act(_ action: Action) {
        store.apply(action)
        let reduce = settings.reducedMotion || iosReduceMotion
        Task { await store.runAIIfNeeded(reduceMotion: reduce) }
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
            Color.paper.ignoresSafeArea()

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
                    onPick: { act(.pick(face: $0)) }
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
        .navigationBarHidden(true)
        .alert("Game over", isPresented: .constant(store.isOver)) {
            Button("New Game") { store.newGame() }
        } message: {
            Text(gameOverMessage)
        }
    }
}

struct ChromeBar: View {
    let settings: SettingsStore
    let onNewGame: () -> Void

    var body: some View {
        HStack {
            Text("ching!")
                .font(.bodoniItalic(22))
                .foregroundStyle(Color.ink)
            Spacer()
            NavigationLink {
                SettingsView(settings: settings, onNewGame: onNewGame)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.ink)
                    .opacity(0.6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
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
            Rectangle().fill(Color.ink).frame(height: 1.5)

            if isOver {
                Text("— game over —")
                    .font(.bodoni(15))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(Color.dimInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else if !isHumanTurn {
                Text("— waiting —")
                    .font(.bodoni(15))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(Color.dimInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else if hasSetAside {
                HStack(spacing: 12) {
                    Button("Roll Again") { onRoll() }
                        .stampButton(primary: true)
                        .disabled(!canRoll)
                        .opacity(canRoll ? 1.0 : 0.4)

                    Button(bankLabel) { onBank() }
                        .stampButton(primary: false)
                        .disabled(!canBank)
                        .opacity(canBank ? 1.0 : 0.4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 18)
            } else {
                HStack {
                    Spacer()
                    Button("Roll") { onRoll() }
                        .stampButton(primary: true)
                        .disabled(!canRoll)
                        .opacity(canRoll ? 1.0 : 0.4)
                        .frame(maxWidth: 260)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
        }
        .background(Color.paper)
    }
}

#Preview {
    GameView(store: GameStore(settings: SettingsStore()), settings: SettingsStore())
}
