import SwiftUI
import CHINGEngine

struct GameView: View {
    @SwiftUI.State private var store = GameStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CHING")
                .font(.largeTitle)
                .bold()

            Text("Phase: \(store.state.phase.rawValue)")
            Text("Turn: \(store.state.players[store.state.current].id)")
            Text("Scores: YOU \(store.scores[0])  JONES \(store.scores[1])")
            CenterTileRow(tiles: store.state.centerTiles)
            VaultRow(players: store.state.players, current: store.state.current)
            Text("Dice in hand: \(store.state.diceInHand)")

            Spacer()
        }
        .padding()
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
                                Text("\(tile)")
                                    .padding(.horizontal, 6)
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

#Preview {
    GameView()
}
