import SwiftUI
import ShellYesEngine

struct VaultStack: View {
    let safes: [Int]
    var activeSeat: Bool = false

    @SwiftUI.State private var addSparkleTrigger: Int = 0

    private let safeWidth: CGFloat = 38
    private let safeHeight: CGFloat = 38
    private let layerOffset: CGFloat = 5
    /// Hard cap on visible shells. Above this, the stack would overflow
    /// the scoreboard column. Older shells beyond the cap are kept in
    /// state but hidden — the textual count below the stack tells the
    /// player how many they actually hold.
    private let maxVisible: Int = 4

    private var visibleCount: Int { min(safes.count, maxVisible) }

    private var stackHeight: CGFloat {
        if safes.isEmpty { return 36 }
        return safeHeight + CGFloat(max(0, visibleCount - 1)) * layerOffset
    }

    /// Newest first, capped at `maxVisible`. Engine stores newest at end
    /// of `tiles`, so reverse and take the prefix.
    private var stackedNewestFirst: [Int] {
        Array(safes.reversed().prefix(maxVisible))
    }

    var body: some View {
        // Always render — keeps view identity (and `addSparkleTrigger`
        // state) stable across the empty → non-empty boundary. If we
        // swapped to EmptyView when empty, the first stolen tile would
        // create a fresh VaultStack whose ForEach element is "initial"
        // rather than "inserted", and onChange wouldn't fire — no
        // sparkle, no scale-in.
        ZStack(alignment: .top) {
            // Key by tile value, not array offset. Tiles 21–36 are
            // unique within a game, so each shell's view identity
            // stays stable across count changes — the removed shell
            // is the one that animates out, instead of every shell
            // re-rendering with a shifted value (which flickered
            // the strokes / pearls).
            ForEach(Array(stackedNewestFirst.enumerated()), id: \.element) { idx, safe in
                safeView(value: safe)
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
                            insertion: .scale(scale: 0.15)
                                .combined(with: .opacity)
                                .animation(.spring(response: 0.55, dampingFraction: 0.6)),
                            removal: .opacity.animation(.easeOut(duration: 0.28))
                          )
                        : .opacity
                    )
            }
        }
        .frame(width: safeWidth, height: stackHeight, alignment: .top)
        // Layout (height) change uses a calm easeOut so removals
        // don't overshoot — the springy "pop" is reserved for the
        // insertion transition above, where it reads as celebration
        // rather than the stack settling after a loss.
        .animation(.easeOut(duration: 0.32), value: safes.count)
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

    @ViewBuilder
    private func safeView(value: Int) -> some View {
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

            // Content renders unconditionally. Lower shells in the stack
            // are already z-occluded by the top card (zIndex is set on
            // the parent ForEach), so their text/pearls stay hidden
            // without needing an opacity gate. Previously this used
            // `.opacity(isTop ? 1 : 0)` to swap content cleanly on a
            // steal, but that gate animated 0→1 on the new top after
            // the old top was removed, reading as a pearl/stroke blink.
            // With the opacity gate gone, the new top is just naturally
            // revealed as the old top's removal transition fades it out.
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.avenir(13, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
                PearlRow(count: GameStore.safeCoins(value), diameter: 4, spacing: 1.5)
            }
        }
        .frame(width: safeWidth, height: safeHeight)
    }
}
