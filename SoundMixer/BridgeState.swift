import Foundation

struct BridgeState: Encodable {
    let schemaVersion: Int
    let isEnabled: Bool
    let devices: [BridgeDevice]
    let outputs: [BridgeOutput]
    let buses: [BridgeNamedItem]
    let blackHoleRoutes: [BridgeRoute]
    let applications: [BridgeApplication]
    let inputCaptureStates: [BridgeInputCaptureState]
    let mixes: [BridgeMix]
}

struct BridgeMix: Encodable {
    let target: String
    let id: String
    let level: Double
    let inputs: [BridgeMixInput]
}

struct BridgeMixInput: Encodable {
    let kind: String
    let id: String
    let level: Double
    let monoPlacement: String
}

struct BridgeApplication: Encodable {
    let id: String
    let name: String
    let available: Bool
    let captureState: String
    let muted: Bool
    let level: Double?
}

struct BridgeInputCaptureState: Encodable {
    let uid: String
    let state: String
    let level: Double?
}

struct BridgeDevice: Encodable {
    let uid: String
    let name: String
    let discovered: Bool
    let available: Bool
    let inputChannels: Int
    let outputChannels: Int
    let savedAs: [String]
    let muted: Bool
}

struct BridgeOutput: Encodable {
    let uid: String
    let name: String
    let isBlackHole: Bool
    let available: Bool
    let outputChannels: Int
    let level: Double
    let configured: Bool
    let routeError: String?
}

struct BridgeNamedItem: Encodable {
    let id: String
    let name: String
}

struct BridgeRoute: Encodable {
    let id: String
    let name: String
    let deviceUID: String
    let channels: [Int]
}

enum BridgeError: LocalizedError {
    case storageUnavailable
    case invalidPayload
    case unknownCommand
    case unknownOutput
    case unknownBus
    case unknownRoute
    case invalidName
    case unavailableBlackHole
    case invalidChannels

    var errorDescription: String? {
        switch self {
        case .storageUnavailable: "Configuration storage is unavailable."
        case .invalidPayload: "The command contains invalid values."
        case .unknownCommand: "The command is not supported."
        case .unknownOutput: "The output is not present in the saved configuration."
        case .unknownBus: "The virtual bus is not present in the saved configuration."
        case .unknownRoute: "The BlackHole route is not present in the saved configuration."
        case .invalidName: "Names must contain 1 to 64 characters."
        case .unavailableBlackHole: "Select an available BlackHole output device."
        case .invalidChannels: "The selected channels are unavailable or already used."
        }
    }
}
