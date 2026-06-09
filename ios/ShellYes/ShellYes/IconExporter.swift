import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// 1024×1024 app icon: full sunset sky behind a glowing shell
/// medallion with sun rays radiating from behind it. Same world as
/// the splash screen but turned up — dusky lavender at the top,
/// gold-peach in the middle, coral at the horizon, with twelve light
/// rays fanning out from the shell.
struct AppIconView: View {
    var body: some View {
        ZStack {
            // Sundown sky: dusky plum at the top, pink coral through
            // the middle, warm gold-orange at the horizon. Mirrors the
            // classic purple-to-orange dusk arc.
            LinearGradient(
                stops: [
                    .init(color: Color.skyPlum, location: 0.0),
                    .init(color: Color.skyLavender, location: 0.22),
                    .init(color: Color.coralLight, location: 0.55),
                    .init(color: Color.coinGoldLight, location: 0.88),
                    .init(color: Color.coinGoldLight, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Subtle darkening wash over the sky. The dusk gradient
            // alone reads as quite bright at icon size — a touch of
            // plum-tinted shade gives the shell room to glow without
            // washing the colour story out. Kept on the .multiply
            // blend so it tints the existing palette rather than
            // flattening it to grey.
            Color(red: 30/255, green: 14/255, blue: 50/255)
                .opacity(0.22)
                .blendMode(.multiply)

            // Sun rays — 8 discrete tapered capsules rotated around
            // the centre, so no angular-gradient seam can appear.
            // Each capsule has a linear-gradient fill that fades at
            // both tips, reading as a beam of light rather than a
            // solid spoke. .plusLighter blend brightens the dusk sky.
            IconRays()
                .blendMode(.plusLighter)

            // Soft warm bloom behind the shell — a quiet golden glow
            // that lifts the medallion off the sunset without
            // becoming the focal point itself.
            RadialGradient(
                colors: [
                    Color.coinGoldLight.opacity(0.55),
                    Color.coinGoldLight.opacity(0.25),
                    Color.coinGoldLight.opacity(0.0),
                ],
                center: .center,
                startRadius: 0,
                endRadius: 520
            )

            // Brighter, more saturated gold pearls so they pop at
            // home-screen size. In-game pearls stay on the muted
            // pearlescent palette.
            ShellMedallion(
                size: 720,
                pearlHighlight: Color(red: 255/255, green: 240/255, blue: 190/255),
                pearlCore: .coinGoldLight,
                pearlEdge: .gold,
                pearlGlow: .coinGoldLight
            )
        }
        .frame(width: 1024, height: 1024)
    }
}

enum IconExporter {
    /// Writes a 1024×1024 PNG of the app icon to the app's Documents
    /// directory if it isn't already there. Idempotent — safe to call
    /// on every launch in DEBUG builds.
    @MainActor
    static func exportIfNeeded() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("AppIcon-1024.png")
        if FileManager.default.fileExists(atPath: url.path) { return }

        let renderer = ImageRenderer(content: AppIconView())
        renderer.scale = 1.0
        guard let image = renderer.uiImage, let cg = image.cgImage else { return }

        // App Store Connect rejects icons that include an alpha
        // channel, even if every pixel is opaque. Redraw into an
        // RGB-only bitmap context (`.noneSkipLast`) so the encoded
        // PNG has no alpha channel.
        let width = cg.width
        let height = cg.height
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
            | CGImageByteOrderInfo.order32Big.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let opaqueCG = ctx.makeImage() else { return }

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return }
        CGImageDestinationAddImage(dest, opaqueCG, nil)
        guard CGImageDestinationFinalize(dest) else { return }
        print("[IconExporter] wrote \(url.path)")
    }
}

/// Static sunburst rays for the app icon. Eight tapered capsules
/// rotated evenly around the centre. Each capsule is a linear-gradient
/// fill that fades at both tips so the beams read as soft light rather
/// than solid spokes. No animations — this view is rendered by
/// `ImageRenderer` into a PNG at build time.
private struct IconRays: View {
    private let rayCount: Int = 10
    private let innerRadius: CGFloat = 220
    private let outerRadius: CGFloat = 640
    private let baseWidth: CGFloat = 180
    /// Inner end is 22% of the base width (was 8%) so each ray
    /// already has some width where it emerges from behind the shell
    /// instead of starting as a sharp point.
    private let tipScale: CGFloat = 0.22

    var body: some View {
        ZStack {
            ForEach(0..<rayCount, id: \.self) { i in
                TaperedRay(tipScale: tipScale)
                    .fill(
                        // Peak alpha dropped from 0.32 → 0.22 — softer
                        // light overall, complemented by the wider
                        // base + stronger blur.
                        LinearGradient(
                            stops: [
                                .init(color: Color.coinGoldLight.opacity(0.0), location: 0.0),
                                .init(color: Color.coinGoldLight.opacity(0.03), location: 0.15),
                                .init(color: Color.coinGoldLight.opacity(0.12), location: 0.5),
                                .init(color: Color.coinGoldLight.opacity(0.05), location: 0.85),
                                .init(color: Color.coinGoldLight.opacity(0.0), location: 1.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: baseWidth, height: outerRadius - innerRadius)
                    .blur(radius: 20)
                    .offset(y: -(innerRadius + (outerRadius - innerRadius) / 2))
                    // Half-step offset (= 360/rayCount/2) places rays
                    // in mirrored pairs flanking the vertical AND
                    // horizontal axes — full bilateral symmetry with
                    // no single ray pointing straight through the
                    // shell's central crown.
                    .rotationEffect(.degrees(Double(i) / Double(rayCount) * 360 + 180.0 / Double(rayCount)))
            }
        }
        .frame(width: outerRadius * 2, height: outerRadius * 2)
    }
}

/// Tapered trapezoid, oriented so the narrow end sits nearer the
/// icon centre (after the offset+rotation) and the wide end fans
/// out at the outer edge. Reads as a beam of light spreading outward
/// rather than the parallel-sided capsule.
private struct TaperedRay: Shape {
    /// Fraction of `rect.width` used at the narrow (centre) end.
    /// 1.0 = parallel sides, 0 = sharp point at the centre.
    var tipScale: CGFloat

    func path(in rect: CGRect) -> Path {
        let baseHalf = rect.width / 2
        let tipHalf = baseHalf * tipScale
        var path = Path()
        // Wide base at the top (outer end, away from centre after rotation)
        path.move(to: CGPoint(x: rect.midX - baseHalf, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + baseHalf, y: rect.minY))
        // Narrow at the bottom (inner end, near centre)
        path.addLine(to: CGPoint(x: rect.midX + tipHalf, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - tipHalf, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    AppIconView()
        .scaleEffect(0.3)
}
