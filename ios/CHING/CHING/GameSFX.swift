import Foundation
import AVFoundation

/// Short one-shot game sound effects. Shared singleton; each clip is
/// pre-loaded as a small pool of AVAudioPlayer instances so overlapping
/// triggers don't cut each other off.
@MainActor
final class GameSFX {
    static let shared = GameSFX()

    private var rollPool: [AVAudioPlayer] = []
    private var confirmPool: [AVAudioPlayer] = []
    private var nextRollIdx = 0
    private var nextConfirmIdx = 0

    private init() {
        // Two roll variants — alternate them for variety.
        load("dice_picking", into: &rollPool, copies: 2, volume: 0.65)
        load("dice_picking_2", into: &rollPool, copies: 2, volume: 0.65)
        load("dice_confirm", into: &confirmPool, copies: 2, volume: 0.7)
    }

    private func load(_ name: String, into pool: inout [AVAudioPlayer], copies: Int, volume: Float) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else { return }
        for _ in 0..<copies {
            guard let p = try? AVAudioPlayer(contentsOf: url) else { continue }
            p.volume = volume
            p.prepareToPlay()
            pool.append(p)
        }
    }

    func playRoll() {
        play(from: &rollPool, cursor: &nextRollIdx)
    }

    func playConfirm() {
        play(from: &confirmPool, cursor: &nextConfirmIdx)
    }

    private func play(from pool: inout [AVAudioPlayer], cursor: inout Int) {
        guard !pool.isEmpty else { return }
        let p = pool[cursor % pool.count]
        cursor += 1
        p.currentTime = 0
        p.play()
    }
}
