import Foundation

struct BridgeState: Encodable {
    let schemaVersion: Int
    let isEnabled: Bool
    let devices: [BridgeDevice]
    let outputs: [BridgeOutput]
    let buses: [BridgeNamedItem]
    let applications: [BridgeApplication]
    let inputCaptureStates: [BridgeInputCaptureState]
    let mixes: [BridgeMix]
}

struct BridgeMix: Encodable {
    let target: String
    let id: String
    let level: Double
    let inputs: [BridgeMixInput]
    let levelReading: Double?
}

struct BridgeMixInput: Encodable {
    let kind: String
    let id: String
    let level: Double
    let channelRouting: [[Int]]
    let channelLevels: [Double]
    let muted: Bool
    let sourceMuted: Bool
    let levelReading: Double?
}

struct BridgeApplication: Encodable {
    let id: String
    let name: String
    let available: Bool
    let captureState: String
    let muted: Bool
    let level: Double?
    let registered: Bool
    let sourceLevel: Double
    let channelLevels: [Double?]
}

struct BridgeInputCaptureState: Encodable {
    let uid: String
    let state: String
    let level: Double?
    let channelLevels: [Double?]
}

struct BridgeDevice: Encodable {
    let uid: String
    let name: String
    let category: String
    let discovered: Bool
    let available: Bool
    let inputChannels: Int
    let outputChannels: Int
    let savedAs: [String]
    let muted: Bool
    let sourceLevel: Double
    let hidden: Bool
}

struct BridgeOutput: Encodable {
    let uid: String
    let name: String
    let category: String
    let available: Bool
    let outputChannels: Int
    let volume: Double?
    let volumeWritable: Bool
    let muted: Bool?
    let muteWritable: Bool
    let configured: Bool
    let routeError: String?
    let levelReading: Double?
    let meterState: String?
}

struct BridgeNamedItem: Encodable {
    let id: String
    let name: String
    let category: String
    let muted: Bool
    let sourceLevel: Double
}

enum BridgeError: LocalizedError {
    case storageUnavailable
    case invalidPayload
    case unknownCommand
    case unknownOutput
    case unknownBus
    case invalidName

    var errorDescription: String? {
        switch self {
        case .storageUnavailable: "Configuration storage is unavailable."
        case .invalidPayload: "The command contains invalid values."
        case .unknownCommand: "The command is not supported."
        case .unknownOutput: "The output is not present in the saved configuration."
        case .unknownBus: "The virtual bus is not present in the saved configuration."
        case .invalidName: "Names must contain 1 to 64 characters."
        }
    }
}
