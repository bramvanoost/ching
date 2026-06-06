import SwiftUI

struct SettingsView: View {
    let settings: SettingsStore
    @SwiftUI.State private var showAbout = false
    @SwiftUI.State private var placeholderOff = false

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.bodoni(28))
                        .foregroundStyle(Color.ink)
                        .padding(.top, 8)

                    SettingsSection(title: "Play") {
                        SettingsRow(title: "Difficulty") {
                            StampSegmented(
                                selection: Binding(
                                    get: { settings.difficulty },
                                    set: { settings.difficulty = $0 }
                                ),
                                options: Difficulty.allCases,
                                labelFor: { $0.rawValue.capitalized }
                            )
                            .frame(maxWidth: 220)
                        }
                    }

                    SettingsSection(title: "Appearance") {
                        SettingsRow(title: "Color mode") {
                            StampSegmented(
                                selection: Binding(
                                    get: { settings.colorMode },
                                    set: { settings.colorMode = $0 }
                                ),
                                options: ColorMode.allCases,
                                labelFor: { $0.rawValue.capitalized }
                            )
                            .frame(maxWidth: 220)
                        }
                        SettingsRow(title: "Reduced motion") {
                            StampToggle(isOn: Binding(
                                get: { settings.reducedMotion },
                                set: { settings.reducedMotion = $0 }
                            ))
                        }
                    }

                    SettingsSection(title: "Feedback") {
                        SettingsRow(title: "Sound", disabled: true) {
                            StampToggle(isOn: $placeholderOff, disabled: true)
                        }
                        SettingsRow(title: "Haptics", disabled: true) {
                            StampToggle(isOn: $placeholderOff, disabled: true)
                        }
                    }

                    SettingsSection(title: "Other") {
                        SettingsRow(title: "Replay tutorial", disabled: true) {
                            Text("tap")
                                .font(.cochinItalic(13))
                                .underline()
                                .foregroundStyle(Color.dimInk)
                        }
                        SettingsRow(title: "Tip jar", disabled: true) {
                            Text("tap")
                                .font(.cochinItalic(13))
                                .underline()
                                .foregroundStyle(Color.dimInk)
                        }
                        Button {
                            showAbout = true
                        } label: {
                            SettingsRow(title: "About") {
                                Text("tap")
                                    .font(.cochinItalic(13))
                                    .underline()
                                    .foregroundStyle(Color.ink)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 40)

                    Text("v0.4 · ching by fastronaut")
                        .font(.cochinItalic(10))
                        .foregroundStyle(Color.dimInk)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showAbout) {
            AboutSheet()
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Color.dimInk)
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.ink).frame(height: 1)
                }
            content()
        }
        .padding(.top, 18)
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    var disabled: Bool = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.cochin(14))
                .foregroundStyle(disabled ? Color.dimInk : Color.ink)
            if disabled {
                Text("soon")
                    .font(.cochinItalic(9))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Color.dimInk)
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 6)
    }
}

private struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("ching!")
                    .font(.bodoniItalic(48))
                    .foregroundStyle(Color.ink)
                Text("A push-your-luck dice game.\nv0.4 — ching by Fastronaut.")
                    .font(.cochin(14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.dimInk)
                Spacer()
                Button("Close") { dismiss() }
                    .stampButton()
                    .frame(maxWidth: 200)
            }
            .padding(40)
        }
    }
}

struct StampSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let labelFor: (T) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { idx in
                let value = options[idx]
                Button {
                    selection = value
                } label: {
                    Text(labelFor(value))
                        .font(.cochin(13))
                        .foregroundStyle(value == selection ? Color.paper : Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(value == selection ? Color.ink : Color.paper)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(labelFor(value)))
                .accessibilityAddTraits(value == selection ? .isSelected : [])

                if idx < options.count - 1 {
                    Rectangle()
                        .fill(Color.ink)
                        .frame(width: 1.5)
                }
            }
        }
        .overlay(
            Rectangle().strokeBorder(Color.ink, lineWidth: 1.5)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct StampToggle: View {
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        Button {
            if !disabled { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle()
                    .fill(Color.paper)
                    .frame(width: 34, height: 20)
                    .overlay(
                        Rectangle()
                            .strokeBorder(disabled ? Color.dimInk : Color.ink, lineWidth: 1.5)
                    )
                Rectangle()
                    .fill(disabled ? Color.dimInk : Color.ink)
                    .frame(width: 14, height: 14)
                    .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Toggle")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(disabled ? [.isStaticText] : [])
    }
}
