import Foundation

public struct Difficulty: Sendable, Equatable {
    public var discipline: Double
    public init(discipline: Double) {
        self.discipline = discipline
    }
}

public func decide(state: State, ai: Difficulty) -> Action {
    if state.phase == .pick {
        return .pick(face: pickFace(state))
    }
    if state.setAside.isEmpty {
        return .roll
    }
    return continueOrStop(state, ai: ai)
}

func pickFace(_ state: State) -> Face {
    let candidates = Face.allCases.filter { face in
        !state.pickedFaces.contains(face) && state.rolled.contains(face)
    }
    let hasCoin = state.setAside.contains(.coin)
    if !hasCoin, candidates.contains(.coin) {
        return .coin
    }
    func valueOf(_ f: Face) -> Int {
        state.rolled.filter { $0 == f }.count * f.value
    }
    return candidates.reduce(candidates.first!) { best, f in
        valueOf(f) > valueOf(best) ? f : best
    }
}

func continueOrStop(_ state: State, ai: Difficulty) -> Action {
    let sum = state.setAside.reduce(0) { $0 + $1.value }
    let hasCoin = state.setAside.contains(.coin)
    guard hasCoin else { return .roll }

    guard let target = bestBankableTile(state, sum: sum) else { return .roll }

    let pickedCount = state.pickedFaces.count
    let bustProb = pow(Double(pickedCount) / 6.0, Double(state.diceInHand))

    // Bust tolerance shrinks sharply as discipline rises.
    // Greedy (0.0) tolerates up to 0.75, cautious (1.0) bails at 0.15.
    let bustCeiling = 0.75 - ai.discipline * 0.6
    if bustProb >= bustCeiling { return .stop }

    // Cap target tier by what's still reachable so we don't wait for tiles
    // that no longer exist.
    let ceiling: Int = state.centerTiles.isEmpty
        ? 4
        : tileCoins(state.centerTiles.last!)
    // Discipline narrows ambition: 0 holds out for 4-coin tiles, 1 banks any.
    let desiredTier = max(1, min(ceiling, Int((4.0 - ai.discipline * 3.5).rounded())))
    if tileCoins(target) >= desiredTier { return .stop }

    return .roll
}

func bestBankableTile(_ state: State, sum: Int) -> Int? {
    for i in state.players.indices where i != state.current {
        if let top = state.players[i].tiles.last, top == sum {
            return sum
        }
    }
    let available = state.centerTiles.filter { $0 <= sum }
    return available.max()
}
