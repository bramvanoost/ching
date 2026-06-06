import XCTest
import CHINGEngine
@testable import CHING

@MainActor
final class GameStoreTests: XCTestCase {
    private static let difficultyKey = "ching.difficulty"
    private static let colorModeKey = "ching.colorMode"
    private static let reducedMotionKey = "ching.reducedMotion"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
        UserDefaults.standard.removeObject(forKey: Self.colorModeKey)
        UserDefaults.standard.removeObject(forKey: Self.reducedMotionKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
        UserDefaults.standard.removeObject(forKey: Self.colorModeKey)
        UserDefaults.standard.removeObject(forKey: Self.reducedMotionKey)
        super.tearDown()
    }

    private func makeStore(seed: UInt32 = 1) -> GameStore {
        GameStore(seed: seed, settings: SettingsStore())
    }

    func test_init_setsUpThreePlayersHumanTurnRollPhase() {
        let store = makeStore(seed: 1)
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
        let store = makeStore(seed: 1)
        store.apply(.roll)
        let advanced = store.state.phase == .pick || store.state.current != 0
        XCTAssertTrue(advanced)
    }

    func test_newGame_resetsState() {
        let store = makeStore(seed: 1)
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
        let store = makeStore(seed: 1)
        let before = store.state
        await store.runAIIfNeeded(reduceMotion: true)
        XCTAssertEqual(store.state, before)
    }

    func test_runAIIfNeeded_reduceMotionRunsInstantly() async {
        let store = makeStore(seed: 1)
        let start = Date()
        await store.runAIIfNeeded(reduceMotion: true)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0)
    }

    func test_fullThreePlayerGameTerminates() {
        let store = makeStore(seed: 1)
        var safetyLimit = 5000
        while !store.isOver && safetyLimit > 0 {
            let action = decide(state: store.state, ai: CHINGEngine.Difficulty(discipline: 0.5))
            store.apply(action)
            safetyLimit -= 1
        }
        XCTAssertTrue(store.isOver, "3-player game should terminate within 5000 actions")
        XCTAssertGreaterThan(safetyLimit, 0)
        XCTAssertEqual(store.state.players.count, 3)
    }

    func test_difficulty_modifierTable() {
        XCTAssertEqual(Difficulty.easy.modifier, -0.15, accuracy: 0.0001)
        XCTAssertEqual(Difficulty.normal.modifier, 0, accuracy: 0.0001)
        XCTAssertEqual(Difficulty.hard.modifier, 0.15, accuracy: 0.0001)
        XCTAssertEqual(Difficulty.allCases, [.easy, .normal, .hard])
    }

    func test_phaseHint_byPhaseAndSeat() {
        let store = makeStore(seed: 1)
        XCTAssertEqual(store.phaseHint, "Your roll.")

        var s = store.state
        s.phase = .pick
        s.rolled = [.three, .three, .five, .coin]
        store.setStateForTesting(s)
        XCTAssertEqual(store.phaseHint, "Make your choice.")

        s.current = GameStore.jonesSeat
        s.phase = .roll
        store.setStateForTesting(s)
        XCTAssertEqual(store.phaseHint, "Jones is thinking…")
    }

    func test_burnedCount_derivesFromMissingSafes() {
        let store = makeStore(seed: 1)
        XCTAssertEqual(store.burnedCount, 0)

        var s = store.state
        s.centerTiles = [23, 24, 25]
        s.players[0].tiles = [21, 22]
        s.players[1].tiles = [26, 27, 28]
        store.setStateForTesting(s)
        XCTAssertEqual(store.burnedCount, 8)
    }

    func test_bankActionLabel_pointsAtFirstRivalWithMatchingTop() {
        let store = makeStore(seed: 1)
        var s = store.state
        s.players[1].tiles = [25]
        s.players[2].tiles = [25]
        s.setAside = [.five, .coin, .five, .four, .three, .three]
        s.pickedFaces = [.five, .coin, .four, .three]
        s.diceInHand = 2
        s.phase = .roll
        s.current = GameStore.humanSeat
        store.setStateForTesting(s)
        XCTAssertEqual(store.setAsideSum, 25)
        XCTAssertEqual(store.bankActionLabel, "Steal Jones's tile")
    }
}
