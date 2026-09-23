import Foundation
import Synchronization

/// Single-producer, single-consumer planar audio queue. The producer and consumer
/// exchange only atomic frame cursors; neither side waits for the other.
final class RealtimeStereoRingBuffer {
    let capacity: Int
    private let mask: Int
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private let readFrame = Atomic<Int64>(0)
    private let writeFrame = Atomic<Int64>(0)
    private let droppedFrameCount = Atomic<Int64>(0)
    private let underrunFrameCount = Atomic<Int64>(0)

    var droppedFrames: Int64 {
        droppedFrameCount.load(ordering: .relaxed)
    }

    var underrunFrames: Int64 {
        underrunFrameCount.load(ordering: .relaxed)
    }

    func recordDroppedFrames(_ count: Int) {
        guard count > 0 else { return }
        droppedFrameCount.wrappingAdd(Int64(count), ordering: .relaxed)
    }

    init(capacity: Int = 32768) {
        precondition(capacity > 0 && capacity.nonzeroBitCount == 1)
        self.capacity = capacity
        mask = capacity - 1
        left = .allocate(capacity: capacity)
        right = .allocate(capacity: capacity)
        left.initialize(repeating: 0, count: capacity)
        right.initialize(repeating: 0, count: capacity)
    }

    deinit {
        left.deinitialize(count: capacity)
        right.deinitialize(count: capacity)
        left.deallocate()
        right.deallocate()
    }

    /// Writes as many frames as fit. Excess input is dropped instead of blocking
    /// the capture callback; the returned count is available for diagnostics.
    @discardableResult
    func write(
        left sourceLeft: UnsafeBufferPointer<Float>,
        right sourceRight: UnsafeBufferPointer<Float>,
        frameCount: Int
    ) -> Int {
        guard frameCount > 0 else { return 0 }
        let writer = writeFrame.load(ordering: .relaxed)
        let reader = readFrame.load(ordering: .acquiring)
        let occupied = Int(writer - reader)
        guard occupied >= 0, occupied <= capacity else { return 0 }
        let count = min(frameCount, min(capacity - occupied, min(sourceLeft.count, sourceRight.count)))
        droppedFrameCount.wrappingAdd(Int64(frameCount - count), ordering: .relaxed)
        guard count > 0 else { return 0 }

        for offset in 0 ..< count {
            let index = (Int(writer) + offset) & mask
            left[index] = sourceLeft[offset]
            right[index] = sourceRight[offset]
        }
        writeFrame.store(writer + Int64(count), ordering: .releasing)
        return count
    }

    /// Reads available frames and fills any underrun with silence.
    @discardableResult
    func read(
        into outputLeft: UnsafeMutableBufferPointer<Float>,
        _ outputRight: UnsafeMutableBufferPointer<Float>,
        frameCount: Int
    ) -> Int {
        guard frameCount > 0 else { return 0 }
        let reader = readFrame.load(ordering: .relaxed)
        let writer = writeFrame.load(ordering: .acquiring)
        let available = Int(writer - reader)
        guard available >= 0, available <= capacity else {
            outputLeft.update(repeating: 0)
            outputRight.update(repeating: 0)
            return 0
        }
        let count = min(frameCount, min(available, min(outputLeft.count, outputRight.count)))
        underrunFrameCount.wrappingAdd(Int64(frameCount - count), ordering: .relaxed)
        for offset in 0 ..< count {
            let index = (Int(reader) + offset) & mask
            outputLeft[offset] = left[index]
            outputRight[offset] = right[index]
        }
        if count < frameCount {
            outputLeft[count ..< min(frameCount, outputLeft.count)].update(repeating: 0)
            outputRight[count ..< min(frameCount, outputRight.count)].update(repeating: 0)
        }
        readFrame.store(reader + Int64(count), ordering: .releasing)
        return count
    }
}
