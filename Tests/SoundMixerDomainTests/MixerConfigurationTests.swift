import Foundation
@testable import SoundMixerDomain
import XCTest

final class MixerConfigurationTests: XCTestCase {
    func testConfigurationRoundTripsEveryReferenceAndLevel() throws {
        let busID = try XCTUnwrap(UUID(uuidString: "1F15C08E-A6CE-4975-B03D-88E559859888"))
        let routeID = try XCTUnwrap(UUID(uuidString: "899FC01B-A279-4785-97EC-31F577CDAB65"))
        let inputUID = DeviceUID(rawValue: "AppleUSBAudioEngine:Vendor:Mic:123")
        let outputUID = DeviceUID(rawValue: "AppleHDAEngineOutput:1B,0,1,2:0")
        let blackHoleUID = DeviceUID(rawValue: "BlackHole64ch_UID")
        let bus = VirtualBus(
            id: busID,
            name: "Stream",
            mix: Mix(level: 0.75, inputs: [MixInput(source: .inputDevice(inputUID), level: 0.25, monoPlacement: .left)])
        )
        let configuration = MixerConfiguration(
            isEnabled: true,
            outputMixes: [OutputMix(deviceUID: outputUID, mix: Mix(level: 0.9, inputs: [
                MixInput(source: .bus(busID), level: 0.5),
                MixInput(source: .application(ApplicationID(rawValue: "com.example.player")), level: 0.6, monoPlacement: .right)
            ]))],
            buses: [bus],
            blackHoleRoutes: [BlackHoleRoute(
                id: routeID,
                name: "Call",
                deviceUID: blackHoleUID,
                channels: .stereo(left: 3, right: 4),
                mix: Mix(level: 0.8, inputs: [MixInput(source: .bus(busID))])
            )],
            knownDevices: [
                KnownDevice(uid: inputUID, lastKnownName: "USB Microphone"),
                KnownDevice(uid: outputUID, lastKnownName: "Studio Speakers"),
                KnownDevice(uid: blackHoleUID, lastKnownName: "BlackHole 64ch")
            ]
        )

        let data = try JSONEncoder().encode(configuration)
        XCTAssertEqual(try JSONDecoder().decode(MixerConfiguration.self, from: data), configuration)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, MixerConfiguration.currentSchemaVersion)
        XCTAssertEqual(object["isEnabled"] as? Bool, true)
        XCTAssertEqual((object["knownDevices"] as? [[String: String]])?.count, 3)
        let outputMixes = try XCTUnwrap(object["outputMixes"] as? [[String: Any]])
        let mix = try XCTUnwrap(outputMixes[0]["mix"] as? [String: Any])
        let inputs = try XCTUnwrap(mix["inputs"] as? [[String: Any]])
        XCTAssertEqual((inputs[0]["source"] as? [String: String])?["kind"], "bus")
        XCTAssertEqual((inputs[0]["source"] as? [String: String])?["id"], busID.uuidString)
    }

    func testMonoChannelAndDuplicateNamesKeepSeparateIdentities() throws {
        let first = VirtualBus(name: "Same")
        let second = VirtualBus(name: "Same")
        let route = BlackHoleRoute(name: "Same", deviceUID: DeviceUID(rawValue: "blackhole"), channels: .mono(17))
        let configuration = MixerConfiguration(buses: [first, second], blackHoleRoutes: [route])

        let restored = try JSONDecoder().decode(MixerConfiguration.self, from: JSONEncoder().encode(configuration))
        XCTAssertNotEqual(restored.buses[0].id, restored.buses[1].id)
        XCTAssertEqual(restored.buses[0].name, restored.buses[1].name)
        XCTAssertEqual(restored.blackHoleRoutes[0].channels, .mono(17))
        XCTAssertEqual(restored.blackHoleRoutes[0].deviceUID.rawValue, "blackhole")
    }

    func testMalformedTaggedValuesAreRejected() {
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(SourceReference.self, from: Data(#"{"kind":"unknown","id":"x"}"#.utf8)))
        XCTAssertThrowsError(try decoder.decode(SourceReference.self, from: Data(#"{"kind":"bus","id":"not-a-uuid"}"#.utf8)))
        XCTAssertThrowsError(try decoder.decode(BlackHoleChannels.self, from: Data(#"{"mode":"stereo","channels":[3]}"#.utf8)))
        XCTAssertThrowsError(try decoder.decode(BlackHoleChannels.self, from: Data(#"{"mode":"mono","channels":[1,2]}"#.utf8)))
    }

    func testKnownNamesFollowReferencedUIDsAndFallbackToUID() {
        let inputUID = DeviceUID(rawValue: "input-1")
        let outputUID = DeviceUID(rawValue: "output-1")
        let routeUID = DeviceUID(rawValue: "blackhole-1")
        let unrelatedUID = DeviceUID(rawValue: "unrelated")
        let input = MixInput(source: .inputDevice(inputUID))
        var configuration = MixerConfiguration(
            outputMixes: [OutputMix(deviceUID: outputUID, mix: Mix(inputs: [input]))],
            blackHoleRoutes: [BlackHoleRoute(name: "Route", deviceUID: routeUID, channels: .mono(1))],
            knownDevices: [KnownDevice(uid: outputUID, lastKnownName: "Saved Output")]
        )

        XCTAssertEqual(configuration.deviceDisplayName(for: outputUID), "Saved Output")
        XCTAssertEqual(configuration.deviceDisplayName(for: inputUID), inputUID.rawValue)
        XCTAssertEqual(Set(configuration.knownDevices.map(\.uid)), [inputUID, outputUID, routeUID])

        configuration.reconcileKnownDevices(with: [
            descriptor(uid: inputUID, name: "USB Mic"),
            descriptor(uid: outputUID, name: "Renamed Output"),
            descriptor(uid: unrelatedUID, name: "Unused")
        ])
        XCTAssertEqual(configuration.deviceDisplayName(for: inputUID), "USB Mic")
        XCTAssertEqual(configuration.deviceDisplayName(for: outputUID), "Renamed Output")
        XCTAssertEqual(configuration.deviceDisplayName(for: routeUID), routeUID.rawValue)
        XCTAssertFalse(configuration.knownDevices.contains { $0.uid == unrelatedUID })

        configuration.outputMixes.removeAll()
        configuration.reconcileKnownDevices(with: [])
        XCTAssertEqual(configuration.knownDevices.map(\.uid), [routeUID])
        XCTAssertEqual(configuration.deviceDisplayName(for: routeUID), routeUID.rawValue)
    }

    func testUnsupportedVersionAndDuplicateMetadataAreRejected() throws {
        let configuration = MixerConfiguration(outputMixes: [OutputMix(deviceUID: DeviceUID(rawValue: "speaker"))])
        let data = try JSONEncoder().encode(configuration)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        object["schemaVersion"] = 1
        XCTAssertThrowsError(try JSONDecoder().decode(MixerConfiguration.self, from: JSONSerialization.data(withJSONObject: object)))

        object["schemaVersion"] = 3
        let knownDevices = try XCTUnwrap(object["knownDevices"] as? [[String: Any]])
        object["knownDevices"] = knownDevices + knownDevices
        XCTAssertThrowsError(try JSONDecoder().decode(MixerConfiguration.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    private func descriptor(uid: DeviceUID, name: String) -> AudioDeviceDescriptor {
        AudioDeviceDescriptor(uid: uid, name: name, inputChannels: 2, outputChannels: 2, sampleRate: 48000, isBlackHole: false)
    }
}
