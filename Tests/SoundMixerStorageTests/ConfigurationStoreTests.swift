import Foundation
import SoundMixerDomain
@testable import SoundMixerStorage
import XCTest

final class ConfigurationStoreTests: XCTestCase {
    func testAcceptedChangesRestoreAfterRestartIncludingNamesAndEnabledState() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let outputUID = DeviceUID(rawValue: "output-1")
        let inputUID = DeviceUID(rawValue: "input-1")
        let store = try ConfigurationStore(fileURL: fileURL)

        try store.update(discoveredDevices: [descriptor(outputUID, name: "Speakers"), descriptor(inputUID, name: "Microphone")]) {
            $0.isEnabled = true
            $0.outputMixes = [OutputMix(deviceUID: outputUID, mix: Mix(inputs: [MixInput(source: .inputDevice(inputUID))]))]
        }

        let restored = try ConfigurationStore(fileURL: fileURL)
        XCTAssertTrue(restored.configuration.isEnabled)
        XCTAssertEqual(restored.configuration.deviceDisplayName(for: outputUID), "Speakers")
        XCTAssertEqual(restored.configuration.deviceDisplayName(for: inputUID), "Microphone")

        try restored.update(discoveredDevices: [descriptor(outputUID, name: "New Speaker Name")]) { _ in }
        XCTAssertEqual(try ConfigurationStore(fileURL: fileURL).configuration.deviceDisplayName(for: outputUID), "New Speaker Name")

        try restored.update {
            $0.outputMixes[0].mix.inputs.removeAll()
            $0.isEnabled = false
        }

        let restarted = try ConfigurationStore(fileURL: fileURL)
        XCTAssertFalse(restarted.configuration.isEnabled)
        XCTAssertEqual(restarted.configuration.deviceDisplayName(for: outputUID), "New Speaker Name")
        XCTAssertFalse(restarted.configuration.knownDevices.contains { $0.uid == inputUID })
    }

    func testInvalidEditLeavesMemoryAndFileUnchanged() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = try ConfigurationStore(fileURL: fileURL)
        try store.update { $0.isEnabled = true }
        let before = try Data(contentsOf: fileURL)

        XCTAssertThrowsError(try store.update { $0.buses = [VirtualBus(name: "   ")] })
        XCTAssertTrue(store.configuration.isEnabled)
        XCTAssertTrue(store.configuration.buses.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fileURL), before)
    }

    func testWriteFailureDoesNotAcceptChange() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = try ConfigurationStore(fileURL: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try store.update { $0.isEnabled = true })
        XCTAssertFalse(store.configuration.isEnabled)
    }

    func testCorruptUnsupportedAndInvalidGraphFilesAreDeletedAndReset() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let valid = try JSONEncoder().encode(MixerConfiguration())
        var unsupportedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        unsupportedObject["schemaVersion"] = 1
        let unsupported = try JSONSerialization.data(withJSONObject: unsupportedObject)
        let invalidGraph = try JSONEncoder().encode(MixerConfiguration(buses: [VirtualBus(name: " ")]))

        for data in [Data("broken JSON".utf8), unsupported, invalidGraph] {
            try data.write(to: fileURL)
            let store = try ConfigurationStore(fileURL: fileURL)
            XCTAssertTrue(store.discardedInvalidConfiguration)
            XCTAssertFalse(store.configuration.isEnabled)
            XCTAssertTrue(store.configuration.outputMixes.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("configuration.json")
    }

    private func descriptor(_ uid: DeviceUID, name: String) -> AudioDeviceDescriptor {
        AudioDeviceDescriptor(uid: uid, name: name, inputChannels: 2, outputChannels: 2, sampleRate: 48000, isBlackHole: false)
    }
}
