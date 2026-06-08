import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// 1024×1024 app icon: full sunset sky behind a glowing shell
/// medallion with sun rays radiating from behind it. Same world as
/// the splash screen but turned up — dusky lavender at the top,
/// gold-peach in the middle, coral at the horizon, with twelve light
/// rays fanning out from the shell.
struct AppIconView: View {
    /// 12 evenly-spaced rays as an angular gradient. Bright/clear
    /// stops alternate so the interpolation produces soft beams
    /// rather than hard bars.
    private var rayStops: [Gradient.Stop] {
        let count = 24
        return (0..<count).map { i in
            let location = Double(i) / Double(count)
            let bright = i.isMultiple(of: 2)
            return Gradient.Stop(
                color: bright ? Color.coinGoldLight.opacity(0.22) : .clear,
                location: location
            )
        }
    }

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

            // Sun rays — angular sweep around the centre, masked to a
            // ring so they emerge from behind the shell and dissipate
            // toward the icon edges. Rotated 7.5° so no ray points
            // straight down through the medallion's axis.
            AngularGradient(
                gradient: Gradient(stops: rayStops),
                center: .center,
                angle: .degrees(7.5)
            )
            .blendMode(.softLight)
            .mask(
                RadialGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.5), location: 0.35),
                        .init(color: .black.opacity(0.35), location: 0.65),
                        .init(color: .clear, location: 0.95),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 620
                )
            )

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

#Preview {
    AppIconView()
        .scaleEffect(0.3)
}
