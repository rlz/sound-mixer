import AudioToolbox
import Foundation
import Synchronization

/// Publishes the latest callback peak without locks or allocation. A nil reading
/// means no callback has arrived within the caller's freshness window.
public final class RealtimePeakMeter {
    private let peakBits = Atomic<UInt32>(0)
    private let updatedAt = Atomic<UInt64>(0)

    func record(buffers: UnsafePointer<AudioBufferList>, frameCount: UInt32, format: AudioStreamBasicDescription) {
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32,
              format.mChannelsPerFrame > 0
        else { return }

        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffers))
        let isNonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        var peak: Float = 0
        var sampleCount = 0
        for buffer in list {
            guard let data = buffer.mData else { continue }
            let availableSamples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let expectedSamples = isNonInterleaved
                ? Int(frameCount)
                : Int(frameCount) * Int(format.mChannelsPerFrame)
            let samples = min(availableSamples, expectedSamples)
            let values = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: samples)
            for value in values where value.isFinite {
                peak = max(peak, abs(value))
            }
            sampleCount += samples
        }
        guard sampleCount > 0 else { return }
        publish(peak)
    }

    func record(left: UnsafeBufferPointer<Float>, right: UnsafeBufferPointer<Float>, frameCount: Int) {
        let count = min(frameCount, min(left.count, right.count))
        var peak: Float = 0
        if count > 0 {
            for index in 0 ..< count {
                let leftSample = left[index]
                let rightSample = right[index]
                if leftSample.isFinite {
                    peak = max(peak, abs(leftSample))
                }
                if rightSample.isFinite {
                    peak = max(peak, abs(rightSample))
                }
            }
        }
        publish(peak)
    }

    func record(peak: Float) {
        publish(peak.isFinite ? min(max(peak, 0), 1) : 0)
    }

    func record(samples: UnsafeBufferPointer<Float>) {
        var peak: Float = 0
        for sample in samples where sample.isFinite {
            peak = max(peak, abs(sample))
        }
        publish(peak)
    }

    static func recordChannelPeaks(
        _ meters: [RealtimePeakMeter],
        buffers: UnsafePointer<AudioBufferList>,
        frameCount: UInt32,
        format: AudioStreamBasicDescription
    ) {
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32,
              Int(format.mChannelsPerFrame) == meters.count
        else { return }

        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffers))
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        if planar {
            let timestamp = DispatchTime.now().uptimeNanoseconds
            for channel in 0 ..< min(meters.count, list.count) {
                guard let data = list[channel].mData else { continue }
                let sampleCount = min(Int(frameCount), Int(list[channel].mDataByteSize) / MemoryLayout<Float>.size)
                let values = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: sampleCount)
                var peak: Float = 0
                for value in values where value.isFinite {
                    peak = max(peak, abs(value))
                }
                meters[channel].record(peak: peak, timestamp: timestamp)
            }
            return
        }

        guard let data = list.first?.mData else { return }
        let timestamp = DispatchTime.now().uptimeNanoseconds
        let availableFrames = Int(list[0].mDataByteSize) / max(1, Int(format.mBytesPerFrame))
        let count = min(Int(frameCount), availableFrames)
        let samples = data.assumingMemoryBound(to: Float.self)
        for channel in meters.indices {
            var peak: Float = 0
            for frame in 0 ..< count {
                let value = samples[frame * meters.count + channel]
                if value.isFinite {
                    peak = max(peak, abs(value))
                }
            }
            meters[channel].record(peak: peak, timestamp: timestamp)
        }
    }

    private func record(peak: Float, timestamp: UInt64) {
        let boundedPeak = peak.isFinite ? min(max(peak, 0), 1) : 0
        peakBits.store(boundedPeak.bitPattern, ordering: .relaxed)
        updatedAt.store(timestamp, ordering: .releasing)
    }

    private func publish(_ peak: Float) {
        peakBits.store(peak.bitPattern, ordering: .relaxed)
        updatedAt.store(DispatchTime.now().uptimeNanoseconds, ordering: .releasing)
    }

    func reading(now: UInt64 = DispatchTime.now().uptimeNanoseconds, maximumAge: UInt64 = 500_000_000) -> Double? {
        let timestamp = updatedAt.load(ordering: .acquiring)
        guard timestamp > 0, now >= timestamp, now - timestamp <= maximumAge else { return nil }
        let peak = Float(bitPattern: peakBits.load(ordering: .relaxed))
        guard peak.isFinite else { return 0 }
        return Double(min(max(peak, 0), 1))
    }
}
