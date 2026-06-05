import SwiftUI
import CHINGEngine

struct ContentView: View {
    var body: some View {
        let s = initialState(playerIds: ["YOU", "JONES"])
        Text("Center tiles: \(s.centerTiles.count)")
    }
}

#Preview {
    ContentView()
}
