import Foundation
import Synchronization

/// Single-producer, single-consumer planar audio ring buffer. The producer and consumer
/// exchange only atomic frame cursors; neither side waits for the other.
final class RealtimeAudioRingBuffer {
    let capacity: Int
    let channelCount: Int
    private let mask: Int
    private let planes: [UnsafeMutablePointer<Float>]
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

    init(capacity: Int = 32768, channelCount: Int = 2) {
        precondition(capacity > 0 && capacity.nonzeroBitCount == 1 && (1 ... 64).contains(channelCount))
        self.capacity = capacity
        self.channelCount = channelCount
        mask = capacity - 1
        planes = (0 ..< channelCount).map { _ in
            let plane = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
            plane.initialize(repeating: 0, count: capacity)
            return plane
        }
    }

    deinit {
        for plane in planes {
            plane.deinitialize(count: capacity)
            plane.deallocate()
        }
    }

    /// Writes a complete planar block and publishes it only after every channel is ready.
    @discardableResult
    func write(channels: UnsafeBufferPointer<UnsafePointer<Float>>, frameCount: Int) -> Int {
        guard frameCount > 0, channels.count == channelCount else { return 0 }
        let writer = writeFrame.load(ordering: .relaxed)
        let reader = readFrame.load(ordering: .acquiring)
        let occupied = Int(writer - reader)
        guard occupied >= 0, occupied <= capacity else { return 0 }
        let count = min(frameCount, capacity - occupied)
        droppedFrameCount.wrappingAdd(Int64(frameCount - count), ordering: .relaxed)
        guard count > 0 else { return 0 }
        let start = Int(writer) & mask
        let firstCount = min(count, capacity - start)

        for channel in 0 ..< channelCount {
            let source = channels[channel]
            let destination = planes[channel]
            destination.advanced(by: start).update(from: source, count: firstCount)
            if firstCount < count {
                destination.update(from: source.advanced(by: firstCount), count: count - firstCount)
            }
        }
        writeFrame.store(writer + Int64(count), ordering: .releasing)
        return count
    }

    /// Reads a complete planar block and fills underruns with silence.
    @discardableResult
    func read(channels: UnsafeBufferPointer<UnsafeMutablePointer<Float>>, frameCount: Int) -> Int {
        guard frameCount > 0, channels.count == channelCount else { return 0 }
        let reader = readFrame.load(ordering: .relaxed)
        let writer = writeFrame.load(ordering: .acquiring)
        let available = Int(writer - reader)
        guard available >= 0, available <= capacity else {
            for channel in channels {
                channel.update(repeating: 0, count: frameCount)
            }
            return 0
        }
        let count = min(frameCount, available)
        underrunFrameCount.wrappingAdd(Int64(frameCount - count), ordering: .relaxed)
        let start = Int(reader) & mask
        let firstCount = min(count, capacity - start)
        for channel in 0 ..< channelCount {
            let destination = channels[channel]
            let source = planes[channel]
            destination.update(from: source.advanced(by: start), count: firstCount)
            if firstCount < count {
                destination.advanced(by: firstCount).update(from: source, count: count - firstCount)
            }
            if count < frameCount {
                destination.advanced(by: count).update(repeating: 0, count: frameCount - count)
            }
        }
        readFrame.store(reader + Int64(count), ordering: .releasing)
        return count
    }
}
