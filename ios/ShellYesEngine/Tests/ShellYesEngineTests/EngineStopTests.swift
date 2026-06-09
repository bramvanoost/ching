import XCTest
@testable import ShellYesEngine

final class EngineStopTests: XCTestCase {

    func testStopBanksWhenInRollPhaseWithSetAside() {
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .roll
        s.setAside = [.coin, .four, .three]  // sum = 12... too low for a tile
        // Sum 12 < any center tile (smallest is 21), so this should bust.
        let s2 = step(state: s, action: .stop, rng: &rng)
        XCTAssertEqual(s2.players[0].tiles, [])
        XCTAssertEqual(s2.current, 1)
    }

    func testStopNoopWhenSetAsideEmpty() {
        var rng = Mulberry32(seed: 0)
        let s = initialState(playerIds: ["P0", "P1"])
        // phase already .roll, setAside empty
        let s2 = step(state: s, action: .stop, rng: &rng)
        XCTAssertEqual(s2, s)
    }

    func testStopBanksHighestAvailableTile() {
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .roll
        s.setAside = [.coin, .coin, .five, .four, .four]  // 5+5+5+4+4 = 23
        let s2 = step(state: s, action: .stop, rng: &rng)
        XCTAssertEqual(s2.players[0].tiles, [23])
        XCTAssertFalse(s2.centerTiles.contains(23))
        XCTAssertEqual(s2.current, 1)
    }

    func testStopAutoResolvesStealWhenNoCenterTileFits() {
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.players[1].tiles = [25]
        s.phase = .roll
        s.setAside = [.coin, .coin, .five, .five, .five]  // sum 25 (coin = 5)
        // Strip every supply tile <= 25 so steal is the only legal option;
        // the bank commits immediately rather than entering chooseBank.
        s.centerTiles = s.centerTiles.filter { $0 > 25 }
        let s2 = step(state: s, action: .stop, rng: &rng)
        XCTAssertEqual(s2.phase, .roll)
        XCTAssertEqual(s2.players[0].tiles, [25])
        XCTAssertEqual(s2.players[1].tiles, [])
    }

    func testStopEntersChooseBankWhenStealAndCenterBothPossible() {
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.players[1].tiles = [24]
        s.phase = .roll
        s.setAside = [.coin, .coin, .five, .five, .four]  // sum 24
        let s2 = step(state: s, action: .stop, rng: &rng)
        XCTAssertEqual(s2.phase, .chooseBank)
        XCTAssertEqual(s2.current, 0)
        XCTAssertEqual(bankOptions(s2), [
            .steal(playerIndex: 1, tile: 24),
            .center(tile: 24),
        ])

        // Commit the steal explicitly: rival 24 transfers, supply untouched.
        let afterSteal = step(state: s2, action: .bank(target: .steal(playerIndex: 1, tile: 24)), rng: &rng)
        XCTAssertEqual(afterSteal.players[0].tiles, [24])
        XCTAssertEqual(afterSteal.players[1].tiles, [])
        XCTAssertTrue(afterSteal.centerTiles.contains(24))
        XCTAssertEqual(afterSteal.current, 1)
    }

    func testBankCenterTakeEndsGameWhenItEmptiesTheSupply() {
        // Bram's scenario: supply has only 25, rival has top tile 26, the
        // active player banks sum 26. Choosing the center take ends the
        // game even though stealing was on offer.
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.players[1].tiles = [26]
        s.phase = .roll
        s.centerTiles = [25]
        s.setAside = [.coin, .coin, .coin, .coin, .coin, .one]  // sum 26
        let s2 = step(state: s, action: .stop, rng: &rng)
        XCTAssertEqual(s2.phase, .chooseBank)

        let afterCenter = step(state: s2, action: .bank(target: .center(tile: 25)), rng: &rng)
        XCTAssertEqual(afterCenter.phase, .over)
        XCTAssertEqual(afterCenter.players[0].tiles, [25])
        XCTAssertEqual(afterCenter.players[1].tiles, [26])
        XCTAssertEqual(afterCenter.centerTiles, [])
    }
}
