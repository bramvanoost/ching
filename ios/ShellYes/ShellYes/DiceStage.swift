import SwiftUI
import ShellYesEngine

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
    var isSteal: Bool = false
    var onBank: () -> Void = {}
    /// Player labels indexed by seat — used to name the steal target in
    /// the chooseBank UI ("Steal Marina's 26"). Empty array means the
    /// caller hasn't wired it; the chooser falls back to "rival N".
    var playerNames: [String] = []
    /// When non-empty, the dice slot is replaced by a two-button chooser
    /// driving `onChoose`. Engine is in `.chooseBank` phase: the player
    /// must pick a target before the turn advances.
    var bankChoices: [BankOption] = []
    var onChoose: (BankOption) -> Void = { _ in }
    var reduceMotion: Bool = false
    var speedFactor: Double = 1.0
    /// When true, roll SFX plays regardless of whose turn it technically
    /// is. Used for the fake post-bust roll animation, where the engine
    /// has already advanced the turn but the player still needs to hear
    /// the dice land before the flash arrives.
    var forceRollSound: Bool = false

    // Source of truth for what the dice slot renders. Updated by the roll
    // animation in steps so the player never sees the final `rolled` values
    // pop in before the cycle starts.
    @SwiftUI.State private var displayedRolled: [Face] = []
    @SwiftUI.State private var rollAnimationTask: Task<Void, Never>?
    @SwiftUI.State private var isAnimating: Bool = false
    @SwiftUI.State private var pickSparkleTrigger: Int = 0
    @SwiftUI.State private var bankSparkleTrigger: Int = 0
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
                .padding(.bottom, 10)

            // Hero number — the running sum. When canBank is true, the
            // whole thing wraps in a stamped card: thin coral border, hard
            // offset shadow, "tap to bank" label below the number. Reads as
            // a button at a glance even before you spot the wink.
            ZStack {
                Button {
                    guard canBank else { return }
                    bankSparkleTrigger += 1
                    // Fire the bank synchronously so the success sound
                    // and event banner land on the same frame as the
                    // tap. The sparkles run in parallel; the modal
                    // takes over the dice area immediately after.
                    onBank()
                } label: {
                    if canBank {
                        // Receipt-style card: cream body holds the running
                        // sum, with a rounded gradient button mounted into
                        // it for the action. Gradient starts at coralLight
                        // (no coinGoldLight at top) so the button edge is
                        // distinct against the cream around it.
                        VStack(spacing: 8) {
                            Text("\(setAsideSum)")
                                .font(.avenir(56, weight: .demiBold))
                                .foregroundStyle(Color.treasureInk)
                                .shadow(color: Color.treasureInk.opacity(0.22), radius: 0, x: 2, y: 3)
                                .padding(.horizontal, 22)
                                .padding(.top, 6)
                                .frame(maxWidth: .infinity)

                            HStack(spacing: 6) {
                                Text(bankPreview.uppercased())
                                    .font(.avenir(11, weight: .demiBold))
                                    .tracking(2.5)
                                Image(systemName: isSteal ? "hand.point.up.fill" : "arrow.right")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(Color.stampText)
                            .padding(.vertical, isSteal ? 11 : 7)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                // Bottom corners match the card's 12pt
                                // outer radius so the button sits flush;
                                // top corners are the visible "button"
                                // cue against the cream above it.
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 10,
                                    bottomLeadingRadius: 12,
                                    bottomTrailingRadius: 12,
                                    topTrailingRadius: 10
                                )
                                .fill(
                                    // Warm gold at the top, settling into
                                    // coral. No coralDark — the deep rose
                                    // is what made the previous gradient
                                    // feel harsh against the cream above.
                                    LinearGradient(
                                        colors: [Color.coinGoldLight, Color.coralLight, Color.coral],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            )
                        }
                        .frame(maxWidth: isSteal ? 280 : 200)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.safePeachLight)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(isSteal ? Color.coralDark : Color.coralDark.opacity(0.5), lineWidth: isSteal ? 1.5 : 1)
                        )
                        // Same SparkleField the dice-pick uses, just with
                        // parameters scaled for the bigger card. Radial
                        // burst from center, particles cross every edge
                        // on their way out — the proven look.
                        .overlay {
                            if bankSparkleTrigger > 0 {
                                SparkleField(count: 60, startRadius: 35, spread: 100, duration: 1.0)
                                    .id(bankSparkleTrigger)
                                    .allowsHitTesting(false)
                            }
                        }
                        .shadow(color: Color.coralDark.opacity(isSteal ? 0.45 : 0.25), radius: isSteal ? 16 : 12, x: 0, y: 6)
                        .contentShape(Rectangle())
                    } else {
                        // Bare hero number — same treatment we've always had.
                        Text("\(setAsideSum)")
                            .font(.avenir(70, weight: .demiBold))
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
                if !bankChoices.isEmpty {
                    bankChooser()
                        .padding(.horizontal, 18)
                } else if !displayRolled.isEmpty {
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

            // Tally row — visualises the whole 8-die supply for this turn.
            // Locked dice on the left show face values (committed). Small
            // hollow circles on the right represent dice still in hand.
            // Count is implicit but legible at a glance, and the row width
            // is bounded because hollow dots are tiny — so an 8-die haul
            // never overflows.
            HStack(spacing: 6) {
                ForEach(Array(locked.enumerated()), id: \.offset) { _, face in
                    lockedDie(face: face)
                }
                if !locked.isEmpty && diceInHand > 0 {
                    Color.clear.frame(width: 4, height: 1)
                }
                ForEach(0..<diceInHand, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2.5)
                        .strokeBorder(Color.ink.opacity(0.45), lineWidth: 1.2)
                        .frame(width: 10, height: 10)
                }
            }
            .frame(height: 26)
            .padding(.top, 8)
            .opacity(locked.isEmpty && diceInHand == 0 ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.vertical, 0)
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
                    // Frame schedule. Fast mode keeps a uniform tick. Slow
                    // mode opens with two snappy flips, then the dice clearly
                    // lose momentum — flat start, gradual ramp, long settle.
                    // Slow-mode curve: four quick rattles to read as
                    // "spinning," then a gentle ramp (~1.25×) into a
                    // steady ~1.75× decay so the slowdown unfolds rather
                    // than landing all at once.
                    let frameNs: [UInt64] = speedFactor > 1.0
                        ? [30_000_000, 34_000_000, 40_000_000, 50_000_000, 75_000_000, 130_000_000, 230_000_000, 410_000_000]
                        : Array(repeating: 80_000_000, count: 5)
                    for i in 0..<frameNs.count {
                        if Task.isCancelled { return }
                        if isHumanTurn || forceRollSound { GameSFX.shared.playRoll() }
                        displayedRolled = (0..<newValue.count).map { _ in pool.randomElement()! }
                        try? await Task.sleep(nanoseconds: frameNs[i])
                    }
                    if !Task.isCancelled {
                        if isHumanTurn || forceRollSound { GameSFX.shared.playRoll() }
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
                    Pearl(diameter: 32)
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
            try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * speedFactor))
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
                Pearl(diameter: 18)
            } else {
                Text(faceText(face))
                    .font(.avenir(14, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
            }
        }
        .frame(width: 26, height: 26)
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

    // MARK: - Bank chooser (engine phase .chooseBank)

    @ViewBuilder
    private func bankChooser() -> some View {
        // Two side-by-side cards, one per legal target. Layout mirrors
        // the event-banner shell chip vocabulary so the prize on offer
        // reads as a real shell, not a label.
        HStack(spacing: 12) {
            ForEach(Array(bankChoices.enumerated()), id: \.offset) { _, option in
                bankChoiceCard(option: option)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 158)
    }

    @ViewBuilder
    private func bankChoiceCard(option: BankOption) -> some View {
        let isSteal: Bool = {
            if case .steal = option { return true }
            return false
        }()
        Button {
            GameSFX.shared.playConfirm()
            onChoose(option)
        } label: {
            VStack(spacing: 8) {
                // Two-line header: action verb on top, source below
                // (rival name for steal, "the sand" for centre take).
                VStack(spacing: 0) {
                    Text(isSteal ? "STEAL FROM" : "TAKE FROM")
                        .font(.avenir(11, weight: .demiBold))
                        .tracking(3)
                        .foregroundStyle(isSteal ? Color.stampText : Color.treasureInk.opacity(0.7))
                    Text(bankChoiceSource(option))
                        .font(.avenir(15, weight: .demiBold, italic: true))
                        .foregroundStyle(isSteal ? Color.stampText : Color.treasureInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.top, 2)

                bankChoiceShell(value: option.tile)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        isSteal
                            ? LinearGradient(
                                colors: [Color.coralLight, Color.coral, Color.coralDark],
                                startPoint: .top,
                                endPoint: .bottom
                              )
                            : LinearGradient(
                                colors: [Color.safePeachLight, Color.safePeachDark],
                                startPoint: .top,
                                endPoint: .bottom
                              )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSteal ? Color.coralDark : Color.treasureInk.opacity(0.55), lineWidth: 1.5)
            )
            .shadow(color: Color.coralDark.opacity(isSteal ? 0.5 : 0.18), radius: isSteal ? 16 : 8, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    /// Embedded shell-chip preview of the prize. Same silhouette and
    /// detailing as the event-banner ShellChip, sized down to fit a
    /// choice card next to header copy.
    @ViewBuilder
    private func bankChoiceShell(value: Int) -> some View {
        let coins = GameStore.safeCoins(value)
        ZStack {
            ShellCardShape()
                .fill(
                    LinearGradient(
                        colors: [Color.safePeachLight, Color.safePeachDark],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    ShellCardShape()
                        .strokeBorder(Color.treasureInk, lineWidth: 2)
                )
                .shadow(color: Color.treasureInk.opacity(0.25), radius: 0, x: 0, y: 4)
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.avenir(22, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
                PearlRow(count: coins, diameter: 5, spacing: 2)
            }
        }
        .frame(width: 52, height: 66)
    }

    private func bankChoiceSource(_ option: BankOption) -> String {
        switch option {
        case .steal(let i, _):
            return i < playerNames.count ? playerNames[i] : "Rival \(i + 1)"
        case .center:
            return "the sand"
        }
    }
}
