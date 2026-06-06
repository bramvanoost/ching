import SwiftUI

/// Golden-hour Balearic backdrop. Sky gradient + distant headland, sea band,
/// dune, and a couple of palm silhouettes. Used by every screen so all the
/// foreground chrome floats on the same atmosphere.
struct Background: View {
    var body: some View {
        ZStack {
            // Sky gradient
            LinearGradient(
                stops: [
                    .init(color: .skyTop, location: 0.0),
                    .init(color: .skyMid, location: 0.35),
                    .init(color: .skyLavender, location: 0.70),
                    .init(color: .skyPlum, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Distant beach silhouette anchored near the bottom edge so the
            // top 2/3 of the screen stays clear for UI.
            GeometryReader { geo in
                BeachScene(horizonY: geo.size.height - 130)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black, location: 0.55),
                                .init(color: .black, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// Layered beach: far headland on the horizon, narrow sea band, lonely
/// sailboat, foreground dune with two palm silhouettes planted in it.
private struct BeachScene: View {
    let horizonY: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let groundHeight = max(h - horizonY, 130)

            ZStack(alignment: .topLeading) {
                // Far headland — distant rolling hills hugging the horizon.
                FarHeadland(width: w)
                    .opacity(0.38)
                    .offset(y: horizonY - 18)

                // Sea band — thin cooler strip below the horizon.
                SeaBand(width: w)
                    .offset(y: horizonY)

                // Sailboat — tiny lateen sail catching the last light.
                Sailboat()
                    .opacity(0.55)
                    .offset(x: w * 0.62, y: horizonY - 11)

                // Dune — wavy foreground hill filling everything below
                // the horizon line.
                Dune(width: w, height: groundHeight)
                    .offset(y: horizonY)

                // Foreground palms — taller one leans gently inland on
                // the left, smaller cousin on the right.
                Palm(height: 110, leanDegrees: -8)
                    .frame(width: 140, height: 110)
                    .offset(x: w * 0.16 - 70, y: horizonY - 66)

                Palm(height: 84, leanDegrees: 10)
                    .frame(width: 116, height: 84)
                    .offset(x: w * 0.76 - 58, y: horizonY - 46)
            }
        }
    }
}

/// Far headland: low rolling silhouette right on the horizon line.
private struct FarHeadland: View {
    let width: CGFloat

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 18))
            p.addCurve(
                to: CGPoint(x: width * 0.32, y: 4),
                control1: CGPoint(x: width * 0.10, y: 16),
                control2: CGPoint(x: width * 0.22, y: 2)
            )
            p.addCurve(
                to: CGPoint(x: width * 0.68, y: 9),
                control1: CGPoint(x: width * 0.46, y: 10),
                control2: CGPoint(x: width * 0.58, y: 16)
            )
            p.addCurve(
                to: CGPoint(x: width, y: 14),
                control1: CGPoint(x: width * 0.82, y: 2),
                control2: CGPoint(x: width * 0.92, y: 8)
            )
            p.addLine(to: CGPoint(x: width, y: 22))
            p.addLine(to: CGPoint(x: 0, y: 22))
            p.closeSubpath()
        }
        .fill(Color.citySilhouette)
        .frame(height: 22)
    }
}

/// Sea band: ~8pt strip where the water meets the shore. Slight cool wash
/// over the sky color so it reads as water, not a stripe.
private struct SeaBand: View {
    let width: CGFloat

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.skyLavender.opacity(0.55),
                        Color.skyMid.opacity(0.25)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width, height: 8)
    }
}

/// Tiny lateen sailboat triangle on the horizon.
private struct Sailboat: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 4, y: 0))
            p.addLine(to: CGPoint(x: 4, y: 11))
            p.addLine(to: CGPoint(x: 0, y: 11))
            p.closeSubpath()
            p.move(to: CGPoint(x: 4.6, y: 1))
            p.addLine(to: CGPoint(x: 9, y: 11))
            p.addLine(to: CGPoint(x: 4.6, y: 11))
            p.closeSubpath()
        }
        .fill(Color.citySilhouette)
        .frame(width: 9, height: 12)
    }
}

