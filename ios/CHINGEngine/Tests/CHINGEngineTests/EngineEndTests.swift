import XCTest
@testable import CHINGEngine

final class EngineEndTests: XCTestCase {

    func testGameEndsWhenLastCenterTileIsBanked() {
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.centerTiles = [21]  // only one tile left
        s.phase = .roll
        s.setAside = [.coin, .coin, .five, .five, .one]  // sum 21
        let s2 = step(state: s, action: .stop, rng: &rng)
        XCTAssertEqual(s2.phase, .over)
        XCTAssertEqual(s2.players[0].tiles, [21])
        XCTAssertTrue(s2.centerTiles.isEmpty)
    }

    func testStepIsNoOpWhenPhaseIsOver() {
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0"])
        s.phase = .over
        let s2 = step(state: s, action: .roll, rng: &rng)
        XCTAssertEqual(s2, s)
    }

    func testGameEndsAfterBustOfFinalTile() {
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.centerTiles = [21]  // only one tile
        s.players[0].tiles = []  // nothing to return
        s.phase = .roll
        s.setAside = [.three]  // no coin -> bust
        let s2 = step(state: s, action: .stop, rng: &rng)
        // bust burns the highest center tile (21), leaving none -> game ends.
        XCTAssertEqual(s2.phase, .over)
        XCTAssertTrue(s2.centerTiles.isEmpty)
    }
}
