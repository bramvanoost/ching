import SwiftUI
import CHINGEngine

struct Scoreboard: View {
    let players: [Player]
    let scores: [Int]
    let current: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(players.indices, id: \.self) { i in
                column(playerIndex: i)
                    .frame(maxWidth: .infinity)
                if i < players.count - 1 {
                    Rectangle()
                        .fill(Color.ink)
                        .frame(width: 1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(
            VStack(spacing: 0) {
                Rectangle().fill(Color.ink).frame(height: 1.5)
                Spacer()
                Rectangle().fill(Color.ink).frame(height: 1.5)
            }
        )
    }

    @ViewBuilder
    private func column(playerIndex i: Int) -> some View {
        let isActive = i == current
        VStack(spacing: 4) {
            Text(players[i].id.capitalized)
                .font(.bodoniItalic(18))
                .foregroundStyle(isActive ? Color.paper : Color.ink)
                .padding(.top, 8)

            Text("\(scores[i])")
                .font(.cochin(32))
                .foregroundStyle(isActive ? Color.paper : Color.ink)

            if players[i].tiles.isEmpty {
                Text("empty")
                    .font(.cochinItalic(9))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(isActive ? Color.paper.opacity(0.6) : Color.dimInk)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            } else {
                VaultStack(safes: players[i].tiles, activeSeat: isActive)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(isActive ? Color.ink : Color.paper)
    }
}
