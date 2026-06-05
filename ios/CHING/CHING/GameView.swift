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
            Text("Center tiles: \(store.state.centerTiles.count)")
            Text("Dice in hand: \(store.state.diceInHand)")

            Spacer()
        }
        .padding()
    }
}

#Preview {
    GameView()
}
