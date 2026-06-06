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
        VStack(spacing: 10) {
            Text(phaseHint)
                .font(.cochinItalic(14))
                .foregroundStyle(Color.dimInk)

            Text("Set aside · sum")
                .font(.cochinItalic(9))
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(Color.dimInk)

            Text("\(setAsideSum)")
                .font(.cochin(64))
                .foregroundStyle(Color.ink)

            if !displayRolled.isEmpty {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                    spacing: 8
                ) {
                    ForEach(Array(displayRolled.enumerated()), id: \.offset) { _, face in
                        dieButton(face: face)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 6)
            } else if !locked.isEmpty {
                Text("Roll again or bank")
                    .font(.cochinItalic(12))
                    .foregroundStyle(Color.dimInk)
                    .padding(.top, 6)
            } else {
                Text("\(diceInHand) dice ready")
                    .font(.cochinItalic(12))
                    .foregroundStyle(Color.dimInk)
                    .padding(.top, 6)
            }

            if !locked.isEmpty {
                HStack(spacing: 6) {
                    Text("Locked")
                        .font(.cochinItalic(9))
                        .textCase(.uppercase)
                        .tracking(1.5)
                        .foregroundStyle(Color.dimInk)
                    ForEach(Array(locked.enumerated()), id: \.offset) { _, face in
                        lockedDie(face: face)
                    }
                }
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
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
                Rectangle()
                    .fill(face == .coin ? Color.ink : Color.paper)
                    .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 1.5))
                    .shadow(color: Color.ink, radius: 0, x: 2, y: 2)

                Text(faceText(face))
                    .font(.cochin(30))
                    .foregroundStyle(face == .coin ? Color.paper : Color.ink)
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
        Text(faceText(face))
            .font(.cochin(14))
            .foregroundStyle(face == .coin ? Color.paper : Color.ink)
            .frame(width: 26, height: 26)
            .background(face == .coin ? Color.ink : Color.paper)
            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 1.5))
    }

    private func faceText(_ f: Face) -> String {
        f == .coin ? "C" : "\(f.rawValue)"
    }
}
