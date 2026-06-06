import SwiftUI
import CHINGEngine

struct DiceStage: View {
    let phaseHint: String
    let setAsideSum: Int
    let rolled: [Face]
    let locked: [Face]
    let diceInHand: Int
    let canPick: (Face) -> Bool
    let onPick: (Face) -> Void
    var reduceMotion: Bool = false

    @SwiftUI.State private var animatedRolled: [Face]?

    private var displayRolled: [Face] {
        animatedRolled ?? rolled
    }

    private var isAnimating: Bool {
        animatedRolled != nil
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(phaseHint.lowercased())
                .font(.avenir(13, weight: .medium, italic: true))
                .foregroundStyle(Color.dimInk)

            Text("set aside · sum")
                .font(.avenir(9, weight: .medium, italic: true))
                .textCase(.lowercase)
                .tracking(2)
                .foregroundStyle(Color.dimInk.opacity(0.7))

            Text("\(setAsideSum)")
                .font(.avenir(60, weight: .ultraLight))
                .foregroundStyle(Color.ink)

            if !displayRolled.isEmpty {
                Text("dice")
                    .font(.avenir(9, weight: .medium, italic: true))
                    .tracking(2)
                    .foregroundStyle(Color.dimInk.opacity(0.7))

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                    spacing: 8
                ) {
                    ForEach(Array(displayRolled.enumerated()), id: \.offset) { _, face in
                        dieButton(face: face)
                    }
                }
                .padding(.horizontal, 30)
            } else if !locked.isEmpty {
                Text("roll again or bank")
                    .font(.avenir(12, weight: .medium, italic: true))
                    .foregroundStyle(Color.dimInk.opacity(0.7))
            } else {
                Text("\(diceInHand) dice ready")
                    .font(.avenir(12, weight: .medium, italic: true))
                    .foregroundStyle(Color.dimInk.opacity(0.7))
            }

            if !locked.isEmpty {
                HStack(spacing: 6) {
                    Text("locked")
                        .font(.avenir(9, weight: .medium, italic: true))
                        .tracking(2)
                        .foregroundStyle(Color.dimInk.opacity(0.7))
                    ForEach(Array(locked.enumerated()), id: \.offset) { _, face in
                        lockedDie(face: face)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .onChange(of: rolled) { oldValue, newValue in
            guard !reduceMotion else { return }
            if oldValue.isEmpty && !newValue.isEmpty {
                animateRoll(count: newValue.count)
            }
        }
    }

    private func animateRoll(count: Int) {
        let pool: [Face] = [.one, .two, .three, .four, .five, .coin]
        Task { @MainActor in
            let frames = 5
            let frameNs: UInt64 = 80_000_000
            for _ in 0..<frames {
                animatedRolled = (0..<count).map { _ in pool.randomElement()! }
                try? await Task.sleep(nanoseconds: frameNs)
            }
            animatedRolled = nil
        }
    }

    @ViewBuilder
    private func dieButton(face: Face) -> some View {
        let pickable = !isAnimating && canPick(face)
        Button {
            if pickable { onPick(face) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        face == .coin
                            ? LinearGradient(
                                colors: [Color.coinGoldLight, Color.coinGoldDark],
                                startPoint: .top,
                                endPoint: .bottom
                              )
                            : LinearGradient(
                                colors: [Color.safePeachLight, Color.safePeachDark],
                                startPoint: .top,
                                endPoint: .bottom
                              )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.treasureInk, lineWidth: 1.5)
                    )
                    .shadow(color: Color.treasureInk.opacity(0.2), radius: 0, x: 0, y: 3)
                    .shadow(color: Color.treasureInk.opacity(0.12), radius: 6, x: 0, y: 5)

                Text(faceText(face))
                    .font(.avenir(22, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!pickable)
        .opacity(pickable ? 1.0 : (isAnimating ? 0.85 : 0.5))
    }

    @ViewBuilder
    private func lockedDie(face: Face) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    face == .coin
                        ? LinearGradient(
                            colors: [Color.coinGoldLight, Color.coinGoldDark],
                            startPoint: .top,
                            endPoint: .bottom
                          )
                        : LinearGradient(
                            colors: [Color.safePeachLight, Color.safePeachDark],
                            startPoint: .top,
                            endPoint: .bottom
                          )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.treasureInk, lineWidth: 1.5)
                )
            Text(faceText(face))
                .font(.avenir(14, weight: .demiBold))
                .foregroundStyle(Color.treasureInk)
        }
        .frame(width: 26, height: 26)
        .opacity(0.75)
    }

    private func faceText(_ f: Face) -> String {
        f == .coin ? "C" : "\(f.rawValue)"
    }
}
