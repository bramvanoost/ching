import Foundation
import ShellYesEngine

struct ParityCase: Codable {
    struct BankTargetDTO: Codable {
        let kind: String
        let tile: Int
        let playerIndex: Int?
    }
    struct ActionDTO: Codable {
        let type: String
        let face: Int?
        let target: BankTargetDTO?
    }
    let seed: UInt32
    let playerIds: [String]
    let actions: [ActionDTO]
}

struct ParityTrace: Codable {
    let states: [State]
}

func actionFrom(_ dto: ParityCase.ActionDTO) -> Action {
    switch dto.type {
    case "ROLL": return .roll
    case "STOP": return .stop
    case "PICK":
        guard let raw = dto.face, let face = Face(rawValue: raw) else {
            FileHandle.standardError.write(Data("invalid PICK face\n".utf8))
            exit(1)
        }
        return .pick(face: face)
    case "BANK":
        guard let t = dto.target else {
            FileHandle.standardError.write(Data("BANK missing target\n".utf8))
            exit(1)
        }
        switch t.kind {
        case "center":
            return .bank(target: .center(tile: t.tile))
        case "steal":
            guard let idx = t.playerIndex else {
                FileHandle.standardError.write(Data("BANK steal missing playerIndex\n".utf8))
                exit(1)
            }
            return .bank(target: .steal(playerIndex: idx, tile: t.tile))
        default:
            FileHandle.standardError.write(Data("unknown BANK target kind \(t.kind)\n".utf8))
            exit(1)
        }
    default:
        FileHandle.standardError.write(Data("unknown action type \(dto.type)\n".utf8))
        exit(1)
    }
}

let input = FileHandle.standardInput.readDataToEndOfFile()
let testCase: ParityCase
do {
    testCase = try JSONDecoder().decode(ParityCase.self, from: input)
} catch {
    FileHandle.standardError.write(Data("invalid input: \(error)\n".utf8))
    exit(1)
}

var rng = Mulberry32(seed: testCase.seed)
var state = initialState(playerIds: testCase.playerIds)
var trace: [State] = [state]
for dto in testCase.actions {
    state = step(state: state, action: actionFrom(dto), rng: &rng)
    trace.append(state)
}

do {
    let out = try JSONEncoder().encode(ParityTrace(states: trace))
    FileHandle.standardOutput.write(out)
} catch {
    FileHandle.standardError.write(Data("encode failed: \(error)\n".utf8))
    exit(1)
}
