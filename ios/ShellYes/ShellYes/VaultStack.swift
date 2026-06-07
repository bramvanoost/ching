import SwiftUI
import ShellYesEngine

struct VaultStack: View {
    let safes: [Int]
    var activeSeat: Bool = false

    @SwiftUI.State private var addSparkleTrigger: Int = 0

    private let safeWidth: CGFloat = 38
    private let safeHeight: CGFloat = 38
    private let layerOffset: CGFloat = 5

    private var stackHeight: CGFloat {
        if safes.isEmpty { return 36 }
        return safeHeight + CGFloat(max(0, safes.count - 1)) * layerOffset
    }

    /// Newest first (top of pile). Engine stores newest at end of `tiles`.
    private var stackedNewestFirst: [Int] {
        safes.reversed()
    }

    var body: some View {
        if safes.isEmpty {
            EmptyView()
        } else {
            ZStack(alignment: .top) {
                ForEach(Array(stackedNewestFirst.enumerated()), id: \.offset) { idx, safe in
                    safeView(value: safe, isTop: idx == 0)
                        .overlay {
                            if idx == 0 && addSparkleTrigger > 0 {
                                SparkleField(count: 42, startRadius: 22, spread: 70, duration: 1.1)
                                    .frame(width: 90, height: 90)
                                    .id(addSparkleTrigger)
                            }
                        }
                        .offset(y: CGFloat(idx) * layerOffset)
                        .zIndex(Double(stackedNewestFirst.count - idx))
                        .transition(
                            idx == 0
                            ? .asymmetric(
                                insertion: .scale(scale: 0.15).combined(with: .opacity),
                                removal: .opacity
                              )
                            : .opacity
                        )
                }
            }
            .frame(width: safeWidth, height: stackHeight, alignment: .top)
            .animation(.spring(response: 0.55, dampingFraction: 0.55), value: safes.count)
            .onChange(of: safes.count) { oldValue, newValue in
                guard newValue > oldValue else { return }
                addSparkleTrigger += 1
                let trigger = addSparkleTrigger
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    if addSparkleTrigger == trigger { addSparkleTrigger = 0 }
                }
            }
        }
    }

    @ViewBuilder
    private func safeView(value: Int, isTop: Bool) -> some View {
        ZStack {
            ShellCardShape()
                .fill(
                    LinearGradient(
                        colors: [Color.safePeachLight, Color.safePeachDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    ShellCardShape()
                        .strokeBorder(Color.treasureInk, lineWidth: 1.5)
                )
                .shadow(color: Color.treasureInk.opacity(0.15), radius: 0, x: 0, y: 2)

            if isTop {
                VStack(spacing: 2) {
                    Text("\(value)")
                        .font(.avenir(13, weight: .demiBold))
                        .foregroundStyle(Color.treasureInk)
                    PearlRow(count: GameStore.safeCoins(value), diameter: 4, spacing: 1.5)
                }
            }
        }
        .frame(width: safeWidth, height: safeHeight)
    }
}
