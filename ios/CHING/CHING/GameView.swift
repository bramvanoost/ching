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

#Preview {
    GameView()
}
