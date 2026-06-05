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
}
