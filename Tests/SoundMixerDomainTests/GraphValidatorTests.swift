import Foundation
@testable import SoundMixerDomain
import XCTest

final class GraphValidatorTests: XCTestCase {
    func testValidSharedBusGraph() throws {
        let application = ApplicationID(rawValue: "com.example.audio")
        let bus = VirtualBus(name: "Shared", mix: Mix(inputs: [MixInput(source: .application(application))]))
        let configuration = MixerConfiguration(
            outputMixes: [OutputMix(deviceUID: DeviceUID(rawValue: "speakers"), mix: Mix(inputs: [MixInput(source: .bus(bus.id))]))],
            buses: [bus]
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

    func testDuplicateNodesSourcesAndInvalidLevelsAreRejected() {
        let bus = VirtualBus(name: "Bus")
        assertError(.duplicateBus(bus.id), in: MixerConfiguration(buses: [bus, bus]))
        let output = OutputMix(deviceUID: DeviceUID(rawValue: "speaker"))
        assertError(.duplicateOutput(output.deviceUID), in: MixerConfiguration(outputMixes: [output, output]))
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

    func testApplicationGainCanExceedUnityOnlyAtGlobalSourceLevel() throws {
        let source = SourceReference.application(ApplicationID(rawValue: "app"))
        let app = MixInput(source: source)
        let bus = VirtualBus(name: "Boosted", mix: Mix(inputs: [app]))
        XCTAssertNoThrow(try GraphValidator.validate(MixerConfiguration(
            buses: [bus], sourceLevels: [SourceLevel(source: source, level: MixInput.maximumApplicationGain)]
        )))
        var boostedRow = bus
        boostedRow.mix.inputs[0].level = 2
        assertError(.invalidLevel, in: MixerConfiguration(buses: [boostedRow]))
        assertError(.invalidLevel, in: MixerConfiguration(
            buses: [bus], sourceLevels: [SourceLevel(source: source, level: MixInput.maximumApplicationGain + 0.01)]
        ))

        let device = MixInput(source: .inputDevice(DeviceUID(rawValue: "mic")), level: 2)
        assertError(.invalidLevel, in: MixerConfiguration(buses: [VirtualBus(name: "Invalid", mix: Mix(inputs: [device]))]))
        assertError(.invalidLevel, in: MixerConfiguration(buses: [VirtualBus(name: "Invalid", mix: Mix(level: 2, inputs: [app]))]))
    }

    func testMissingDevicesAreRetainedButIncompatibleFormatsAreReported() throws {
        let inputUID = DeviceUID(rawValue: "mic")
        let outputUID = DeviceUID(rawValue: "speaker")
        let configuration = MixerConfiguration(
            outputMixes: [OutputMix(deviceUID: outputUID, mix: Mix(inputs: [MixInput(source: .inputDevice(inputUID))]))]
        )
        XCTAssertNoThrow(try GraphValidator.validate(configuration))
        XCTAssertEqual(GraphValidator.deviceIssues(for: configuration, devices: []), [
            .missingDevice(.input(inputUID)), .missingDevice(.output(outputUID))
        ])

        let issues = GraphValidator.deviceIssues(for: configuration, devices: [
            device(inputUID, input: 65, output: 0, rate: 48000),
            device(outputUID, input: 0, output: 65, rate: .nan)
        ])
        XCTAssertEqual(issues, [
            .unsupportedChannelCount(.input(inputUID)),
            .invalidSampleRate(.output(outputUID))
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

    private func device(
        _ uid: DeviceUID,
        input: Int,
        output: Int,
        rate: Double
    ) -> AudioDeviceDescriptor {
        AudioDeviceDescriptor(
            uid: uid, name: uid.rawValue, inputChannels: input,
            outputChannels: output, sampleRate: rate
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
