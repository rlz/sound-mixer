import AudioToolbox
import Foundation

struct AudioQueueDiagnostics: Equatable {
    let droppedFrames: Int64
    let underrunFrames: Int64
}

private final class SourceBuffer {
    let channelCount: Int
    private let planes: [UnsafeMutablePointer<Float>]
    let sourcePlanePointers: UnsafeMutablePointer<UnsafePointer<Float>>
    private let capacity: Int
    var outputRemainder = 0.0

    init(capacity: Int, channelCount: Int) {
        self.capacity = capacity
        self.channelCount = channelCount
        planes = (0 ..< channelCount).map { _ in
            let plane = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
            plane.initialize(repeating: 0, count: capacity)
            return plane
        }
        sourcePlanePointers = .allocate(capacity: channelCount)
        for channel in 0 ..< channelCount {
            sourcePlanePointers.advanced(by: channel).initialize(to: UnsafePointer(planes[channel]))
        }
    }

    deinit {
        for plane in planes {
            plane.deinitialize(count: capacity)
            plane.deallocate()
        }
        sourcePlanePointers.deinitialize(count: channelCount)
        sourcePlanePointers.deallocate()
    }

    func convert(
        buffers: UnsafePointer<AudioBufferList>,
        frames: UInt32,
        format: AudioStreamBasicDescription
    ) -> (frameCount: Int, droppedFrames: Int)? {
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32,
              (1 ... 64).contains(format.mChannelsPerFrame),
              format.mSampleRate.isFinite,
              (8000 ... 384_000).contains(format.mSampleRate)
        else { return nil }

        let inputFrames = Int(frames)
        guard inputFrames > 0, inputFrames <= capacity else { return nil }
        let channelCount = Int(format.mChannelsPerFrame)
        guard channelCount <= self.channelCount else { return nil }
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffers))
        let nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        guard hasEnoughData(
            list: list,
            inputFrames: inputFrames,
            channelCount: channelCount,
            nonInterleaved: nonInterleaved
        ) else { return nil }

        let expectedFrames = Double(inputFrames) * 48000 / format.mSampleRate + outputRemainder
        let convertedFrames = Int(expectedFrames)
        outputRemainder = expectedFrames - Double(convertedFrames)
        let outputFrames = min(capacity, convertedFrames)
        guard outputFrames > 0 else { return nil }
        let source = SourceAudioBlock(
            buffers: list,
            channelCount: channelCount,
            isPlanar: nonInterleaved,
            sampleRate: format.mSampleRate
        )
        for channel in 0 ..< channelCount {
            resample(
                channel: channel,
                frames: outputFrames,
                inputFrames: inputFrames,
                source: source
            )
        }
        if channelCount < self.channelCount {
            for channel in channelCount ..< self.channelCount {
                planes[channel].update(repeating: 0, count: outputFrames)
            }
        }
        return (outputFrames, convertedFrames - outputFrames)
    }

    private func hasEnoughData(
        list: UnsafeMutableAudioBufferListPointer,
        inputFrames: Int,
        channelCount: Int,
        nonInterleaved: Bool
    ) -> Bool {
        let sampleSize = MemoryLayout<Float>.size
        let requiredBytes = inputFrames * (nonInterleaved ? sampleSize : channelCount * sampleSize)
        guard let first = list.first, Int(first.mDataByteSize) >= requiredBytes else { return false }
        if nonInterleaved {
            guard list.count >= channelCount else { return false }
            for channel in 0 ..< channelCount where Int(list[channel].mDataByteSize) < inputFrames * sampleSize {
                return false
            }
        }
        return true
    }

    private func resample(
        channel: Int,
        frames: Int,
        inputFrames: Int,
        source: SourceAudioBlock
    ) {
        guard let data = source.buffers[source.isPlanar ? channel : 0].mData else { return }
        let samples = data.assumingMemoryBound(to: Float.self)
        for frame in 0 ..< frames {
            let position = min(Double(inputFrames - 1), Double(frame) * source.sampleRate / 48000)
            let inputFrame = Int(position)
            let nextFrame = min(inputFrames - 1, inputFrame + 1)
            let fraction = Float(position - Double(inputFrame))
            let start = source.isPlanar ? inputFrame : inputFrame * source.channelCount + channel
            let end = source.isPlanar ? nextFrame : nextFrame * source.channelCount + channel
            planes[channel][frame] = samples[start] + (samples[end] - samples[start]) * fraction
        }
    }
}

