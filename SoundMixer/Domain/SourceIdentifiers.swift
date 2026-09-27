import Foundation

/// A persisted Core Audio UID. Names and live AudioObjectIDs belong to discovery.
public struct DeviceUID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ApplicationID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AudioDeviceDescriptor: Equatable, Sendable {
    public let uid: DeviceUID
    public let name: String
    public let inputChannels: Int
    public let outputChannels: Int
    public let sampleRate: Double
    public init(uid: DeviceUID, name: String, inputChannels: Int, outputChannels: Int, sampleRate: Double) {
        self.uid = uid
        self.name = name
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
        self.sampleRate = sampleRate
    }
}

public struct ApplicationDescriptor: Equatable, Sendable {
    public let id: ApplicationID
    public let name: String
    public let isAvailable: Bool

    public init(id: ApplicationID, name: String, isAvailable: Bool) {
        self.id = id
        self.name = name
        self.isAvailable = isAvailable
    }
}
