import Foundation

/// Realtime-safe stereo summing primitive. Callers provide planar source buffers and
/// preallocated output buffers; processing performs no allocation or synchronization.
public struct StereoMixingEngine: Sendable {
    public private(set) var currentSourceGain: Float
    public private(set) var currentMainGain: Float
    private var targetSourceGain: Float
    private var targetMainGain: Float
    private let smoothingCoefficient: Float

    public init(sampleRate: Double, smoothingTime: Double = 0.01) {
        let rate = max(sampleRate, 1)
        let time = max(smoothingTime, 0.0001)
        smoothingCoefficient = 1 - exp(-1 / Float(rate * time))
        currentSourceGain = 1
        currentMainGain = 1
        targetSourceGain = 1
        targetMainGain = 1
    }

    public mutating func setSourceGain(_ gain: Float) {
        targetSourceGain = gain.isFinite ? min(max(gain, 0), Float(MixInput.maximumApplicationGain)) : 0
    }

    public mutating func setMainGain(_ gain: Float) {
        targetMainGain = gain.isFinite ? min(max(gain, 0), 1) : 0
    }

    /// Adds one stereo source to the output. Source and master gain ramps are smoothed
    /// per sample; the final hard limiter guarantees finite samples within [-1, 1].
    public mutating func mix(
        left: UnsafeBufferPointer<Float>,
        right: UnsafeBufferPointer<Float>,
        into outputLeft: UnsafeMutableBufferPointer<Float>,
        outputRight: UnsafeMutableBufferPointer<Float>,
        frameCount: Int,
        peakMeter: RealtimePeakMeter? = nil
    ) {
        let count = min(frameCount, min(left.count, min(right.count, min(outputLeft.count, outputRight.count))))
        guard count > 0 else { return }

        var contributionPeak: Float = 0
        for frame in 0 ..< count {
            currentSourceGain += (targetSourceGain - currentSourceGain) * smoothingCoefficient
            currentMainGain += (targetMainGain - currentMainGain) * smoothingCoefficient
            let gain = currentSourceGain * currentMainGain
            let leftSum = outputLeft[frame] + left[frame] * gain
            let rightSum = outputRight[frame] + right[frame] * gain
            contributionPeak = max(contributionPeak, max(abs(left[frame] * gain), abs(right[frame] * gain)))
            outputLeft[frame] = Self.limit(leftSum)
            outputRight[frame] = Self.limit(rightSum)
        }
        peakMeter?.record(peak: contributionPeak)
    }

    /// Adds a mono source to the selected side or duplicates it to both sides.
    /// The unused side is left untouched so multiple sources can be summed.
    public mutating func mix(
        mono: UnsafeBufferPointer<Float>,
        placement: MonoPlacement,
        into outputLeft: UnsafeMutableBufferPointer<Float>,
        outputRight: UnsafeMutableBufferPointer<Float>,
        frameCount: Int,
        peakMeter: RealtimePeakMeter? = nil
    ) -> Float {
        let count = min(frameCount, min(mono.count, min(outputLeft.count, outputRight.count)))
        guard count > 0 else { return 0 }

        var contributionPeak: Float = 0
        for frame in 0 ..< count {
            currentSourceGain += (targetSourceGain - currentSourceGain) * smoothingCoefficient
            currentMainGain += (targetMainGain - currentMainGain) * smoothingCoefficient
            let sample = mono[frame] * currentSourceGain * currentMainGain
            contributionPeak = max(contributionPeak, abs(sample))
            if placement != .right {
                outputLeft[frame] = Self.limit(outputLeft[frame] + sample)
            }
            if placement != .left {
                outputRight[frame] = Self.limit(outputRight[frame] + sample)
            }
        }
        peakMeter?.record(peak: contributionPeak)
        return contributionPeak
    }

    @inline(__always)
    private static func limit(_ sample: Float) -> Float {
        guard sample.isFinite else { return 0 }
        return min(max(sample, -1), 1)
    }
}
