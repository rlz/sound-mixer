@testable import SoundMixerDomain
import XCTest

final class AudioGraphRendererDeviceActivityTests: XCTestCase {
    func testDisabledInputFallsSilentAndRecoversWhenEnabled() throws {
        let uid = DeviceUID(rawValue: "microphone")
        let input = MixInput(
            source: .inputDevice(uid), channelRouting: [[1, 2]], channelLevels: [1]
        )
        let output = OutputMix(deviceUID: DeviceUID(rawValue: "speakers"), mix: Mix(inputs: [input]))
        let ring = RealtimeAudioRingBuffer(channelCount: 1)
        let source = [Float](repeating: 0.5, count: 4096)
        var left = [Float](repeating: 0, count: source.count)
        var right = [Float](repeating: 0, count: source.count)
        let enabled = try MixGraphSnapshot(configuration: MixerConfiguration(outputMixes: [output]))
        let renderer = AudioGraphRenderer(
            graph: enabled, output: output, sourceRings: ["input:microphone": ring],
            targetKey: "output:speakers", meters: [:]
        )

        func render(_ graph: MixGraphSnapshot) {
            renderer.updateGains(from: graph)
            source.withUnsafeBufferPointer { samples in
                let channels = [samples.baseAddress!]
                channels.withUnsafeBufferPointer { pointers in
                    _ = ring.write(channels: pointers, frameCount: source.count)
                }
            }
            left.withUnsafeMutableBufferPointer { leftBuffer in
                right.withUnsafeMutableBufferPointer { rightBuffer in
                    let channels = [leftBuffer.baseAddress!, rightBuffer.baseAddress!]
                    channels.withUnsafeBufferPointer { pointers in
                        renderer.render(channels: pointers, frameCount: source.count)
                    }
                }
            }
        }

        render(enabled)
        XCTAssertEqual(left.last ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(right.last ?? 0, 0.5, accuracy: 0.001)

        let disabled = try MixGraphSnapshot(configuration: MixerConfiguration(
            outputMixes: [output], hiddenDeviceUIDs: [uid]
        ))
        render(disabled)
        XCTAssertLessThan(abs(left.last ?? 1), 0.001)
        XCTAssertLessThan(abs(right.last ?? 1), 0.001)

        render(enabled)
        XCTAssertEqual(left.last ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(right.last ?? 0, 0.5, accuracy: 0.001)
    }
}
