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
    // Bank is anchored to the sum — tap the big number to bank it. Keeps the
    // bottom action bar a single position-stable Roll button so a thumb
    // resting on Roll never accidentally banks the turn.
    var canBank: Bool = false
    var bankPreview: String = ""
    var onBank: () -> Void = {}
    var reduceMotion: Bool = false

    // Source of truth for what the dice slot renders. Updated by the roll
    // animation in steps so the player never sees the final `rolled` values
    // pop in before the cycle starts.
    @SwiftUI.State private var displayedRolled: [Face] = []
    @SwiftUI.State private var rollAnimationTask: Task<Void, Never>?
    @SwiftUI.State private var isAnimating: Bool = false
    @SwiftUI.State private var pickSparkleTrigger: Int = 0
    @SwiftUI.State private var lastSum: Int = -1
    @SwiftUI.State private var pickingFace: Face?

    private var displayRolled: [Face] {
        displayedRolled
    }

    var body: some View {
        VStack(spacing: 6) {
            // Phase hint — fixed height, always present. Keep the source
            // casing (the strings already read in sentence case).
            Text(phaseHint)
                .font(.avenir(14, weight: .medium, italic: true))
                .foregroundStyle(Color.ink.opacity(0.78))
                .frame(height: 18)

            // Hero number — the running sum. When canBank is true, the
            // whole thing wraps in a stamped card: thin coral border, hard
            // offset shadow, "tap to bank" label below the number. Reads as
            // a button at a glance even before you spot the wink.
            ZStack {
                Button {
                    guard canBank else { return }
                    onBank()
                } label: {
                    if canBank {
                        // Compact two-tone receipt: cream half holds the
                        // value, coral half is the action footer with the
                        // BANK label in cream stamp text. Width capped so it
                        // doesn't bleed past the app's horizontal rhythm and
                        // sits like a card you can tap, not a banner.
                        VStack(spacing: 0) {
                            Text("\(setAsideSum)")
                                .font(.avenir(56, weight: .demiBold, italic: true))
                                .foregroundStyle(Color.ink)
                                    .shadow(color: Color.ink.opacity(0.22), radius: 0, x: 2, y: 3)
                                .padding(.horizontal, 22)
                                .padding(.top, 6)
                                .padding(.bottom, 4)
                                .frame(maxWidth: .infinity)
                                .background(Color.safePeachLight)

                            HStack(spacing: 6) {
                                Text(bankPreview.uppercased())
                                    .font(.avenir(11, weight: .demiBold))
                                    .tracking(2.5)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(Color.stampText)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                LinearGradient(
                                    colors: [Color.coralLight, Color.coral, Color.coralDark],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                        .frame(maxWidth: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.coralDark.opacity(0.5), lineWidth: 1)
                        )
                        .shadow(color: Color.coralDark.opacity(0.25), radius: 12, x: 0, y: 6)
                        .contentShape(Rectangle())
                    } else {
                        // Bare hero number — same treatment we've always had.
                        Text("\(setAsideSum)")
                            .font(.avenir(70, weight: .demiBold, italic: true))
                            .foregroundStyle(Color.ink)
                            .shadow(color: Color.ink.opacity(0.28), radius: 0, x: 2, y: 3)
                            .shadow(color: Color.ink.opacity(0.12), radius: 10, x: 0, y: 0)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canBank)

                if pickSparkleTrigger > 0 {
                    SparkleField(count: 50, startRadius: 50, spread: 90, duration: 1.0)
                        .frame(width: 220, height: 160)
                        .id(pickSparkleTrigger)
                }
            }
            // Always reserve room for the stamped card so the layout doesn't
            // reflow when canBank flips on/off mid-turn.
            .frame(height: 108)

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
        .onChange(of: rolled, initial: true) { oldValue, newValue in
            let isFreshRoll = oldValue.isEmpty && !newValue.isEmpty
            rollAnimationTask?.cancel()
            if isFreshRoll && !reduceMotion {
                isAnimating = true
                rollAnimationTask = Task { @MainActor in
                    defer {
                        isAnimating = false
                        rollAnimationTask = nil
                    }
                    let pool: [Face] = [.one, .two, .three, .four, .five, .coin]
                    let frames = 5
                    let frameNs: UInt64 = 80_000_000
                    for _ in 0..<frames {
                        if Task.isCancelled { return }
                        if isHumanTurn { GameSFX.shared.playRoll() }
                        displayedRolled = (0..<newValue.count).map { _ in pool.randomElement()! }
                        try? await Task.sleep(nanoseconds: frameNs)
                    }
                    if !Task.isCancelled {
                        displayedRolled = newValue
                    }
                }
            } else {
                if isFreshRoll, reduceMotion, isHumanTurn {
                    GameSFX.shared.playRoll()
                }
                isAnimating = false
                displayedRolled = newValue
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
                    ShellMedallion(size: 36)
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
                ShellMedallion(size: 22)
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
