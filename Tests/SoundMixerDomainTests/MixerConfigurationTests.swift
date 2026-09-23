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
            )]
        )

        let data = try JSONEncoder().encode(configuration)
        XCTAssertEqual(try JSONDecoder().decode(MixerConfiguration.self, from: data), configuration)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["isEnabled"] as? Bool, true)
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
}
