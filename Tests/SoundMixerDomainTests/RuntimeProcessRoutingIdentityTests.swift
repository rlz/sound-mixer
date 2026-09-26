import Foundation
@testable import SoundMixerDomain
import XCTest

final class RuntimeProcessRoutingIdentityTests: XCTestCase {
    func testUnchangedMultiprocessApplicationIsEqualRegardlessOfDiscoveryOrder() {
        let first = identity(pid: 101)
        let second = identity(pid: 102)
        let idle = identity(pid: 103, active: false)
        let snapshot = [first, second, idle]

        XCTAssertTrue(RuntimeProcessRoutingIdentity.matches(snapshot, snapshot))
        XCTAssertTrue(RuntimeProcessRoutingIdentity.matches(snapshot, [idle, second, first]))
    }

    func testProcessReplacementAndActivityChangesRequireReconciliation() {
        let snapshot = [identity(pid: 101), identity(pid: 102)]
        XCTAssertFalse(RuntimeProcessRoutingIdentity.matches(snapshot, [identity(pid: 101), identity(pid: 104)]))
        XCTAssertFalse(RuntimeProcessRoutingIdentity.matches(snapshot, [identity(pid: 101), identity(pid: 102, active: false)]))
        XCTAssertFalse(RuntimeProcessRoutingIdentity.matches(snapshot, [identity(pid: 101)]))
        XCTAssertFalse(RuntimeProcessRoutingIdentity.matches(snapshot, [identity(pid: 101), identity(pid: 101)]))
    }

    func testApplicationIdentityAndDuplicateCountsArePreserved() {
        let first = identity(pid: 101)
        let other = RuntimeProcessRoutingIdentity(applicationID: "com.example.other", processID: 101, isProducingOutput: true)
        XCTAssertFalse(RuntimeProcessRoutingIdentity.matches([first], [other]))
        XCTAssertTrue(RuntimeProcessRoutingIdentity.matches([first, first], [first, first]))
        XCTAssertFalse(RuntimeProcessRoutingIdentity.matches([first, first], [first]))
        XCTAssertTrue(RuntimeProcessRoutingIdentity.matches([], []))
    }

    private func identity(pid: Int32, active: Bool = true) -> RuntimeProcessRoutingIdentity {
        RuntimeProcessRoutingIdentity(applicationID: "com.example.player", processID: pid, isProducingOutput: active)
    }
}
