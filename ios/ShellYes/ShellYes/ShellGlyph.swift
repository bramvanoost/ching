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

            // Seven lobes. Dome is a true half-circle (no stretching),
            // and the "butt" at the bottom — a pronounced umbo flap —
            // adds enough height to balance the overall silhouette.
            let bumps = 7
            let fluteAmp: Double = 0.07
            let umboRatio: Double = 0.55  // umbo height as fraction of rx

            // Width: dome width = 2·rx·(1+fluteAmp).
            // Height: dome (rx · (1+fluteAmp)) + umbo (rx · umboRatio).
            let rxByW = (w - 4) / (2.0 * (1 + fluteAmp))
            let rxByH = (h - 4) / ((1 + fluteAmp) + umboRatio)
            let rx = min(rxByW, rxByH)
            let ry = rx
            let umboHalfWidth = rx * 0.28
            let umboHeight = rx * umboRatio

            // Hinge sits near the bottom so the umbo tip lands a couple
            // of points above the canvas edge.
            let hinge = CGPoint(x: w / 2, y: h - umboHeight - 2)

            let steps = bumps * 14

            let outline = Path { p in
                for s in 0...steps {
                    let t = Double(s) / Double(steps)
                    let deg = 180.0 + 180.0 * t
                    let rad = deg * .pi / 180.0
                    let wobble = sin(t * Double(bumps) * .pi * 2) * fluteAmp
                    let rxFlute = Double(rx) * (1 + wobble)
                    let ryFlute = Double(ry) * (1 + wobble)
                    let x = Double(hinge.x) + cos(rad) * rxFlute
                    let y = Double(hinge.y) + sin(rad) * ryFlute
                    if s == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else      { p.addLine(to: CGPoint(x: x, y: y)) }
                }

                // Bottom: flat in, umbo curve, flat back.
                p.addLine(to: CGPoint(x: hinge.x + umboHalfWidth, y: hinge.y))
                p.addQuadCurve(
                    to: CGPoint(x: hinge.x - umboHalfWidth, y: hinge.y),
                    control: CGPoint(x: hinge.x, y: hinge.y + umboHeight * 2)
                )
                p.closeSubpath()
            }

            let bbox = outline.boundingRect
            ctx.fill(
                outline,
                with: .linearGradient(
                    Gradient(colors: [fillTop, fillBottom]),
                    startPoint: CGPoint(x: bbox.midX, y: bbox.minY),
                    endPoint: CGPoint(x: bbox.midX, y: bbox.maxY)
                )
            )

            ctx.stroke(outline, with: .color(stroke), lineWidth: ridgeWidth)

            if showRidges && size >= 14 {
                let insetX = rx * 0.14
                let insetY = ry * 0.14
                let reachX = rx * 0.88
                let reachY = ry * 0.88
                for i in 1..<bumps {
                    let t = Double(i) / Double(bumps)
                    let deg = 180.0 + 180.0 * t
                    let rad = deg * .pi / 180.0
                    var line = Path()
                    line.move(to: CGPoint(
                        x: Double(hinge.x) + cos(rad) * Double(insetX),
                        y: Double(hinge.y) + sin(rad) * Double(insetY)
                    ))
                    line.addLine(to: CGPoint(
                        x: Double(hinge.x) + cos(rad) * Double(reachX),
                        y: Double(hinge.y) + sin(rad) * Double(reachY)
                    ))
                    ctx.stroke(line, with: .color(stroke.opacity(0.32)), lineWidth: ridgeWidth * 0.65)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// The brand icon: scallop shell with three pearl cutouts and lobe
/// detail, all baked into a single SVG ("ShellIcon"). Golden pearls
/// sit behind the icon, peeking through the cutouts. A top-edge
/// highlight and bottom-edge shadow give the shell rim dimension.
struct ShellMedallion: View {
    var size: CGFloat
    var pearlHighlight: Color = .pearlHighlight
    var pearlCore: Color = .pearlCore
    var pearlEdge: Color = .pearlEdge
    var pearlGlow: Color = .pearlGlow

    // SVG pearl geometry (viewBox 800×800):
    // centers y = 558.21 → 0.6978; x = 297.67 / 399.62 / 501.58 → 0.3721 / 0.4995 / 0.6270
    // radius = 40 → 0.05 (diameter 0.10)
    private let pearlCentersX: [CGFloat] = [0.3721, 0.4995, 0.6270]
    private let pearlCenterY: CGFloat = 0.6978
    private var pearlDiameter: CGFloat { size * 0.105 }

    var body: some View {
        ZStack {
            // Pearls behind, aligned to the SVG holes. Slightly oversized
            // so the icon's rim covers any sub-pixel edge.
            ForEach(pearlCentersX, id: \.self) { cx in
                Pearl(
                    diameter: pearlDiameter,
                    highlight: pearlHighlight,
                    core: pearlCore,
                    edge: pearlEdge,
                    glow: pearlGlow
                )
                    .offset(
                        x: size * (cx - 0.5),
                        y: size * (pearlCenterY - 0.5)
                    )
            }

            // Shell silhouette with peach gradient.
            Image("ShellIcon")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.pearlHighlight, Color.safePeachDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                // Top sheen + bottom depth, masked to the shell shape.
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.45), location: 0.0),
                            .init(color: .white.opacity(0.08), location: 0.18),
                            .init(color: .clear, location: 0.42),
                            .init(color: .clear, location: 0.62),
                            .init(color: Color.treasureInk.opacity(0.18), location: 0.92),
                            .init(color: Color.treasureInk.opacity(0.35), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .mask(
                        Image("ShellIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    )
                )
                // Soft inner highlight in the upper-left quadrant.
                .overlay(
                    RadialGradient(
                        colors: [.white.opacity(0.35), .clear],
                        center: UnitPoint(x: 0.38, y: 0.22),
                        startRadius: 0,
                        endRadius: size * 0.32
                    )
                    .mask(
                        Image("ShellIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    )
                    .blendMode(.plusLighter)
                )
                .shadow(color: Color.treasureInk.opacity(0.35), radius: max(1, size / 40), x: 0, y: max(1, size / 60))
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
