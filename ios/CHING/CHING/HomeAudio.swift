import Foundation
import AVFoundation

/// Owns the looping home-screen music. One instance per app session;
/// `start()` is idempotent so re-entering the splash screen resumes the
/// existing player instead of double-playing.
final class HomeAudio {
    private var player: AVAudioPlayer?

    /// Filename (without extension) for the home-screen track. Keeping the
    /// Pixabay-issued name preserves the artist + track ID in the bundle.
    private let resourceName = "farran_ez-minimal-piano-underscore-456148"

    @MainActor
    func start() {
        if let existing = player {
            if !existing.isPlaying { existing.play() }
            return
        }
        let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3")
              ?? Bundle.main.url(forResource: resourceName, withExtension: "m4a")
        guard let url else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.55
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            // Silent fail — no music is better than a crash.
        }
    }

    @MainActor
    func stop(fade: TimeInterval = 0.4) {
        guard let p = player else { return }
        if fade <= 0 {
            p.stop()
            player = nil
            return
        }
        p.setVolume(0, fadeDuration: fade)
        let deadline = DispatchTime.now() + fade + 0.05
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            guard let self else { return }
            self.player?.stop()
            self.player = nil
        }
    }
}
