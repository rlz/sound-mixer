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
}

struct BridgeApplication: Encodable {
    let id: String
    let name: String
    let available: Bool
    let captureState: String
}

struct BridgeInputCaptureState: Encodable {
    let uid: String
    let state: String
}

struct BridgeDevice: Encodable {
    let uid: String
    let name: String
    let discovered: Bool
    let available: Bool
    let inputChannels: Int
    let outputChannels: Int
    let savedAs: [String]
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
}

enum BridgeError: LocalizedError {
    case storageUnavailable
    case invalidPayload
    case unknownCommand
    case unknownOutput
    case unknownBus
    case unknownRoute
    case invalidName

    var errorDescription: String? {
        switch self {
        case .storageUnavailable: "Configuration storage is unavailable."
        case .invalidPayload: "The command contains invalid values."
        case .unknownCommand: "The command is not supported."
        case .unknownOutput: "The output is not present in the saved configuration."
        case .unknownBus: "The virtual bus is not present in the saved configuration."
        case .unknownRoute: "The BlackHole route is not present in the saved configuration."
        case .invalidName: "Names must contain 1 to 64 characters."
        }
    }
}
