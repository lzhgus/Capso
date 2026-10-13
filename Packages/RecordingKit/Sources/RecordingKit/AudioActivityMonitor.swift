import Accelerate
import CoreMedia
import Foundation

public enum AudioIssue: Sendable, Equatable {
    case microphoneSilent
    case microphoneStopped
    case systemAudioStopped
}

/// Fed from the recording queue; reports each audio problem at most once per recording.
final class AudioActivityMonitor: @unchecked Sendable {
    static let silenceThresholdDecibels: Float = -80
    static let silenceWindow: TimeInterval = 8
    static let stallTimeout: TimeInterval = 5

    private let lock = NSLock()
    private var startTime: Date?
    private var lastMicrophoneBuffer: Date?
    private var lastSystemAudioBuffer: Date?
    private var microphoneHeard = false
    private var reported: Set<AudioIssue> = []

    func start(expectMicrophone: Bool, expectSystemAudio: Bool, at time: Date) {
        lock.withLock {
            startTime = time
            lastMicrophoneBuffer = expectMicrophone ? time : nil
            lastSystemAudioBuffer = expectSystemAudio ? time : nil
            microphoneHeard = false
            reported = []
        }
    }

    func microphoneBuffer(peakDecibels: Float?, at time: Date) {
        lock.withLock {
            lastMicrophoneBuffer = time
            if (peakDecibels ?? 0) > Self.silenceThresholdDecibels { microphoneHeard = true }
        }
    }

    func systemAudioBuffer(at time: Date) {
        lock.withLock { lastSystemAudioBuffer = time }
    }

    func newIssues(at now: Date) -> [AudioIssue] {
        lock.withLock {
            guard let startTime else { return [] }
            var issues: [AudioIssue] = []
            if let last = lastMicrophoneBuffer {
                if now.timeIntervalSince(last) > Self.stallTimeout {
                    issues.append(.microphoneStopped)
                } else if !microphoneHeard, now.timeIntervalSince(startTime) >= Self.silenceWindow {
                    issues.append(.microphoneSilent)
                }
            }
            if let last = lastSystemAudioBuffer, now.timeIntervalSince(last) > Self.stallTimeout {
                issues.append(.systemAudioStopped)
            }
            let fresh = issues.filter { !reported.contains($0) }
            reported.formUnion(fresh)
            return fresh
        }
    }
}

enum AudioLevel {
    /// Loudest absolute sample in dBFS, or `nil` when the buffer isn't 32-bit float PCM.
    static func peakDecibels(of buffer: CMSampleBuffer) -> Float? {
        guard let format = buffer.formatDescription?.audioStreamBasicDescription,
              format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32 else { return nil }

        var listSize = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer, bufferListSizeNeededOut: &listSize, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil
        ) == noErr else { return nil }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: listSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        let list = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: listSize,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &block
        ) == noErr else { return nil }

        let peak: Float = withExtendedLifetime(block) {
            var peak: Float = 0
            for channel in UnsafeMutableAudioBufferListPointer(list) {
                guard let data = channel.mData else { continue }
                var channelPeak: Float = 0
                vDSP_maxmgv(data.assumingMemoryBound(to: Float.self), 1, &channelPeak,
                            vDSP_Length(channel.mDataByteSize) / vDSP_Length(MemoryLayout<Float>.size))
                peak = max(peak, channelPeak)
            }
            return peak
        }
        return 20 * log10(max(peak, 1e-8))
    }
}
