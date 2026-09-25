import Foundation
@testable import SoundMixerDomain
import XCTest

final class GraphValidatorTests: XCTestCase {
    private let blackHoleUID = DeviceUID(rawValue: "blackhole")

    func testValidSharedBusAndNonoverlappingRoutes() throws {
        let application = ApplicationID(rawValue: "com.example.audio")
        let bus = VirtualBus(name: "Shared", mix: Mix(inputs: [MixInput(source: .application(application))]))
        let configuration = MixerConfiguration(
            outputMixes: [OutputMix(deviceUID: DeviceUID(rawValue: "speakers"), mix: Mix(inputs: [MixInput(source: .bus(bus.id))]))],
            buses: [bus],
            blackHoleRoutes: [
                route(channels: .mono(17), mix: Mix(inputs: [MixInput(source: .bus(bus.id))])),
                route(channels: .stereo(left: 3, right: 4))
            ]
        )

        XCTAssertNoThrow(try GraphValidator.validate(configuration))
    }

    func testMissingBusAndCyclesAreRejected() {
        let firstID = UUID()
        let secondID = UUID()
        let first = VirtualBus(id: firstID, name: "First", mix: Mix(inputs: [MixInput(source: .bus(secondID))]))
        let second = VirtualBus(id: secondID, name: "Second", mix: Mix(inputs: [MixInput(source: .bus(firstID))]))

        assertError(.missingBus(secondID), in: MixerConfiguration(buses: [first]))
        assertError(.busCycle, in: MixerConfiguration(buses: [first, second]))
        let selfReferencing = VirtualBus(id: firstID, name: "Self", mix: Mix(inputs: [MixInput(source: .bus(firstID))]))
        assertError(.busCycle, in: MixerConfiguration(buses: [selfReferencing]))
    }

    func testRouteReferencesAreValidatedAndParticipateInMixedCycles() {
        let routeID = UUID()
        let missingRouteID = UUID()
        let referencingRoute = BlackHoleRoute(
            name: "Reference",
            deviceUID: blackHoleUID,
            channels: .stereo(left: 1, right: 2),
            mix: Mix(inputs: [MixInput(source: .blackHoleRoute(missingRouteID))])
        )
        assertError(.missingRoute(missingRouteID), in: MixerConfiguration(blackHoleRoutes: [referencingRoute]))

        let busID = UUID()
        let bus = VirtualBus(id: busID, name: "Bus", mix: Mix(inputs: [MixInput(source: .blackHoleRoute(routeID))]))
        let linkedRoute = BlackHoleRoute(
            id: routeID,
            name: "Route",
            deviceUID: blackHoleUID,
            channels: .stereo(left: 1, right: 2),
            mix: Mix(inputs: [MixInput(source: .bus(busID))])
        )
        assertError(.busCycle, in: MixerConfiguration(buses: [bus], blackHoleRoutes: [linkedRoute]))
    }

    func testBlackHoleChannelSelectionsAndConflictsAreRejected() {
        assertError(.invalidChannels, in: MixerConfiguration(blackHoleRoutes: [route(channels: .mono(0))]))
        assertError(.invalidChannels, in: MixerConfiguration(blackHoleRoutes: [route(channels: .stereo(left: 3, right: 3))]))
        assertError(.blackHoleChannelConflict(blackHoleUID), in: MixerConfiguration(blackHoleRoutes: [
            route(channels: .stereo(left: 3, right: 4)), route(channels: .mono(4))
        ]))
        assertError(.blackHoleChannelConflict(blackHoleUID), in: MixerConfiguration(
            outputMixes: [OutputMix(deviceUID: blackHoleUID)],
            blackHoleRoutes: [route(channels: .mono(17))]
        ))
    }

    func testDuplicateNodesSourcesAndInvalidLevelsAreRejected() {
        let bus = VirtualBus(name: "Bus")
        assertError(.duplicateBus(bus.id), in: MixerConfiguration(buses: [bus, bus]))
        let output = OutputMix(deviceUID: DeviceUID(rawValue: "speaker"))
        assertError(.duplicateOutput(output.deviceUID), in: MixerConfiguration(outputMixes: [output, output]))
        let duplicateRoute = route(channels: .mono(1))
        assertError(.duplicateRoute(duplicateRoute.id), in: MixerConfiguration(blackHoleRoutes: [duplicateRoute, duplicateRoute]))
        let source = MixInput(source: .bus(bus.id))
        assertError(.duplicateSource, in: MixerConfiguration(
            outputMixes: [OutputMix(deviceUID: output.deviceUID, mix: Mix(inputs: [source, source]))],
            buses: [bus]
        ))
        assertError(.invalidLevel, in: MixerConfiguration(buses: [VirtualBus(name: "Invalid", mix: Mix(level: .nan))]))
        assertError(.invalidLevel, in: MixerConfiguration(buses: [VirtualBus(name: "Invalid", mix: Mix(inputs: [
            MixInput(source: .application(ApplicationID(rawValue: "app")), level: MixInput.maximumApplicationGain + 0.01)
        ]))]))
    }

