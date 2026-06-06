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

    private var currentSeatName: String {
        store.state.players[store.state.current].id
    }

    private var gameOverMessage: String {
        let ranked = zip(store.state.players, store.scores)
            .map { (id: $0.id, score: $1) }
            .sorted { $0.score > $1.score }

        let top = ranked.first!.score
        let leaders = ranked.filter { $0.score == top }

        let headline: String
        if leaders.count == 1 {
            headline = "\(leaders[0].id) wins."
        } else {
            headline = "Tie at the top."
        }

        let body = ranked
            .map { "\($0.id) \($0.score)" }
            .joined(separator: " · ")

        return "\(headline)\n\(body)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CHING")
                .font(.largeTitle)
                .bold()

            Text("Phase: \(store.state.phase.rawValue)")
            Text("Turn: \(store.state.players[store.state.current].id)")
            Text("Scores: " + zip(store.state.players, store.scores)
                .map { "\($0.id) \($1)" }
                .joined(separator: "  "))
            CenterTileRow(tiles: store.state.centerTiles)
            VaultRow(players: store.state.players, current: store.state.current)
            DiceRow(
                rolled: store.state.rolled,
                setAside: store.state.setAside,
                setAsideSum: store.setAsideSum,
                diceInHand: store.state.diceInHand
            )
            PickBar(store: store, act: act)
            ActionBar(store: store, act: act)

            if !store.isHumanTurn && !store.isOver {
                Text("\(currentSeatName) is thinking…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .alert("Game over", isPresented: .constant(store.isOver)) {
            Button("New Game") {
                store.newGame()
            }
        } message: {
            Text(gameOverMessage)
        }
    }
}

struct CenterTileRow: View {
    let tiles: [Int]

    var body: some View {
        VStack(alignment: .leading) {
            Text("CENTER").font(.caption).bold()
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(tiles, id: \.self) { tile in
                        VStack {
                            Text("\(tile)").font(.headline)
                            Text("\(tileCoins(tile))c").font(.caption2)
                        }
                        .padding(6)
                        .overlay(Rectangle().stroke())
                    }
                }
            }
        }
    }
}

struct VaultRow: View {
    let players: [Player]
    let current: Int

    var body: some View {
        VStack(alignment: .leading) {
            Text("VAULTS").font(.caption).bold()
            ForEach(players.indices, id: \.self) { i in
                HStack {
                    Text(players[i].id)
                        .bold(i == current)
                        .frame(width: 70, alignment: .leading)
                    if players[i].tiles.isEmpty {
                        Text("(empty)").font(.caption).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(players[i].tiles, id: \.self) { tile in
                                VStack(spacing: 0) {
                                    Text("\(tile)")
                                    Text("\(tileCoins(tile))c").font(.caption2)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .overlay(Rectangle().stroke())
                            }
                        }
                    }
                    Spacer()
                }
            }
        }
    }
}

func faceLabel(_ f: Face) -> String {
    f == .coin ? "C" : "\(f.rawValue)"
}

struct DiceRow: View {
    let rolled: [Face]
    let setAside: [Face]
    let setAsideSum: Int
    let diceInHand: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DICE").font(.caption).bold()
            HStack {
                VStack(alignment: .leading) {
                    Text("Rolled").font(.caption2)
                    HStack(spacing: 4) {
                        ForEach(Array(rolled.enumerated()), id: \.offset) { _, f in
                            Text(faceLabel(f))
                                .frame(width: 22, height: 22)
                                .overlay(Rectangle().stroke())
                        }
                        if rolled.isEmpty {
                            Text("(none)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Set aside (sum \(setAsideSum))").font(.caption2)
                    HStack(spacing: 4) {
                        ForEach(Array(setAside.enumerated()), id: \.offset) { _, f in
                            Text(faceLabel(f))
                                .frame(width: 22, height: 22)
                                .overlay(Rectangle().stroke().opacity(0.5))
                        }
                        if setAside.isEmpty {
                            Text("(none)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("In hand: \(diceInHand)").font(.caption2)
        }
    }
}

struct PickBar: View {
    let store: GameStore
    let act: (Action) -> Void

    private let faces: [Face] = [.one, .two, .three, .four, .five, .coin]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PICK").font(.caption).bold()
            HStack(spacing: 6) {
                ForEach(faces, id: \.self) { face in
                    Button(faceLabel(face)) {
                        act(.pick(face: face))
                    }
                    .disabled(!store.canPick(face))
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

struct ActionBar: View {
    let store: GameStore
    let act: (Action) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Roll") {
                act(.roll)
            }
            .disabled(!store.canRoll)
            .buttonStyle(.borderedProminent)

            Button(store.bankActionLabel) {
                act(.stop)
            }
            .disabled(!store.canBank)
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    GameView(store: GameStore(settings: SettingsStore()), settings: SettingsStore())
}
