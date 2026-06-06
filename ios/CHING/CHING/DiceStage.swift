import SwiftUI
import CHINGEngine

struct DiceStage: View {
    let phaseHint: String
    let setAsideSum: Int
    let rolled: [Face]
    let locked: [Face]
    let diceInHand: Int
    let isHumanTurn: Bool
    let canPick: (Face) -> Bool
    let onPick: (Face) -> Void
    var reduceMotion: Bool = false

    @SwiftUI.State private var animatedRolled: [Face]?
    @SwiftUI.State private var pickSparkleTrigger: Int = 0
    @SwiftUI.State private var lastSum: Int = -1
    @SwiftUI.State private var pickingFace: Face?

    private var displayRolled: [Face] {
        animatedRolled ?? rolled
    }

    private var isAnimating: Bool {
        animatedRolled != nil
    }

    var body: some View {
        VStack(spacing: 6) {
            // Phase hint — fixed height, always present.
            Text(phaseHint.lowercased())
                .font(.avenir(14, weight: .medium, italic: true))
                .foregroundStyle(Color.ink.opacity(0.78))
                .frame(height: 18)

            // Hero number — the running sum, treated as a stamped headline
            // with a hard ink offset and a soft halo.
            ZStack {
                Text("\(setAsideSum)")
                    .font(.avenir(76, weight: .demiBold, italic: true))
                    .foregroundStyle(Color.ink)
                    .monospacedDigit()
                    .shadow(color: Color.ink.opacity(0.28), radius: 0, x: 2, y: 3)
                    .shadow(color: Color.ink.opacity(0.12), radius: 10, x: 0, y: 0)
                if pickSparkleTrigger > 0 {
                    SparkleField(count: 50, startRadius: 50, spread: 90, duration: 1.0)
                        .frame(width: 220, height: 160)
                        .id(pickSparkleTrigger)
                }
            }
            .frame(height: 84)

            // Dice slot — fixed height holds either the 4-col grid (max 2 rows)
            // or a centered status line. Swapping inside doesn't reflow.
            ZStack {
                if !displayRolled.isEmpty {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                        spacing: 8
                    ) {
                        ForEach(Array(displayRolled.enumerated()), id: \.offset) { _, face in
                            dieButton(face: face)
                        }
                    }
                    .padding(.horizontal, 40)
                } else if locked.isEmpty {
                    Text("\(diceInHand) dice ready")
                        .font(.avenir(13, weight: .medium, italic: true))
                        .foregroundStyle(Color.ink.opacity(0.65))
                }
                // When dice are empty but you have locked tiles, the phase
                // hint at the top already says "Roll again, or bank." — no
                // need to repeat it here.
            }
            .frame(height: 158)

            // Locked slot — always reserved, transparent when empty.
            HStack(spacing: 6) {
                Text("locked")
                    .font(.avenir(10, weight: .medium, italic: true))
                    .tracking(2)
                    .foregroundStyle(Color.ink.opacity(0.55))
                ForEach(Array(locked.enumerated()), id: \.offset) { _, face in
                    lockedDie(face: face)
                }
            }
            .frame(height: 28)
            .opacity(locked.isEmpty ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.vertical, 6)
        .onChange(of: rolled) { oldValue, newValue in
            if oldValue.isEmpty && !newValue.isEmpty {
                if reduceMotion {
                    if isHumanTurn { GameSFX.shared.playRoll() }
                } else {
                    animateRoll(count: newValue.count, withSound: isHumanTurn)
                }
            }
        }
        .onChange(of: setAsideSum) { oldValue, newValue in
            guard !reduceMotion, newValue > oldValue, oldValue >= 0 else {
                lastSum = newValue
                return
            }
            pickSparkleTrigger += 1
            let trigger = pickSparkleTrigger
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if pickSparkleTrigger == trigger { pickSparkleTrigger = 0 }
            }
            lastSum = newValue
        }
    }

    private func animateRoll(count: Int, withSound: Bool) {
        let pool: [Face] = [.one, .two, .three, .four, .five, .coin]
        Task { @MainActor in
            let frames = 5
            let frameNs: UInt64 = 80_000_000
            for _ in 0..<frames {
                if withSound { GameSFX.shared.playRoll() }
                animatedRolled = (0..<count).map { _ in pool.randomElement()! }
                try? await Task.sleep(nanoseconds: frameNs)
            }
            animatedRolled = nil
        }
    }

    @ViewBuilder
    private func dieButton(face: Face) -> some View {
        let isPicked = pickingFace == face
        let isOther = pickingFace != nil && pickingFace != face
        let canTap = !isAnimating && pickingFace == nil && canPick(face)
        Button {
            handlePick(face)
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
                            .strokeBorder(
                                isPicked ? Color.gold : Color.treasureInk,
                                lineWidth: isPicked ? 2.5 : 1.5
                            )
                    )
                    .shadow(color: Color.treasureInk.opacity(0.2), radius: 0, x: 0, y: 3)
                    .shadow(color: Color.treasureInk.opacity(0.12), radius: 6, x: 0, y: 5)
                    .shadow(color: isPicked ? Color.gold.opacity(0.7) : .clear, radius: 14, x: 0, y: 0)

                if face == .coin {
                    ShellGlyph(size: 32)
                } else {
                    Text(faceText(face))
                        .font(.avenir(22, weight: .demiBold))
                        .foregroundStyle(Color.treasureInk)
                }

                if isPicked {
                    SparkleField(count: 44, startRadius: 30, spread: 75, duration: 1.3)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .scaleEffect(isPicked ? 1.08 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isPicked)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canTap)
        .opacity(
            isPicked ? 1.0 :
            isOther ? 0.22 :
            canPick(face) ? (isAnimating ? 0.85 : 1.0) :
            0.5
        )
        .animation(.easeOut(duration: 0.25), value: pickingFace)
    }

    private func handlePick(_ face: Face) {
        guard !isAnimating, pickingFace == nil, canPick(face) else { return }
        GameSFX.shared.playConfirm()
        if reduceMotion {
            onPick(face)
            return
        }
        pickingFace = face
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            onPick(face)
            pickingFace = nil
        }
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
            if face == .coin {
                ShellGlyph(size: 20)
            } else {
                Text(faceText(face))
                    .font(.avenir(14, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
            }
        }
        .frame(width: 26, height: 26)
        .opacity(0.75)
    }

    @ViewBuilder
    private func coinGlyph(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.gold)
                .overlay(
                    Circle().strokeBorder(Color.treasureInk, lineWidth: 1.5)
                )
            Circle()
                .strokeBorder(Color.coinGoldLight.opacity(0.7), lineWidth: 1)
                .padding(3)
        }
        .frame(width: size, height: size)
    }

    private func faceText(_ f: Face) -> String {
        f == .coin ? "C" : "\(f.rawValue)"
    }
}
