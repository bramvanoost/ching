import XCTest
@testable import CHINGEngine

final class EngineRollTests: XCTestCase {

    func testRollProducesEightDiceFromFreshState() {
        var rng = Mulberry32(seed: 1)
        let s0 = initialState(playerIds: ["P0", "P1"])
        let s1 = step(state: s0, action: .roll, rng: &rng)
        XCTAssertEqual(s1.rolled.count, 8)
        XCTAssertEqual(s1.phase, .pick)
        XCTAssertEqual(s1.diceInHand, 8)  // not consumed until PICK
    }

    func testRollNoopWhenPhaseIsNotRoll() {
        var rng = Mulberry32(seed: 1)
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .pick
        let s2 = step(state: s, action: .roll, rng: &rng)
        XCTAssertEqual(s2, s)
    }

    func testRollNoopWhenDiceInHandIsZero() {
        var rng = Mulberry32(seed: 1)
        var s = initialState(playerIds: ["P0", "P1"])
        s.diceInHand = 0
        let s2 = step(state: s, action: .roll, rng: &rng)
        XCTAssertEqual(s2, s)
    }
}
