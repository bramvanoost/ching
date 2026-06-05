import XCTest
import CHINGEngine
@testable import CHING

@MainActor
final class GameStoreTests: XCTestCase {
    func test_init_setsUpTwoPlayersHumanTurnRollPhase() {
        let store = GameStore(seed: 1)
        XCTAssertEqual(store.state.players.count, 2)
        XCTAssertEqual(store.state.players[0].id, "YOU")
        XCTAssertEqual(store.state.players[1].id, "JONES")
        XCTAssertEqual(store.state.phase, .roll)
        XCTAssertEqual(store.state.current, 0)
        XCTAssertTrue(store.isHumanTurn)
        XCTAssertFalse(store.isOver)
        XCTAssertEqual(store.scores, [0, 0])
    }

    func test_apply_rollAdvancesPhaseOrTurn() {
        let store = GameStore(seed: 1)
        store.apply(.roll)
        let advanced = store.state.phase == .pick || store.state.current != 0
        XCTAssertTrue(advanced)
    }

    func test_newGame_resetsState() {
        let store = GameStore(seed: 1)
        store.apply(.roll)
        store.newGame()
        XCTAssertEqual(store.state.centerTiles, Array(21...36))
        XCTAssertEqual(store.state.phase, .roll)
        XCTAssertEqual(store.state.players[0].tiles, [])
        XCTAssertEqual(store.state.players[1].tiles, [])
        XCTAssertEqual(store.state.current, 0)
    }

    func test_runAIIfNeeded_isNoOpOnHumanTurn() {
        let store = GameStore(seed: 1)
        let before = store.state
        store.runAIIfNeeded()
        XCTAssertEqual(store.state, before)
    }

    func test_fullGameTerminates() {
        let store = GameStore(seed: 1)
        var safetyLimit = 5000
        while !store.isOver && safetyLimit > 0 {
            let action = decide(state: store.state, ai: Difficulty(discipline: 0.5))
            store.apply(action)
            safetyLimit -= 1
        }
        XCTAssertTrue(store.isOver, "Game should terminate within 5000 actions")
        XCTAssertGreaterThan(safetyLimit, 0)
    }

    func test_difficulty_modifierTable() {
        XCTAssertEqual(Difficulty.easy.modifier, -0.15, accuracy: 0.0001)
        XCTAssertEqual(Difficulty.normal.modifier, 0, accuracy: 0.0001)
        XCTAssertEqual(Difficulty.hard.modifier, 0.15, accuracy: 0.0001)
        XCTAssertEqual(Difficulty.allCases, [.easy, .normal, .hard])
    }
}
