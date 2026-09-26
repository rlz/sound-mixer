import Foundation
import Synchronization

/// Publishes a retained immutable object to realtime readers. The control thread
/// waits for existing readers before reclaiming an old value; readers never wait.
final class RealtimePublication<Value: AnyObject> {
    private let pointer = Atomic<UnsafeMutableRawPointer?>(nil)
    private let readers = Atomic<Int>(0)

    init(_ initial: Value? = nil) {
        if let initial {
            pointer.store(Unmanaged.passRetained(initial).toOpaque(), ordering: .sequentiallyConsistent)
        }
    }

    deinit {
        publish(nil)
    }

    func publish(_ next: Value?) {
        let nextPointer = next.map { Unmanaged.passRetained($0).toOpaque() }
        guard let previous = pointer.exchange(nextPointer, ordering: .sequentiallyConsistent) else { return }
        while readers.load(ordering: .sequentiallyConsistent) > 0 {
            Thread.sleep(forTimeInterval: 0.0001)
        }
        Unmanaged<Value>.fromOpaque(previous).release()
    }

    /// Every beginRead must be followed by endRead, including when the value is nil.
    @inline(__always)
    func beginRead() -> Value? {
        readers.wrappingAdd(1, ordering: .sequentiallyConsistent)
        guard let current = pointer.load(ordering: .sequentiallyConsistent) else { return nil }
        return Unmanaged<Value>.fromOpaque(current).takeUnretainedValue()
    }

    @inline(__always)
    func endRead() {
        readers.wrappingSubtract(1, ordering: .sequentiallyConsistent)
    }
}
