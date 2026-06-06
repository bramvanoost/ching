import SwiftUI

/// Procedural scallop shell — replaces the coin glyph everywhere.
/// Scales cleanly from a 5pt tile pip up to a 90pt hero on the bust /
/// ceremony screens.
///
/// Shape model: hinge at bottom-center. Fan sweeps from 195° through
/// 270° (straight up) to 345°, giving a ~1.9:1 width:height scallop.
/// A radial wobble on the rim gives the fluted edge; radial ridges
/// add interior detail when the size is big enough to read them.
struct ShellGlyph: View {
    var size: CGFloat
    var fillTop: Color = .coinGoldLight
    var fillBottom: Color = .gold
    var stroke: Color = .treasureInk
    var showRidges: Bool = true

    private var ridgeWidth: CGFloat {
        max(0.7, size / 28)
    }

    var body: some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            // Hinge sits about 80% down — the shell domes up from a narrow
            // base instead of hanging from the bottom edge, so it reads
            // higher in its frame.
            let hinge = CGPoint(x: w / 2, y: h * 0.80)
            // Arc sweep is narrower than before (210°→330°, ~120° total).
            // That makes the silhouette closer to a dome than a wide fan:
            // width:height ≈ 1.7:1 instead of 1.9:1.
            let startDeg: Double = 210
            let endDeg: Double = 330
            // cos(210°) = -0.866 — width-half per unit radius. Radius is the
            // smaller of "fit the width" or "reach the top" so we never clip.
            let r = min(h * 0.78, (w / 2) / 0.866)

            let bumps = 7
            let steps = bumps * 8

            // Outline: hinge → walk the fluted rim → hinge.
            let outline = Path { p in
                p.move(to: hinge)
                for s in 0...steps {
                    let t = Double(s) / Double(steps)
                    let deg = startDeg + (endDeg - startDeg) * t
                    let rad = deg * .pi / 180.0
                    // Fluted wobble: positive on the rim peaks, negative in the troughs.
                    let wobble = sin(t * Double(bumps) * .pi * 2) * Double(r) * 0.06
                    let radius = Double(r) + wobble
                    let x = Double(hinge.x) + cos(rad) * radius
                    let y = Double(hinge.y) + sin(rad) * radius
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.closeSubpath()
            }

            // Body fill — top-to-bottom warm gradient.
            let bbox = outline.boundingRect
            ctx.fill(
                outline,
                with: .linearGradient(
                    Gradient(colors: [fillTop, fillBottom]),
                    startPoint: CGPoint(x: bbox.midX, y: bbox.minY),
                    endPoint: CGPoint(x: bbox.midX, y: bbox.maxY)
                )
            )

            // Outline stroke
            ctx.stroke(outline, with: .color(stroke), lineWidth: ridgeWidth)

            // Radial ridges, one per scallop, from just above the hinge
            // out to the rim. Skip when the glyph is tiny (won't read).
            if showRidges && size >= 14 {
                let inset = r * 0.18
                let reach = r * 0.92
                for i in 1..<bumps {
                    let t = Double(i) / Double(bumps)
                    let deg = startDeg + (endDeg - startDeg) * t
                    let rad = deg * .pi / 180.0
                    var line = Path()
                    line.move(to: CGPoint(
                        x: Double(hinge.x) + cos(rad) * Double(inset),
                        y: Double(hinge.y) + sin(rad) * Double(inset)
                    ))
                    line.addLine(to: CGPoint(
                        x: Double(hinge.x) + cos(rad) * Double(reach),
                        y: Double(hinge.y) + sin(rad) * Double(reach)
                    ))
                    ctx.stroke(line, with: .color(stroke.opacity(0.5)), lineWidth: ridgeWidth * 0.7)
                }
            }

            // Hinge dot
            let dot = Path(ellipseIn: CGRect(
                x: Double(hinge.x) - Double(ridgeWidth) * 1.4,
                y: Double(hinge.y) - Double(ridgeWidth) * 1.4,
                width: Double(ridgeWidth) * 2.8,
                height: Double(ridgeWidth) * 2.8
            ))
            ctx.fill(dot, with: .color(stroke))
        }
        .frame(width: size, height: size * 0.92)
    }
}

/// A gold coin with a shell engraved on it. Used everywhere the original
/// gold-disc coin lived — dice "coin" face, splash hero, ceremony totals.
/// The shell is drawn with no body fill so the gold field shows through,
/// and stroked in treasure ink so it reads like a mint stamp.
struct ShellMedallion: View {
    var size: CGFloat
    var shellScale: CGFloat = 0.66

    var body: some View {
        ZStack {
            // Coin body
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.coinGoldLight, Color.gold],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .overlay(
                    Circle().strokeBorder(Color.treasureInk, lineWidth: max(1, size / 28))
                )

            // Inner highlight ring
            Circle()
                .strokeBorder(Color.coinGoldLight.opacity(0.7), lineWidth: max(0.8, size / 40))
                .padding(size * 0.1)

            // Shell in relief — body fill brighter than the coin, plus a
            // soft cast shadow so it reads as raised off the surface
            // rather than carved into it. Ridges stay treasure-ink so
            // they read as grooves between raised facets.
            ShellGlyph(
                size: size * shellScale,
                fillTop: Color.shellHighlight,
                fillBottom: Color.coinGoldLight,
                stroke: Color.treasureInk.opacity(0.55),
                showRidges: true
            )
            .shadow(color: Color.treasureInk.opacity(0.45), radius: max(1.5, size / 36), x: 0, y: max(1.5, size / 50))
            // Lift so the shell's optical center sits above the coin's
            // geometric center — the hinge naturally falls lower than the
            // shell's visual mass.
            .offset(y: -size * 0.07)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    ZStack {
        Color.skyMid.ignoresSafeArea()
        VStack(spacing: 24) {
            HStack(alignment: .bottom, spacing: 16) {
                ShellGlyph(size: 12)
                ShellGlyph(size: 28)
                ShellGlyph(size: 60)
            }
            HStack(alignment: .bottom, spacing: 16) {
                ShellMedallion(size: 28)
                ShellMedallion(size: 48)
                ShellMedallion(size: 90)
                ShellMedallion(size: 120)
            }
        }
    }
}
