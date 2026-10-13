import Testing
import CoreMedia
import Foundation
@testable import RecordingKit

@Suite("Audio activity monitor")
struct AudioActivityMonitorTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    private func feed(_ monitor: AudioActivityMonitor, mic decibels: Float?, from start: TimeInterval, to end: TimeInterval) {
        for t in stride(from: start, to: end, by: 0.02) {
            monitor.microphoneBuffer(peakDecibels: decibels, at: t0 + t)
        }
    }

    @Test("A speaking microphone raises nothing")
    func audibleMicrophone() {
        let monitor = AudioActivityMonitor()
        monitor.start(expectMicrophone: true, expectSystemAudio: false, at: t0)
        feed(monitor, mic: -90, from: 0, to: 3)
        feed(monitor, mic: -30, from: 3, to: 20)
        #expect(monitor.newIssues(at: t0 + 20).isEmpty)
    }

    @Test("A silent microphone is reported once after the silence window")
    func silentMicrophone() {
        let monitor = AudioActivityMonitor()
        monitor.start(expectMicrophone: true, expectSystemAudio: false, at: t0)
        feed(monitor, mic: -160, from: 0, to: 20)

        #expect(monitor.newIssues(at: t0 + AudioActivityMonitor.silenceWindow - 0.1).isEmpty)
        #expect(monitor.newIssues(at: t0 + AudioActivityMonitor.silenceWindow) == [.microphoneSilent])
        #expect(monitor.newIssues(at: t0 + 20).isEmpty)
    }

    @Test("Buffers in an unknown format are not treated as silence")
    func unknownFormat() {
        let monitor = AudioActivityMonitor()
        monitor.start(expectMicrophone: true, expectSystemAudio: false, at: t0)
        feed(monitor, mic: nil, from: 0, to: 20)
        #expect(monitor.newIssues(at: t0 + 20).isEmpty)
    }

    @Test("Sources that stop delivering are reported once each")
    func stalledSources() {
        let monitor = AudioActivityMonitor()
        monitor.start(expectMicrophone: true, expectSystemAudio: true, at: t0)
        feed(monitor, mic: -30, from: 0, to: 2)
        monitor.systemAudioBuffer(at: t0 + 4)

        #expect(monitor.newIssues(at: t0 + 6).isEmpty)
        #expect(monitor.newIssues(at: t0 + 7.1) == [.microphoneStopped])
        #expect(monitor.newIssues(at: t0 + 9.1) == [.systemAudioStopped])
        #expect(monitor.newIssues(at: t0 + 30).isEmpty)
    }

    @Test("A source that never delivers is reported")
    func neverDelivered() {
        let monitor = AudioActivityMonitor()
        monitor.start(expectMicrophone: false, expectSystemAudio: true, at: t0)
        #expect(monitor.newIssues(at: t0 + 5.1) == [.systemAudioStopped])
    }

    @Test("Peak level of float PCM buffers", arguments: [
        (Float(1.0), Float(0)),
        (Float(-0.5), Float(-6.0206)),
        (Float(0), Float(-160)),
    ])
    func peakLevel(sample: Float, expected: Float) throws {
        let buffer = try makeFloatBuffer(samples: [0, sample * 0.1, sample, 0])
        let peak = try #require(AudioLevel.peakDecibels(of: buffer))
        #expect(abs(peak - expected) < 0.01)
    }

    private func makeFloatBuffer(samples: [Float]) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                       formatDescriptionOut: &format)
        let bytes = samples.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes,
                                           blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                           dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag,
                                           blockBufferOut: &block)
        _ = samples.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!,
                                          offsetIntoDestination: 0, dataLength: bytes)
        }
        var buffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block!, formatDescription: try #require(format),
            sampleCount: samples.count, presentationTimeStamp: .zero,
            packetDescriptions: nil, sampleBufferOut: &buffer)
        return try #require(buffer)
    }
}
