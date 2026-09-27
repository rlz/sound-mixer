import Foundation
@testable import SoundMixerDomain
import XCTest

final class RuntimeGraphShapeTests: XCTestCase {
    func testGainEditsDoNotReplaceOutputRenderersOrBusMeterPumps() {
        let source = SourceReference.application(ApplicationID(rawValue: "com.example.player"))
        let bus = VirtualBus(name: "Bus", mix: Mix(inputs: [MixInput(source: source)]))
        let output = OutputMix(deviceUID: DeviceUID(rawValue: "speakers"), mix: Mix(inputs: [MixInput(source: .bus(bus.id))]))
        let original = MixerConfiguration(outputMixes: [output], buses: [bus])
        let before = RuntimeGraphShape(configuration: original)
        let edits: [(inout MixerConfiguration) -> Void] = [
            { $0.outputMixes[0].mix.inputs[0].level = 0.3 },
            { $0.buses[0].mix.inputs[0].level = 0.3 },
            { $0.buses[0].mix.level = 0.3 }
        ]
        for (index, edit) in edits.enumerated() {
            var changed = original
            edit(&changed)
            let after = RuntimeGraphShape(configuration: changed)
            XCTAssertEqual(after.changedRouteKeys(from: before), [], "Gain edit \(index) replaces an output renderer")
            XCTAssertEqual(after.changedBusIDs(from: before), [], "Gain edit \(index) replaces a meter pump")
        }
    }

    func testChannelGainAndRoutingEditsPreserveRenderers() {
        let input = MixInput(source: .inputDevice(DeviceUID(rawValue: "mic")), channelRouting: [[1], [2]], channelLevels: [1, 1])
        let output = OutputMix(deviceUID: DeviceUID(rawValue: "speakers"), mix: Mix(inputs: [input]))
        let original = MixerConfiguration(outputMixes: [output])
        let before = RuntimeGraphShape(configuration: original)
        var changed = original
        changed.outputMixes[0].mix.inputs[0].channelLevels = [0.3, 0.7]
        XCTAssertEqual(RuntimeGraphShape(configuration: changed).changedRouteKeys(from: before), [])
        changed.outputMixes[0].mix.inputs[0].channelRouting = [[1, 2], []]
        XCTAssertEqual(RuntimeGraphShape(configuration: changed).changedRouteKeys(from: before), [])
    }

    func testIndependentVirtualBusCreationAndDeletionLeaveExistingRoutesAndMetersUntouched() {
        let source = SourceReference.application(ApplicationID(rawValue: "com.example.player"))
        let existingBus = VirtualBus(name: "Existing", mix: Mix(inputs: [MixInput(source: source)]))
        let newBus = VirtualBus(name: "New")
        let output = OutputMix(
            deviceUID: DeviceUID(rawValue: "speakers"),
            mix: Mix(inputs: [MixInput(source: .bus(existingBus.id))])
        )
        let before = RuntimeGraphShape(configuration: MixerConfiguration(outputMixes: [output], buses: [existingBus]))
        let after = RuntimeGraphShape(configuration: MixerConfiguration(outputMixes: [output], buses: [existingBus, newBus]))

        XCTAssertEqual(after.changedRouteKeys(from: before), [])
        XCTAssertEqual(after.changedBusIDs(from: before), [newBus.id])
        XCTAssertEqual(before.changedRouteKeys(from: after), [])
        XCTAssertEqual(before.changedBusIDs(from: after), [newBus.id])
    }

    func testAddingOrRemovingAnEmptyBusIsOnlyAConfigurationChange() {
        let existingBus = VirtualBus(name: "Existing")
        let addedBus = VirtualBus(name: "New")
        let before = MixerConfiguration(buses: [existingBus])
        let after = MixerConfiguration(buses: [existingBus, addedBus])

        XCTAssertTrue(RuntimeGraphShape.hasOnlyEmptyBusChanges(from: before, to: after))
        XCTAssertTrue(RuntimeGraphShape.hasOnlyEmptyBusChanges(from: after, to: before))
    }

    func testAddingABusWithAnInputIsNotAConfigurationOnlyChange() {
        let before = MixerConfiguration()
        let populatedBus = VirtualBus(
            name: "New",
            mix: Mix(inputs: [MixInput(source: .application(ApplicationID(rawValue: "com.example.player")))])
        )
        let after = MixerConfiguration(buses: [populatedBus])

        XCTAssertFalse(RuntimeGraphShape.hasOnlyEmptyBusChanges(from: before, to: after))
    }

    func testBusEditChangesOnlyItsConsumersAndDependentBusMeters() {
        let source = SourceReference.application(ApplicationID(rawValue: "com.example.player"))
        let addedSource = SourceReference.application(ApplicationID(rawValue: "com.example.voice"))
        let upstream = VirtualBus(name: "Upstream", mix: Mix(inputs: [MixInput(source: source)]))
        let downstream = VirtualBus(name: "Downstream", mix: Mix(inputs: [MixInput(source: .bus(upstream.id))]))
        let dependentOutput = OutputMix(
            deviceUID: DeviceUID(rawValue: "speakers"),
            mix: Mix(inputs: [MixInput(source: .bus(downstream.id))])
        )
        let independentOutput = OutputMix(
            deviceUID: DeviceUID(rawValue: "headphones"),
            mix: Mix(inputs: [MixInput(source: source)])
        )
        let before = RuntimeGraphShape(configuration: MixerConfiguration(
            outputMixes: [dependentOutput, independentOutput], buses: [upstream, downstream]
        ))
        var changedUpstream = upstream
        changedUpstream.mix.inputs.append(MixInput(source: addedSource))
        let after = RuntimeGraphShape(configuration: MixerConfiguration(
            outputMixes: [dependentOutput, independentOutput], buses: [changedUpstream, downstream]
        ))

        XCTAssertEqual(after.changedRouteKeys(from: before), ["output:speakers"])
        XCTAssertEqual(after.changedBusIDs(from: before), [upstream.id, downstream.id])
    }

    func testRenamingBusDoesNotChangeRenderingShape() {
        let bus = VirtualBus(name: "Original")
        let output = OutputMix(
            deviceUID: DeviceUID(rawValue: "speakers"),
            mix: Mix(inputs: [MixInput(source: .bus(bus.id))])
        )
        let before = RuntimeGraphShape(configuration: MixerConfiguration(outputMixes: [output], buses: [bus]))
        var renamed = bus
        renamed.name = "Renamed"
        let after = RuntimeGraphShape(configuration: MixerConfiguration(outputMixes: [output], buses: [renamed]))

        XCTAssertEqual(after.changedRouteKeys(from: before), [])
        XCTAssertEqual(after.changedBusIDs(from: before), [])
    }
}
