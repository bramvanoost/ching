import Foundation
import Observation
import ShellYesEngine

enum Difficulty: String, Codable, CaseIterable {
    case easy, normal, hard

    var modifier: Double {
        switch self {
        case .easy: return -0.15
        case .normal: return 0
        case .hard: return 0.15
        }
    }
}

@MainActor
@Observable
final class GameStore {
    static let humanSeat = 0
    static let jonesSeat = 1
    static let bot03Seat = 2

    private let baseDiscipline: [Int: Double] = [
        jonesSeat: 0.30,
        bot03Seat: 0.85,
    ]

    enum AIEvent: Equatable {
        case took(actor: String, shell: Int)
        case stole(actor: String, victim: String, shell: Int)
        case bust(actor: String, burned: Int?)
    }

    private(set) var state: State
    private(set) var aiEvent: AIEvent? = nil
    @ObservationIgnored private var aiEventContinuation: CheckedContinuation<Void, Never>?
    private var rng: Mulberry32
    private let settings: SettingsStore

    init(seed: UInt32, settings: SettingsStore) {
        self.rng = Mulberry32(seed: seed)
        self.settings = settings
        self.state = initialState(playerIds: ["YOU", "JONES", "BOT 03"])
    }

    convenience init(settings: SettingsStore) {
        self.init(seed: UInt32.random(in: 1...UInt32.max), settings: settings)
    }

    var scores: [Int] { score(state) }
    var setAsideSum: Int { state.setAside.reduce(0) { $0 + $1.value } }
    var isHumanTurn: Bool { state.current == Self.humanSeat }
    var isOver: Bool { state.phase == .over }

    var canRoll: Bool {
        state.phase == .roll && state.diceInHand > 0 && isHumanTurn
    }

    var canBank: Bool {
        state.phase == .roll && !state.setAside.isEmpty && isHumanTurn
    }

    var bankActionLabel: String {
        guard canBank else { return "Keep" }
        for i in state.players.indices where i != state.current {
            if let top = state.players[i].tiles.last, top == setAsideSum {
                let name = state.players[i].id.capitalized
                return "Take \(name)'s shell"
            }
        }
        return "Keep"
    }

    var isStealOpportunity: Bool {
        guard canBank else { return false }
        for i in state.players.indices where i != state.current {
            if let top = state.players[i].tiles.last, top == setAsideSum {
                return true
            }
        }
        return false
    }

    var phaseHint: String {
        if !isHumanTurn && !isOver {
            return "\(state.players[state.current].id.capitalized) reads the tide…"
        }
        if isOver { return "the tide rolls back." }
        switch state.phase {
        case .roll:
            return state.setAside.isEmpty ? "no rush, smell the sea air" : "roll on, or keep."
        case .pick:
            return "pick what you'll keep."
        case .over:
            return "the tide rolls back."
        }
    }

    var burnedCount: Int {
        let totalInUse = state.centerTiles.count + state.players.reduce(0) { $0 + $1.tiles.count }
        return max(0, 16 - totalInUse)
    }

    static func safeCoins(_ safe: Int) -> Int {
        tileCoins(safe)
    }

    func canPick(_ face: Face) -> Bool {
        state.phase == .pick &&
            isHumanTurn &&
            !state.pickedFaces.contains(face) &&
            state.rolled.contains(face)
    }

    var currentAIDifficulty: ShellYesEngine.Difficulty? {
        guard !isHumanTurn else { return nil }
        let base = baseDiscipline[state.current] ?? 0.5
        let adjusted = max(0, min(1, base + settings.difficulty.modifier))
        return ShellYesEngine.Difficulty(discipline: adjusted)
    }

    func apply(_ action: Action) {
        state = step(state: state, action: action, rng: &rng)
    }

    private static let aiPaceNanoseconds: UInt64 = 300_000_000

    func runAIIfNeeded(reduceMotion: Bool) async {
        let factor = settings.gameSpeed.factor
        let pace = UInt64(Double(Self.aiPaceNanoseconds) * factor)
        while !isOver, let ai = currentAIDifficulty {
            let oldState = state
            let oldCurrent = oldState.current
            let action = decide(state: state, ai: ai)
            apply(action)
            if !reduceMotion {
                try? await Task.sleep(nanoseconds: pace)
            }
            // Turn passed — surface an event banner so the player sees what
            // happened without scanning the board for differences.
            if !reduceMotion, state.current != oldCurrent || (isOver && state.current == oldCurrent) {
                if let event = turnEndEvent(from: oldState, oldCurrent: oldCurrent) {
                    await presentAIEvent(event)
                }
            }
        }
    }

    private func turnEndEvent(from oldState: State, oldCurrent: Int) -> AIEvent? {
        let actorName = oldState.players[oldCurrent].id.capitalized
        let oldTiles = oldState.players[oldCurrent].tiles
        let newTiles = state.players[oldCurrent].tiles
        if newTiles.count > oldTiles.count, let newShell = newTiles.last {
            for i in oldState.players.indices where i != oldCurrent {
                if state.players[i].tiles.count < oldState.players[i].tiles.count {
                    let victim = oldState.players[i].id.capitalized
                    return .stole(actor: actorName, victim: victim, shell: newShell)
                }
            }
            return .took(actor: actorName, shell: newShell)
        }
        // Bust — find the burned shell by diffing total supply (center +
        // every player's stack). Tile numbers are unique 21-36, so the
        // single missing entry is the one the bank ate.
        let oldSet = Set(oldState.centerTiles + oldState.players.flatMap { $0.tiles })
        let newSet = Set(state.centerTiles + state.players.flatMap { $0.tiles })
        let burned = oldSet.subtracting(newSet).first
        return .bust(actor: actorName, burned: burned)
    }

    private func presentAIEvent(_ event: AIEvent) async {
        aiEvent = event
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            aiEventContinuation = cont
        }
    }

    /// Display a turn event banner without blocking on a continuation —
    /// for the human's own actions, where there's no AI loop to pause.
    /// The view dismisses it via `dismissAIEvent()` on tap.
    func presentTurnEvent(_ event: AIEvent) {
        aiEvent = event
    }

    func dismissAIEvent() {
        guard aiEvent != nil else { return }
        aiEvent = nil
        let cont = aiEventContinuation
        aiEventContinuation = nil
        cont?.resume()
    }

    func newGame() {
        rng = Mulberry32(seed: UInt32.random(in: 1...UInt32.max))
        state = initialState(playerIds: ["YOU", "JONES", "BOT 03"])
    }

    #if DEBUG
    func setStateForTesting(_ s: State) {
        self.state = s
    }
    #endif
}
