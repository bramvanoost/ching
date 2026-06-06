import SwiftUI
import CHINGEngine

struct VaultStack: View {
    let safes: [Int]
    var activeSeat: Bool = false

    private let safeWidth: CGFloat = 44
    private let safeHeight: CGFloat = 42
    private let layerOffset: CGFloat = 6

    var stackHeight: CGFloat {
        if safes.isEmpty { return 48 }
        return safeHeight + CGFloat(max(0, safes.count - 1)) * layerOffset
    }

    private var stackedNewestFirst: [Int] {
        safes.reversed()
    }

    var body: some View {
        if safes.isEmpty {
            Text("empty")
                .font(.cochinItalic(9))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(activeSeat ? Color.paper.opacity(0.6) : Color.dimInk)
                .frame(width: safeWidth, height: 48)
        } else {
            ZStack(alignment: .top) {
                ForEach(Array(stackedNewestFirst.enumerated()), id: \.offset) { idx, safe in
                    safeView(value: safe, isTop: idx == 0)
                        .offset(y: CGFloat(idx) * layerOffset)
                        .zIndex(Double(stackedNewestFirst.count - idx))
                }
            }
            .frame(width: safeWidth, height: stackHeight, alignment: .top)
        }
    }

    @ViewBuilder
    private func safeView(value: Int, isTop: Bool) -> some View {
        let strokeColor = activeSeat ? Color.paper : Color.ink
        let fillColor = activeSeat ? Color.ink : Color.paper
        VStack(spacing: 3) {
            if isTop {
                Text("\(value)")
                    .font(.cochin(18))
                    .foregroundStyle(activeSeat ? Color.paper : Color.ink)
                CoinPips(count: GameStore.safeCoins(value), diameter: 5, spacing: 2)
            } else {
                EmptyView()
            }
        }
        .frame(width: safeWidth, height: safeHeight)
        .background(fillColor)
        .overlay(Rectangle().strokeBorder(strokeColor, lineWidth: 1.5))
    }
}
