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
    // Always-ROLL placeholder; replaced in Task 12.
    return .roll
}
