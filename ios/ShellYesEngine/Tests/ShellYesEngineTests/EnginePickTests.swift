import XCTest
@testable import CHINGEngine

final class EnginePickTests: XCTestCase {

    func testPickLocksAllDiceOfFace() {
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .pick
        s.rolled = [.three, .three, .four, .five, .coin, .one, .two, .three]
        let s2 = step(state: s, action: .pick(face: .three), rng: &rng)
        XCTAssertEqual(s2.setAside, [.three, .three, .three])
        XCTAssertEqual(s2.pickedFaces, [.three])
        XCTAssertEqual(s2.diceInHand, 5)
        XCTAssertEqual(s2.rolled, [])
        XCTAssertEqual(s2.phase, .roll)
    }

    func testPickNoopWhenFaceAlreadyPicked() {
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .pick
        s.rolled = [.three, .four]
        s.pickedFaces = [.three]
        let s2 = step(state: s, action: .pick(face: .three), rng: &rng)
        XCTAssertEqual(s2, s)
    }

    func testPickNoopWhenFaceNotInRolled() {
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .pick
        s.rolled = [.three, .four]
        let s2 = step(state: s, action: .pick(face: .five), rng: &rng)
        XCTAssertEqual(s2, s)
    }

    func testPickConsumingLastDieAutoBanks() {
        // 8 dice all coin face, pick coin -> diceInHand = 0 -> tryBank.
        // sum = 8 * 5 = 40, contains coin, take highest tile <= 40 = 36.
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .pick
        s.rolled = Array(repeating: .coin, count: 8)
        let s2 = step(state: s, action: .pick(face: .coin), rng: &rng)
        XCTAssertEqual(s2.players[0].tiles, [36])
        XCTAssertEqual(s2.centerTiles.last, 35)
        XCTAssertEqual(s2.current, 1)
    }
}
