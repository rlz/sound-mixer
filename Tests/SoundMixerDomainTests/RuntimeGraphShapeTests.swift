import Foundation
@testable import SoundMixerDomain
import XCTest

final class RuntimeGraphShapeTests: XCTestCase {
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

    func testAddingEmptyBlackHoleRouteDoesNotCreateAnOutputRenderer() {
        let output = OutputMix(deviceUID: DeviceUID(rawValue: "speakers"))
        let route = BlackHoleRoute(
            name: "BlackHole 1/2",
            deviceUID: DeviceUID(rawValue: "blackhole"),
            channels: .stereo(left: 1, right: 2)
        )
        let before = RuntimeGraphShape(configuration: MixerConfiguration(outputMixes: [output]))
        let after = RuntimeGraphShape(configuration: MixerConfiguration(
            outputMixes: [output], blackHoleRoutes: [route]
        ))

        XCTAssertEqual(after.changedRouteKeys(from: before), [])
        XCTAssertEqual(after.changedBusIDs(from: before), [])
    }

    func testAddingBlackHoleRouteWithSourcesCreatesOnlyItsOutputRenderer() {
        let output = OutputMix(deviceUID: DeviceUID(rawValue: "speakers"))
        let route = BlackHoleRoute(
            name: "BlackHole 1/2",
            deviceUID: DeviceUID(rawValue: "blackhole"),
            channels: .stereo(left: 1, right: 2),
            mix: Mix(inputs: [MixInput(source: .application(ApplicationID(rawValue: "com.example.player")))])
        )
        let before = RuntimeGraphShape(configuration: MixerConfiguration(outputMixes: [output]))
        let after = RuntimeGraphShape(configuration: MixerConfiguration(
            outputMixes: [output], blackHoleRoutes: [route]
        ))

        XCTAssertEqual(after.changedRouteKeys(from: before), ["blackhole:\(route.id.uuidString)"])
    }
}
