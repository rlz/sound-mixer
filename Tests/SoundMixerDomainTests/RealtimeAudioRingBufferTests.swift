@testable import SoundMixerDomain
import XCTest

final class RealtimeAudioRingBufferTests: XCTestCase {
    func testWraparoundAndUnderrunPreserveChannelSamples() {
        let ring = RealtimeAudioRingBuffer(capacity: 8, channelCount: 2)
        let left: [Float] = [0, 1, 2, 3, 4, 5]
        let right: [Float] = [10, 11, 12, 13, 14, 15]
        write(ring, left: left, right: right)
        XCTAssertEqual(read(ring, frames: 4), [[0, 1, 2, 3], [10, 11, 12, 13]])

        write(ring, left: [6, 7, 8, 9, 10, 11], right: [16, 17, 18, 19, 20, 21])
        XCTAssertEqual(read(ring, frames: 8), [[4, 5, 6, 7, 8, 9, 10, 11], [14, 15, 16, 17, 18, 19, 20, 21]])
        XCTAssertEqual(read(ring, frames: 2), [[0, 0], [0, 0]])
        XCTAssertEqual(ring.underrunFrames, 2)
    }

    func testFullQueueDropsNewestFrames() {
        let ring = RealtimeAudioRingBuffer(capacity: 4, channelCount: 2)
        write(ring, left: [1, 2, 3, 4], right: [5, 6, 7, 8])
        write(ring, left: [9, 10], right: [11, 12])
        XCTAssertEqual(ring.droppedFrames, 2)
        XCTAssertEqual(read(ring, frames: 4), [[1, 2, 3, 4], [5, 6, 7, 8]])
    }

    private func write(_ ring: RealtimeAudioRingBuffer, left: [Float], right: [Float]) {
        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                let channels = [leftBuffer.baseAddress!, rightBuffer.baseAddress!]
                channels.withUnsafeBufferPointer { pointers in
                    _ = ring.write(channels: pointers, frameCount: left.count)
                }
            }
        }
    }

    private func read(_ ring: RealtimeAudioRingBuffer, frames: Int) -> [[Float]] {
        var left = [Float](repeating: -1, count: frames)
        var right = [Float](repeating: -1, count: frames)
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                let channels = [leftBuffer.baseAddress!, rightBuffer.baseAddress!]
                channels.withUnsafeBufferPointer { pointers in
                    _ = ring.read(channels: pointers, frameCount: frames)
                }
            }
        }
        return [left, right]
    }
}
