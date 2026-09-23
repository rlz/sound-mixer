@testable import SoundMixerDomain
import XCTest

final class StereoMixingEngineTests: XCTestCase {
    func testUnityGainsPreserveStereoSignal() {
        var engine = StereoMixingEngine(sampleRate: 48000, smoothingTime: 0.0001)
        let left: [Float] = [0.25, -0.5, 0.75]
        let right: [Float] = [-0.25, 0.5, -0.75]
        var outputLeft = [Float](repeating: 0, count: 3)
        var outputRight = [Float](repeating: 0, count: 3)

        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                outputLeft.withUnsafeMutableBufferPointer { outputLeftBuffer in
                    outputRight.withUnsafeMutableBufferPointer { outputRightBuffer in
                        engine.mix(
                            left: leftBuffer,
                            right: rightBuffer,
                            into: outputLeftBuffer,
                            outputRight: outputRightBuffer,
                            frameCount: 3
                        )
                    }
                }
            }
        }

        for index in left.indices {
            XCTAssertEqual(outputLeft[index], left[index], accuracy: 0.0001)
            XCTAssertEqual(outputRight[index], right[index], accuracy: 0.0001)
        }
    }

    func testGainChangeRampsWithoutDiscontinuityAndClipsSafely() {
        var engine = StereoMixingEngine(sampleRate: 48000, smoothingTime: 0.01)
        engine.setSourceGain(0.5)
        let source = [Float](repeating: 0.8, count: 512)
        var outputLeft = [Float](repeating: 0, count: source.count)
        var outputRight = [Float](repeating: 0, count: source.count)

        source.withUnsafeBufferPointer { input in
            outputLeft.withUnsafeMutableBufferPointer { left in
                outputRight.withUnsafeMutableBufferPointer { right in
                    engine.mix(left: input, right: input, into: left, outputRight: right, frameCount: source.count)
                }
            }
        }

        XCTAssertLessThan(outputLeft[1], outputLeft[0])
        XCTAssertGreaterThan(outputLeft[1] - outputLeft[0], -0.01)
        XCTAssertTrue(outputLeft.allSatisfy { $0.isFinite && abs($0) <= 1 })
        XCTAssertTrue(outputRight.allSatisfy { $0.isFinite && abs($0) <= 1 })

        let overload = [Float](repeating: 10, count: 8)
        var clippedLeft = [Float](repeating: 0, count: overload.count)
        var clippedRight = [Float](repeating: 0, count: overload.count)
        overload.withUnsafeBufferPointer { input in
            clippedLeft.withUnsafeMutableBufferPointer { left in
                clippedRight.withUnsafeMutableBufferPointer { right in
                    engine.mix(left: input, right: input, into: left, outputRight: right, frameCount: overload.count)
                }
            }
        }
        XCTAssertEqual(clippedLeft, [Float](repeating: 1, count: overload.count))
        XCTAssertEqual(clippedRight, [Float](repeating: 1, count: overload.count))
    }

    func testRepeatedVariableSizedBlocksStayFiniteAndBounded() {
        var engine = StereoMixingEngine(sampleRate: 44100)
        let source = [Float](repeating: 0.4, count: 257)
        var left = [Float](repeating: 0, count: source.count)
        var right = [Float](repeating: 0, count: source.count)

        for block in 1 ... 2000 {
            engine.setSourceGain(block.isMultiple(of: 2) ? 0.25 : 1)
            source.withUnsafeBufferPointer { input in
                left.withUnsafeMutableBufferPointer { outputLeft in
                    right.withUnsafeMutableBufferPointer { outputRight in
                        engine.mix(
                            left: input,
                            right: input,
                            into: outputLeft,
                            outputRight: outputRight,
                            frameCount: block % source.count
                        )
                    }
                }
            }
            XCTAssertTrue(left.allSatisfy { $0.isFinite && abs($0) <= 1 })
            XCTAssertTrue(right.allSatisfy { $0.isFinite && abs($0) <= 1 })
        }
    }
}