/// Dune: wavy foreground hill from horizon to bottom edge. Subtle gradient
/// fade from crest to base so the foreground doesn't read as a flat slab.
private struct Dune: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 28))
                p.addCurve(
                    to: CGPoint(x: width * 0.42, y: 6),
                    control1: CGPoint(x: width * 0.14, y: 20),
                    control2: CGPoint(x: width * 0.28, y: 2)
                )
                p.addCurve(
                    to: CGPoint(x: width, y: 34),
                    control1: CGPoint(x: width * 0.62, y: 12),
                    control2: CGPoint(x: width * 0.82, y: 44)
                )
                p.addLine(to: CGPoint(x: width, y: height))
                p.addLine(to: CGPoint(x: 0, y: height))
                p.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        Color.citySilhouette.opacity(0.72),
                        Color.citySilhouette.opacity(0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Lit crest accent — a thin warm line along the top of the dune,
            // catching the last of the sun.
            Path { p in
                p.move(to: CGPoint(x: 0, y: 28))
                p.addCurve(
                    to: CGPoint(x: width * 0.42, y: 6),
                    control1: CGPoint(x: width * 0.14, y: 20),
                    control2: CGPoint(x: width * 0.28, y: 2)
                )
                p.addCurve(
                    to: CGPoint(x: width, y: 34),
                    control1: CGPoint(x: width * 0.62, y: 12),
                    control2: CGPoint(x: width * 0.82, y: 44)
                )
            }
            .stroke(Color.citySilhouetteAccent.opacity(0.7), lineWidth: 1.2)
        }
    }
}

/// Procedural palm silhouette: gently curved trunk + a crown of feathered
/// fronds (each frond = a central spine with leaflets running along both
/// sides, like a real palm). `leanDegrees` tilts the whole tree.
private struct Palm: View {
    var height: CGFloat
    var leanDegrees: Double = 0

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let trunkBaseX = w * 0.5
            let trunkBaseY = h
            let crownY = h * 0.36
            let crownX = trunkBaseX + sin(leanDegrees * .pi / 180) * (h - crownY) * 0.6

            let trunkWidthBase = max(3.5, height / 26)
            let trunkWidthTop = max(2.0, height / 44)
            let silhouette = GraphicsContext.Shading.color(Color.citySilhouette)

            // Trunk
            var trunk = Path()
            trunk.move(to: CGPoint(x: trunkBaseX - trunkWidthBase, y: trunkBaseY))
            trunk.addQuadCurve(
                to: CGPoint(x: crownX - trunkWidthTop, y: crownY),
                control: CGPoint(
                    x: (trunkBaseX + crownX) / 2 - trunkWidthBase * 1.6,
                    y: (trunkBaseY + crownY) / 2
                )
            )
            trunk.addLine(to: CGPoint(x: crownX + trunkWidthTop, y: crownY))
            trunk.addQuadCurve(
                to: CGPoint(x: trunkBaseX + trunkWidthBase, y: trunkBaseY),
                control: CGPoint(
                    x: (trunkBaseX + crownX) / 2 + trunkWidthBase * 0.4,
                    y: (trunkBaseY + crownY) / 2
                )
            )
            trunk.closeSubpath()
            ctx.fill(trunk, with: silhouette)

            // Crown lump — tightens the trunk-to-fronds junction.
            let lumpR = trunkWidthTop * 2
            ctx.fill(
                Path(ellipseIn: CGRect(
                    x: crownX - lumpR,
                    y: crownY - lumpR,
                    width: lumpR * 2,
                    height: lumpR * 2
                )),
                with: silhouette
            )

