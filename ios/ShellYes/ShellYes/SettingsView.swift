import SwiftUI
import ShellYesEngine

/// Reads the version Aptabase reports (CFBundleShortVersionString) so
/// the in-app footer / About screen can't drift out of sync with the
/// dashboard. Bump MARKETING_VERSION in the Xcode project to change it.
enum AppVersion {
    static let short: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }()
}

struct SettingsView: View {
    let settings: SettingsStore
    let stats: StatsStore
    let onNewGame: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.goHome) private var goHome
    @SwiftUI.State private var showAbout = false
    @SwiftUI.State private var showExplainer = false
    @SwiftUI.State private var showRestartConfirm = false
    @SwiftUI.State private var placeholderOff = false

    var body: some View {
        ZStack {
            Background()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("settings")
                        .font(.avenir(34, weight: .ultraLight))
                        .tracking(2)
                        .foregroundStyle(Color.ink)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    glassCard {
                        SettingsSection(title: "play") {
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
                            SettingsRow(title: "Pace") {
                                StampSegmented(
                                    selection: Binding(
                                        get: { settings.gameSpeed },
                                        set: { settings.gameSpeed = $0 }
                                    ),
                                    options: GameSpeed.allCases,
                                    labelFor: { $0.rawValue.capitalized }
                                )
                                .frame(maxWidth: 220)
                            }
                            SettingsRow(title: "Quiet AI turns") {
                                StampToggle(isOn: Binding(
                                    get: { settings.quietAITurns },
                                    set: { settings.quietAITurns = $0 }
                                ))
                            }
                            Button {
                                showRestartConfirm = true
                            } label: {
                                SettingsRow(title: "New game") {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.coral)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    glassCard {
                        SettingsSection(title: "stats") {
                            StatRow(label: "Games played", value: "\(stats.gamesPlayed)")
                            StatRow(label: "Wins", value: winsValue)
                            StatRow(label: "Win streak", value: streakValue)
                            StatRow(label: "Best score", value: bestScoreValue)
                            StatRow(label: "Biggest keep", value: biggestKeepValue)
                            StatRow(label: "Steals", value: "\(stats.steals)")
                            StatRow(label: "Busts", value: "\(stats.busts)")
                            StatRow(label: "Hot face", value: hotFaceValue)
                        }
                    }

                    glassCard {
                        SettingsSection(title: "by difficulty") {
                            ForEach(Difficulty.allCases, id: \.self) { d in
                                StatRow(
                                    label: d.rawValue.capitalized,
                                    value: modeValue(
                                        wins: stats.winsByDifficulty[d.rawValue] ?? 0,
                                        games: stats.gamesByDifficulty[d.rawValue] ?? 0
                                    )
                                )
                            }
                        }
                    }

                    glassCard {
                        SettingsSection(title: "by pace") {
                            ForEach(GameSpeed.allCases, id: \.self) { p in
                                StatRow(
                                    label: p.rawValue.capitalized,
                                    value: modeValue(
                                        wins: stats.winsByPace[p.rawValue] ?? 0,
                                        games: stats.gamesByPace[p.rawValue] ?? 0
                                    )
                                )
                            }
                        }
                    }

                    glassCard {
                        SettingsSection(title: "appearance") {
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
                    }

                    glassCard {
                        SettingsSection(title: "feedback") {
                            SettingsRow(title: "Sound") {
                                StampSegmented(
                                    selection: Binding(
                                        get: { settings.soundMode },
                                        set: { settings.soundMode = $0 }
                                    ),
                                    options: SoundMode.allCases,
                                    labelFor: soundModeLabel
                                )
                                .frame(maxWidth: 240)
                            }
                            SettingsRow(title: "Haptics", disabled: true) {
                                StampToggle(isOn: $placeholderOff, disabled: true)
                            }
                        }
                    }

                    glassCard {
                        SettingsSection(title: "other") {
                            Button {
                                goHome()
                            } label: {
                                SettingsRow(title: "Home") {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.coral)
                                }
                            }
                            .buttonStyle(.plain)
                            Button {
                                showExplainer = true
                            } label: {
                                SettingsRow(title: "How to play") {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.coral)
                                }
                            }
                            .buttonStyle(.plain)
                            SettingsRow(title: "Tip jar", disabled: true) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.dimInk)
                            }
                            Button {
                                showAbout = true
                            } label: {
                                SettingsRow(title: "About") {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.coral)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer(minLength: 40)

                    Text("v\(AppVersion.short) · shell yes by fastronaut")
                        .font(.avenir(13, weight: .medium, italic: true))
                        .tracking(1)
                        .foregroundStyle(Color.ink.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 18)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAbout) {
            AboutSheet()
        }
        .sheet(isPresented: $showExplainer) {
            ExplainerView()
        }
        .alert("Start a new game?", isPresented: $showRestartConfirm) {
            Button("New game", role: .destructive) {
                onNewGame()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current game will be discarded.")
        }
    }

    private func soundModeLabel(_ mode: SoundMode) -> String {
        switch mode {
        case .all: return "All"
        case .gameOnly: return "Game"
        case .muted: return "Off"
        }
    }

    // MARK: - Stats formatting

    private var winsValue: String {
        if let rate = stats.winRate {
            let pct = Int((rate * 100).rounded())
            return "\(stats.wins) · \(pct)%"
        }
        return "\(stats.wins)"
    }

    private var streakValue: String {
        if stats.bestStreak > stats.winStreak && stats.bestStreak > 0 {
            return "\(stats.winStreak) · best \(stats.bestStreak)"
        }
        return "\(stats.winStreak)"
    }

    private var bestScoreValue: String {
        stats.bestScore > 0 ? "\(stats.bestScore)" : "—"
    }

    private var biggestKeepValue: String {
        stats.biggestKeep > 0 ? "\(stats.biggestKeep)" : "—"
    }

    private var hotFaceValue: String {
        guard let face = stats.hotFace else { return "—" }
        return face == .coin ? "$" : "\(face.rawValue)"
    }

    /// Per-mode breakdown formatted as `wins/games · pct%`, or an em-dash
    /// when no games have been played in that mode yet.
    private func modeValue(wins: Int, games: Int) -> String {
        guard games > 0 else { return "—" }
        let pct = Int((Double(wins) / Double(games) * 100).rounded())
        return "\(wins)/\(games) · \(pct)%"
    }

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.ink.opacity(0.18), lineWidth: 1)
        )
        .padding(.bottom, 12)
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.avenir(15, weight: .medium))
                .foregroundStyle(Color.ink)
            Spacer()
            Text(value)
                .font(.avenir(15, weight: .demiBold))
                .foregroundStyle(Color.ink.opacity(0.85))
                .monospacedDigit()
        }
        .padding(.vertical, 8)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.avenir(11, weight: .medium, italic: true))
                .textCase(.lowercase)
                .tracking(2)
                .foregroundStyle(Color.coral)
                .padding(.bottom, 8)
            content()
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    var disabled: Bool = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.avenir(15, weight: .medium))
                .foregroundStyle(disabled ? Color.dimInk : Color.ink)
            if disabled {
                Text("soon")
                    .font(.avenir(9, weight: .medium, italic: true))
                    .textCase(.lowercase)
                    .tracking(1)
                    .foregroundStyle(Color.dimInk.opacity(0.7))
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 8)
    }
}

private struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Background()
            VStack(spacing: 20) {
                Spacer()
                HStack(spacing: 0) {
                    Text("c")
                    Text("h").foregroundStyle(Color.coral).font(.avenir(56, weight: .demiBold))
                    Text("ing")
                }
                .font(.avenir(56, weight: .ultraLight))
                .tracking(4)
                .foregroundStyle(Color.ink)

                Text("A push-your-luck dice game.\nv\(AppVersion.short) — Shell Yes by Fastronaut.")
                    .font(.avenir(15, weight: .medium, italic: true))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.dimInk)

                Spacer()

                Button("Close") { dismiss() }
                    .stampButton()
                    .frame(maxWidth: 240)
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
                let isSelected = value == selection
                Button {
                    selection = value
                } label: {
                    Text(labelFor(value))
                        .font(.avenir(13, weight: isSelected ? .demiBold : .medium))
                        .foregroundStyle(isSelected ? Color.paper : Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(isSelected ? Color.coral : Color.clear)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(labelFor(value)))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.insetSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.ink.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                Capsule()
                    .fill(
                        isOn
                            ? (disabled ? Color.dimInk.opacity(0.4) : Color.coral)
                            : Color.insetSurface
                    )
                    .frame(width: 38, height: 22)
                    .overlay(
                        Capsule().strokeBorder(disabled ? Color.dimInk.opacity(0.5) : Color.ink.opacity(0.4), lineWidth: 1)
                    )

                Circle()
                    .fill(isOn ? Color.paper : Color.ink.opacity(disabled ? 0.4 : 0.8))
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Toggle")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(disabled ? [.isStaticText] : [])
    }
}
