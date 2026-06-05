import XCTest
@testable import CHINGEngine

final class AITests: XCTestCase {

    func testAiPicksCoinFirstWhenAvailable() {
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .pick
        s.rolled = [.coin, .three, .three, .three, .three, .three, .three, .three]
        let action = decide(state: s, ai: Difficulty(discipline: 0.5))
        XCTAssertEqual(action, .pick(face: .coin))
    }

    func testAiPicksHighestValueGroupWhenCoinAlreadyHeld() {
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .pick
        s.setAside = [.coin]
        s.pickedFaces = [.coin]
        s.rolled = [.three, .three, .three, .four, .four]
        // 3 threes = 9, 2 fours = 8 -> pick threes
        let action = decide(state: s, ai: Difficulty(discipline: 0.5))
        XCTAssertEqual(action, .pick(face: .three))
    }

    func testAiPicksAnythingPresentWhenNoCoinAvailable() {
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .pick
        s.rolled = [.one, .one]
        let action = decide(state: s, ai: Difficulty(discipline: 0.5))
        XCTAssertEqual(action, .pick(face: .one))
    }

    func testAiRollsWhenNoCoinHeld() {
        var s = initialState(playerIds: ["P0", "P1"])
        s.setAside = [.three, .four]  // no coin
        let action = decide(state: s, ai: Difficulty(discipline: 1.0))
        XCTAssertEqual(action, .roll)
    }

    func testCautiousAiStopsAtAnyReachableTile() {
        var s = initialState(playerIds: ["P0", "P1"])
        s.setAside = [.coin, .coin, .coin, .coin, .one]  // sum 21
        s.diceInHand = 3
        s.pickedFaces = [.coin, .one]
        let action = decide(state: s, ai: Difficulty(discipline: 1.0))
        XCTAssertEqual(action, .stop)
    }

    func testGreedyAiKeepsRollingForHigherTier() {
        var s = initialState(playerIds: ["P0", "P1"])
        s.setAside = [.coin, .coin, .coin, .coin, .one]  // sum 21 -> tier 1
        s.diceInHand = 3
        s.pickedFaces = [.coin, .one]
        let action = decide(state: s, ai: Difficulty(discipline: 0.0))
        XCTAssertEqual(action, .roll)
    }

    func testAiStopsWhenBustRiskExceedsCeiling() {
        var s = initialState(playerIds: ["P0", "P1"])
        // Force a reachable tile so we exercise the bustCeiling branch (not the
        // bestBankableTile == nil branch).
        s.setAside = [.coin, .coin, .coin, .coin, .one]  // sum 21
        s.pickedFaces = [.coin, .one, .two, .three, .four]
        s.diceInHand = 1
        // bust prob = (5/6)^1 ~= 0.833
        // bustCeiling at discipline 0.5 = 0.75 - 0.3 = 0.45 < 0.833 -> STOP
        let action = decide(state: s, ai: Difficulty(discipline: 0.5))
        XCTAssertEqual(action, .stop)
    }
}