            // Fronds — feathered compound leaves fanning across the upper
            // hemisphere only.
            let scale = height / 110
            for i in Self.frondAngles.indices {
                drawFrond(
                    ctx: &ctx,
                    crownX: crownX,
                    crownY: crownY,
                    angle: Self.frondAngles[i],
                    length: Self.frondLengths[i] * scale,
                    shading: silhouette,
                    scale: scale
                )
            }
        }
    }

    // Six fronds fanning across the upper hemisphere only — no fronds below
    // the crown so the silhouette never grows "roots".
    private static let frondAngles: [Double] = [-160, -125, -90, -55, -20, 15]
    private static let frondLengths: [CGFloat] = [42, 50, 54, 52, 46, 40]

    private func drawFrond(
        ctx: inout GraphicsContext,
        crownX: CGFloat,
        crownY: CGFloat,
        angle: Double,
        length: CGFloat,
        shading: GraphicsContext.Shading,
        scale: CGFloat
    ) {
        let rad = angle * .pi / 180
        let horizontality = abs(cos(rad))
        let droop = length * 0.34 * horizontality + 4

        // Straight tip, plus a vertical droop applied at the end.
        let tipX = crownX + cos(rad) * length
        let tipY = crownY + sin(rad) * length + droop

        // Quadratic Bezier: control point pulls the belly downward so the
        // spine curves like a hanging frond rather than a rigid spike.
        let ctrlX = (crownX + tipX) / 2
        let ctrlY = (crownY + tipY) / 2 + droop * 0.5

        // Central spine — thin filled taper from crown to tip.
        let spineHalf = max(1.0, 1.4 * scale)
        let perpAtBaseX = -sin(rad) * spineHalf
        let perpAtBaseY = cos(rad) * spineHalf
        var spine = Path()
        spine.move(to: CGPoint(x: crownX - perpAtBaseX, y: crownY - perpAtBaseY))
        spine.addQuadCurve(
            to: CGPoint(x: tipX, y: tipY),
            control: CGPoint(x: ctrlX - perpAtBaseX * 0.4, y: ctrlY - perpAtBaseY * 0.4)
        )
        spine.addQuadCurve(
            to: CGPoint(x: crownX + perpAtBaseX, y: crownY + perpAtBaseY),
            control: CGPoint(x: ctrlX + perpAtBaseX * 0.4, y: ctrlY + perpAtBaseY * 0.4)
        )
        spine.closeSubpath()
        ctx.fill(spine, with: shading)

        // Leaflets — short strokes perpendicular to the spine tangent,
        // one bundle on each side at every t. Length tapers toward the tip.
        let leafletCount = 11
        let baseLeafletLength: CGFloat = 9 * scale
        for i in 1...leafletCount {
            let t = Double(i) / Double(leafletCount + 1)

            // Point on the spine at parameter t.
            let oneMinusT = 1 - t
            let bx = oneMinusT * oneMinusT * crownX
                  + 2 * oneMinusT * t * ctrlX
                  + t * t * tipX
            let by = oneMinusT * oneMinusT * crownY
                  + 2 * oneMinusT * t * ctrlY
                  + t * t * tipY

            // Tangent at t (derivative of the quad Bezier).
            let tx = 2 * oneMinusT * (ctrlX - crownX) + 2 * t * (tipX - ctrlX)
            let ty = 2 * oneMinusT * (ctrlY - crownY) + 2 * t * (tipY - ctrlY)
            let tangentLen = max(0.001, sqrt(tx * tx + ty * ty))
            let perpX = -ty / tangentLen
            let perpY = tx / tangentLen

            // Leaflets shorten as we approach the tip, never below 35%.
            let leafletLen = baseLeafletLength * (1 - t * 0.55)

            // Top leaflet
            let topEndX = bx + perpX * leafletLen
            let topEndY = by + perpY * leafletLen + 1.0
            var topLeaf = Path()
            topLeaf.move(to: CGPoint(x: bx, y: by))
            topLeaf.addQuadCurve(
                to: CGPoint(x: topEndX, y: topEndY),
                control: CGPoint(
                    x: (bx + topEndX) / 2 + perpX * 0.5,
                    y: (by + topEndY) / 2 + 1.0
                )
            )
            ctx.stroke(
                topLeaf,
                with: shading,
                style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round)
            )

            // Bottom leaflet (other side of spine, droops slightly more).
            let botEndX = bx - perpX * leafletLen
            let botEndY = by - perpY * leafletLen + 2.0
            var botLeaf = Path()
            botLeaf.move(to: CGPoint(x: bx, y: by))
            botLeaf.addQuadCurve(
                to: CGPoint(x: botEndX, y: botEndY),
                control: CGPoint(
                    x: (bx + botEndX) / 2 - perpX * 0.5,
                    y: (by + botEndY) / 2 + 2.0
                )
            )
            ctx.stroke(
                botLeaf,
                with: shading,
                style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round)
            )
        }
    }
}

#Preview {
    Background()
}
