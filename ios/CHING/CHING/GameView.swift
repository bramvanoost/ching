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

    private func displayName(_ id: String) -> String {
        id.capitalized
    }

    private var currentSeatName: String {
        store.state.players[store.state.current].id
    }

    private var scoresLine: String {
        zip(store.state.players, store.scores)
            .map { "\(displayName($0.id)) \($1)" }
            .joined(separator: " · ")
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                NavigationLink {
                    SettingsView(settings: settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.ink)
                }
            }

            Text("ching!")
                .font(.bodoniItalic(44))
                .foregroundStyle(Color.ink)

            Text("Turn · \(displayName(currentSeatName)) · \(store.state.phase.rawValue) phase")
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)

            Text(scoresLine)
                .font(.cochin(13))
                .foregroundStyle(Color.ink)

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
                Text("\(displayName(currentSeatName)) is thinking…")
                    .font(.cochinItalic(13))
                    .foregroundStyle(Color.dimInk)
            }

            Spacer()
        }
        .navigationBarHidden(true)
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
            Text("Safes")
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(tiles, id: \.self) { tile in
                        VStack(spacing: 0) {
                            Text("\(tile)")
                                .font(.cochin(14))
                                .foregroundStyle(Color.ink)
                            Text("\(tileCoins(tile))c")
                                .font(.cochinItalic(8))
                                .foregroundStyle(Color.dimInk)
                        }
                        .padding(6)
                        .overlay(Rectangle().stroke(Color.ink, lineWidth: 1.5))
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
            Text("Vaults")
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)
            ForEach(players.indices, id: \.self) { i in
                HStack {
                    Text(players[i].id.capitalized)
                        .font(.cochinItalic(11))
                        .textCase(.uppercase)
                        .tracking(1)
                        .frame(width: 70, alignment: .leading)
                        .foregroundStyle(Color.ink)
                        .overlay(alignment: .leading) {
                            if i == current {
                                Text("▸ ").font(.cochin(11))
                                    .offset(x: -10)
                            }
                        }
                    if players[i].tiles.isEmpty {
                        Text("empty")
                            .font(.cochinItalic(11))
                            .foregroundStyle(Color.dimInk)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(players[i].tiles, id: \.self) { tile in
                                VStack(spacing: 0) {
                                    Text("\(tile)")
                                        .font(.cochin(13))
                                        .foregroundStyle(Color.ink)
                                    Text("\(tileCoins(tile))c")
                                        .font(.cochinItalic(8))
                                        .foregroundStyle(Color.dimInk)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .overlay(Rectangle().stroke(Color.ink, lineWidth: 1.5))
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
            Text("Dice")
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)
            HStack {
                VStack(alignment: .leading) {
                    Text("Rolled")
                        .font(.cochinItalic(9))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(Color.dimInk)
                    HStack(spacing: 4) {
                        ForEach(Array(rolled.enumerated()), id: \.offset) { _, f in
                            Text(faceLabel(f))
                                .frame(width: 22, height: 22)
                                .overlay(Rectangle().stroke(Color.ink, lineWidth: 1.5))
                        }
                        if rolled.isEmpty {
                            Text("(none)").font(.cochinItalic(11)).foregroundStyle(Color.dimInk)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Set aside · sum \(setAsideSum)")
                        .font(.cochinItalic(9))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(Color.dimInk)
                    HStack(spacing: 4) {
                        ForEach(Array(setAside.enumerated()), id: \.offset) { _, f in
                            Text(faceLabel(f))
                                .frame(width: 22, height: 22)
                                .overlay(Rectangle().stroke(Color.ink, lineWidth: 1.5).opacity(0.5))
                        }
                        if setAside.isEmpty {
                            Text("(none)").font(.cochinItalic(11)).foregroundStyle(Color.dimInk)
                        }
                    }
                }
            }
            Text("In hand · \(diceInHand)")
                .font(.cochinItalic(9))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Color.dimInk)
        }
    }
}

struct PickBar: View {
    let store: GameStore
    let act: (Action) -> Void

    private let faces: [Face] = [.one, .two, .three, .four, .five, .coin]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pick")
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)
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
