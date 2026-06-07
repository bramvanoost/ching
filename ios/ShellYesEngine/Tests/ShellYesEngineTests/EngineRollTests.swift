import XCTest
@testable import ShellYesEngine

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

    func testRollBustsWhenAllFacesAlreadyPicked() {
        // Setup: player has picked faces 1 and 2. Only one die left, RNG forces it to 1.
        // Player must bust because no new face is available.
        struct ForcedOne: ShellYesRandom {
            mutating func next() -> Double { 0.0 }  // -> floor(0 * 6) + 1 = 1
        }
        var rng = ForcedOne()
        var s = initialState(playerIds: ["P0", "P1"])
        s.pickedFaces = [.one, .two]
        s.diceInHand = 1
        s.players[0].tiles = [28]
        let after = step(state: s, action: .roll, rng: &rng)
        // Bust: top tile returned to center (sorted), highest center burned, turn ends.
        XCTAssertEqual(after.players[0].tiles, [])
        XCTAssertEqual(after.centerTiles.last, 35)  // 36 burned, 28 returned
        XCTAssertTrue(after.centerTiles.contains(28))
        XCTAssertEqual(after.current, 1)
        XCTAssertEqual(after.phase, .roll)
    }
}
