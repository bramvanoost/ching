import SwiftUI
import UIKit

extension Color {
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)
            : UIColor(red: 250/255, green: 248/255, blue: 243/255, alpha: 1)
    })

    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 250/255, green: 248/255, blue: 243/255, alpha: 1)
            : UIColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)
    })

    static let dimInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 154/255, green: 154/255, blue: 154/255, alpha: 1)
            : UIColor(red: 107/255, green: 107/255, blue: 107/255, alpha: 1)
    })
}

extension Font {
    static func cochin(_ size: CGFloat) -> Font {
        .custom("Cochin", size: size)
    }

    static func cochinItalic(_ size: CGFloat) -> Font {
        .custom("Cochin-Italic", size: size)
    }

    static func bodoni(_ size: CGFloat) -> Font {
        .custom("BodoniSvtyTwoITCTT-Book", size: size)
    }

    static func bodoniItalic(_ size: CGFloat) -> Font {
        .custom("BodoniSvtyTwoITCTT-BookIta", size: size)
    }
}

struct StampShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: Color.ink, radius: 0, x: 2, y: 2)
    }
}

extension View {
    func stampShadow() -> some View {
        modifier(StampShadowModifier())
    }
}

struct StampButtonStyle: ButtonStyle {
    var primary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodoni(16))
            .textCase(.uppercase)
            .tracking(2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .foregroundStyle(primary ? Color.paper : Color.ink)
            .background(primary ? Color.ink : Color.paper)
            .overlay(
                Rectangle().strokeBorder(Color.ink, lineWidth: 1.5)
            )
            .stampShadow()
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

extension View {
    func stampButton(primary: Bool = false) -> some View {
        self.buttonStyle(StampButtonStyle(primary: primary))
    }
}
