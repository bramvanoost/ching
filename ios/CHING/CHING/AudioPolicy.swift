import Foundation

/// Single source of truth for "should anything play right now?".
/// SettingsStore feeds it the user's sound preference, and the views
/// tell it whether we're currently in the game vs on the splash so
/// the home music ducks while the game is on screen.
@MainActor
final class AudioPolicy {
    static let shared = AudioPolicy()

    private(set) var soundMode: SoundMode = .all
    private(set) var inGame: Bool = false

    private init() {}

    func applySoundMode(_ mode: SoundMode) {
        soundMode = mode
        apply()
    }

    func setInGame(_ value: Bool) {
        guard inGame != value else { return }
        inGame = value
        apply()
    }

    /// SFX (rolls, picks, banks, busts) are silent only when fully muted.
    var sfxEnabled: Bool { soundMode != .muted }

    private func apply() {
        switch soundMode {
        case .muted, .gameOnly:
            HomeAudio.shared.stop(fade: 0.4)
        case .all:
            HomeAudio.shared.startIfNeeded()
            HomeAudio.shared.setVolume(inGame ? 0.15 : 0.55, fade: 0.6)
        }
    }
}