    func testApplicationGainCanExceedUnityOnlyWithinItsOwnRow() throws {
        let app = MixInput(source: .application(ApplicationID(rawValue: "app")), level: MixInput.maximumApplicationGain)
        XCTAssertNoThrow(try GraphValidator.validate(MixerConfiguration(buses: [VirtualBus(name: "Boosted", mix: Mix(inputs: [app]))])))

        let device = MixInput(source: .inputDevice(DeviceUID(rawValue: "mic")), level: 2)
        assertError(.invalidLevel, in: MixerConfiguration(buses: [VirtualBus(name: "Invalid", mix: Mix(inputs: [device]))]))
        assertError(.invalidLevel, in: MixerConfiguration(buses: [VirtualBus(name: "Invalid", mix: Mix(level: 2, inputs: [app]))]))
    }

    func testMissingDevicesAreRetainedButIncompatibleFormatsAreReported() throws {
        let inputUID = DeviceUID(rawValue: "mic")
        let outputUID = DeviceUID(rawValue: "speaker")
        let route = route(channels: .stereo(left: 3, right: 4))
        let configuration = MixerConfiguration(
            outputMixes: [OutputMix(deviceUID: outputUID, mix: Mix(inputs: [MixInput(source: .inputDevice(inputUID))]))],
            blackHoleRoutes: [route]
        )
        XCTAssertNoThrow(try GraphValidator.validate(configuration))
        XCTAssertEqual(GraphValidator.deviceIssues(for: configuration, devices: []), [
            .missingDevice(.input(inputUID)), .missingDevice(.output(outputUID)), .missingDevice(.blackHoleRoute(route.id))
        ])

        let issues = GraphValidator.deviceIssues(for: configuration, devices: [
            device(inputUID, input: 4, output: 0, rate: 48000),
            device(outputUID, input: 0, output: 1, rate: .nan),
            device(blackHoleUID, input: 0, output: 3, rate: 44100, isBlackHole: false)
        ])
        XCTAssertEqual(issues, [
            .unsupportedChannelCount(.input(inputUID)),
            .invalidSampleRate(.output(outputUID)), .unsupportedChannelCount(.output(outputUID)),
            .notBlackHole(.blackHoleRoute(route.id)), .channelOutOfRange(.blackHoleRoute(route.id))
        ])
    }

    func testDifferentValidSampleRatesCanBeConverted() {
        let inputUID = DeviceUID(rawValue: "mic")
        let outputUID = DeviceUID(rawValue: "speaker")
        let configuration = MixerConfiguration(outputMixes: [OutputMix(
            deviceUID: outputUID, mix: Mix(inputs: [MixInput(source: .inputDevice(inputUID))])
        )])
        XCTAssertTrue(GraphValidator.deviceIssues(for: configuration, devices: [
            device(inputUID, input: 1, output: 0, rate: 44100),
            device(outputUID, input: 0, output: 2, rate: 48000)
        ]).isEmpty)
    }

    private func route(channels: BlackHoleChannels, mix: Mix = Mix()) -> BlackHoleRoute {
        BlackHoleRoute(name: "Route", deviceUID: blackHoleUID, channels: channels, mix: mix)
    }

    private func device(
        _ uid: DeviceUID,
        input: Int,
        output: Int,
        rate: Double,
        isBlackHole: Bool = false
    ) -> AudioDeviceDescriptor {
        AudioDeviceDescriptor(
            uid: uid, name: uid.rawValue, inputChannels: input,
            outputChannels: output, sampleRate: rate, isBlackHole: isBlackHole
        )
    }

    private func assertError(
        _ expected: GraphValidationError,
        in configuration: MixerConfiguration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try GraphValidator.validate(configuration), file: file, line: line) { error in
            XCTAssertEqual(error as? GraphValidationError, expected, file: file, line: line)
        }
    }
}