private struct SourceAudioBlock {
    let buffers: UnsafeMutableAudioBufferListPointer
    let channelCount: Int
    let isPlanar: Bool
    let sampleRate: Double
}

/// Converts captured Float32 input to the 48 kHz planar format used by renderers.
/// It fans each source into a distinct SPSC queue for every configured endpoint.
final class AudioSourceFanout {
    private let queuesBySource: [String: [RealtimeAudioRingBuffer]]
    private let inputChannelCounts: [String: Int]
    private let buffersBySource: [String: SourceBuffer]
    let metersBySource: [String: RealtimePeakMeter]
    let channelMetersBySource: [String: [RealtimePeakMeter]]
    var channelReadingsBySource: [String: [Double?]] {
        channelMetersBySource.mapValues { $0.map { $0.reading() } }
    }

    private let capacity = 8192

    init(
        queuesBySource: [String: [RealtimeAudioRingBuffer]],
        inputChannelCounts: [String: Int],
        existing: AudioSourceFanout? = nil
    ) {
        self.queuesBySource = queuesBySource
        self.inputChannelCounts = inputChannelCounts
        buffersBySource = Dictionary(uniqueKeysWithValues: queuesBySource.map { key, _ in
            let count = inputChannelCounts[key] ?? 2
            if let buffer = existing?.buffersBySource[key], buffer.channelCount == count {
                return (key, buffer)
            }
            return (key, SourceBuffer(capacity: 8192, channelCount: count))
        })
        metersBySource = Dictionary(uniqueKeysWithValues: queuesBySource.keys.map {
            ($0, existing?.metersBySource[$0] ?? RealtimePeakMeter())
        })
        channelMetersBySource = Dictionary(uniqueKeysWithValues: queuesBySource.keys.compactMap { key in
            let count: Int
            if let inputCount = inputChannelCounts[key] {
                count = inputCount
            } else if key.hasPrefix("application:") {
                count = 2
            } else {
                return nil
            }
            guard (1 ... 64).contains(count) else { return nil }
            let priorMeters = existing?.channelMetersBySource[key]
            let meters: [RealtimePeakMeter] = if let priorMeters, priorMeters.count == count {
                priorMeters
            } else {
                (0 ..< count).map { _ in RealtimePeakMeter() }
            }
            return (key, meters)
        })
    }

    func hasSameTopology(
        queuesBySource: [String: [RealtimeAudioRingBuffer]],
        inputChannelCounts: [String: Int]
    ) -> Bool {
        guard self.queuesBySource.count == queuesBySource.count else { return false }
        for (source, queues) in queuesBySource {
            guard let currentQueues = self.queuesBySource[source], currentQueues.count == queues.count,
                  self.inputChannelCounts[source] == inputChannelCounts[source]
            else { return false }
            for desired in queues {
                guard currentQueues.contains(where: { $0 === desired }) else { return false }
            }
        }
        return true
    }

    func consume(id: String, buffers: UnsafePointer<AudioBufferList>, frames: UInt32, format: AudioStreamBasicDescription) {
        metersBySource[id]?.record(buffers: buffers, frameCount: frames, format: format)
        if let channelMeters = channelMetersBySource[id] {
            RealtimePeakMeter.recordChannelPeaks(channelMeters, buffers: buffers, frameCount: frames, format: format)
        }
        guard let queues = queuesBySource[id], let storage = buffersBySource[id], !queues.isEmpty,
              let converted = storage.convert(buffers: buffers, frames: frames, format: format)
        else { return }
        let sourcePlanes = UnsafeBufferPointer(start: storage.sourcePlanePointers, count: storage.channelCount)
        for queue in queues {
            if converted.droppedFrames > 0 {
                queue.recordDroppedFrames(converted.droppedFrames)
            }
            _ = queue.write(channels: sourcePlanes, frameCount: converted.frameCount)
        }
    }
}
