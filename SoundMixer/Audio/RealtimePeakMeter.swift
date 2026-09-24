import Foundation
import Synchronization

/// Publishes the latest callback peak without locks or allocation. A nil reading
/// means no callback has arrived within the caller's freshness window.
final class RealtimePeakMeter {
    private let peakBits = Atomic<UInt32>(0)
    private let updatedAt = Atomic<UInt64>(0)

    func record(left: UnsafeBufferPointer<Float>, right: UnsafeBufferPointer<Float>, frameCount: Int) {
        let count = min(frameCount, min(left.count, right.count))
        var peak: Float = 0
        if count > 0 {
            for index in 0 ..< count {
                let leftSample = left[index]
                let rightSample = right[index]
                if leftSample.isFinite { peak = max(peak, abs(leftSample)) }
                if rightSample.isFinite { peak = max(peak, abs(rightSample)) }
            }
        }
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
