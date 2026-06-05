import XCTest
import CHINGEngine
@testable import CHING

@MainActor
final class GameStoreTests: XCTestCase {
    private static let difficultyKey = "ching.difficulty"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
        super.tearDown()
    }

    func test_init_setsUpThreePlayersHumanTurnRollPhase() {
        let store = GameStore(seed: 1)
        XCTAssertEqual(store.state.players.count, 3)
        XCTAssertEqual(store.state.players[0].id, "YOU")
        XCTAssertEqual(store.state.players[1].id, "JONES")
        XCTAssertEqual(store.state.players[2].id, "BOT 03")
        XCTAssertEqual(store.state.phase, .roll)
        XCTAssertEqual(store.state.current, 0)
        XCTAssertTrue(store.isHumanTurn)
        XCTAssertFalse(store.isOver)
        XCTAssertEqual(store.scores, [0, 0, 0])
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
        XCTAssertEqual(store.state.players[2].tiles, [])
        XCTAssertEqual(store.state.current, 0)
    }

    func test_runAIIfNeeded_isNoOpOnHumanTurn() async {
        let store = GameStore(seed: 1)
        let before = store.state
        await store.runAIIfNeeded(reduceMotion: true)
        XCTAssertEqual(store.state, before)
    }

    func test_runAIIfNeeded_reduceMotionRunsInstantly() async {
        let store = GameStore(seed: 1)
        let start = Date()
        await store.runAIIfNeeded(reduceMotion: true)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0)
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

    func test_difficulty_defaultIsNormalOnFirstLaunch() {
        let store = GameStore(seed: 1)
        XCTAssertEqual(store.difficulty, .normal)
    }

    func test_difficulty_persistsAcrossInstances() {
        let store1 = GameStore(seed: 1)
        store1.difficulty = .hard
        let store2 = GameStore(seed: 2)
        XCTAssertEqual(store2.difficulty, .hard)
    }
}
