// Packages/RecordingKit/Sources/RecordingKit/ScreenRecorder.swift

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import Observation
@preconcurrency import ScreenCaptureKit

// MARK: - Debug Log

func capsoLog(_ msg: String) {
    #if DEBUG
    NSLog("[Capso] %@", msg)
    #endif
}

// MARK: - Errors

public enum RecordingError: Error, LocalizedError {
    case noMatchingDisplay, writerSetupFailed(String), writerFailedToStart
    case writerFailed(Error?), notRecording, alreadyRecording, cancelled, noFramesCaptured

    public var errorDescription: String? {
        switch self {
        case .noMatchingDisplay: return "No matching display."
        case .writerSetupFailed(let r): return "Writer setup: \(r)"
        case .writerFailedToStart: return "Writer failed to start."
        case .writerFailed(let e): return "Writer: \(e?.localizedDescription ?? "?")"
        case .notRecording: return "Not recording."
        case .alreadyRecording: return "Already recording."
        case .cancelled: return "Cancelled."
        case .noFramesCaptured: return "No frames captured."
        }
    }
}

// MARK: - ScreenRecorder

@MainActor
@Observable
public final class ScreenRecorder {
    private static let excludedWindowLookupDelay: Duration = .milliseconds(30)
    private static let excludedWindowLookupAttempts = 8

    public private(set) var state: RecordingState = .idle
    public private(set) var elapsedTime: TimeInterval = 0
    public private(set) var error: Error?

    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var recordingQueue: DispatchQueue?
    private let writer = RecordingWriter()
    private var elapsedTimer: Timer?
    private var recordingStartTime: Date?
    private var outputFileURL: URL?
    private var recordingConfig: RecordingConfig?

    public init() {}

    public func startRecording(
        config: RecordingConfig,
        excludeWindowIDs: [CGWindowID] = []
    ) async throws {
        capsoLog("startRecording rect=\(config.captureRect) display=\(config.displayID)")
        guard state == .idle else { throw RecordingError.alreadyRecording }

        state = .preparing
        error = nil
        elapsedTime = 0
        recordingConfig = config

        do {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("capso_recording_\(UUID().uuidString).mov")
            outputFileURL = fileURL

            // Calculate dimensions (same as stream config)
            let dims = videoDims(for: config.captureRect)

            // Set up SCStream first (creates the dispatch queue)
            try await setupStream(config: config, dims: dims, excludeWindowIDs: excludeWindowIDs)

            // Create writer ON the recording dispatch queue (thread affinity —
            // AVAssetWriter's AAC encoder must be created and used on same thread)
            let wr = writer
            let cfg = config
            let w = dims.w; let h = dims.h; let url = fileURL
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.recordingQueue!.async {
                    do {
                        try wr.setup(outputURL: url, config: cfg, videoWidth: w, videoHeight: h)
                        cont.resume()
                    } catch { cont.resume(throwing: error) }
                }
            }
            try await stream?.startCapture()
            writer.activate()

            state = .recording
            recordingStartTime = Date()
            startElapsedTimer()
            capsoLog("Recording started")
        } catch {
            state = .idle; self.error = error; cleanup(); throw error
        }
    }

    public func pause() {
        guard state == .recording else { return }
        state = .paused; writer.deactivate(); stopElapsedTimer()
    }

    public func resume() {
        guard state == .paused else { return }
        state = .recording; writer.activate(); startElapsedTimer()
    }

    public func stopRecording() async throws -> RecordingResult {
        capsoLog("stopRecording state=\(state.rawValue)")
        guard state == .recording || state == .paused else { throw RecordingError.notRecording }

        state = .stopping
        stopElapsedTimer()
        writer.deactivate()
        if let s = stream { try await s.stopCapture() }

        guard writer.hasWrittenFrames else {
            capsoLog("No frames written"); cleanup(); state = .idle
            throw RecordingError.noFramesCaptured
        }

        await writer.finalize()

        if let e = writer.error {
            capsoLog("Writer error: \(e)"); cleanup(); state = .idle
            throw RecordingError.writerFailed(e)
        }

        guard let url = outputFileURL, let cfg = recordingConfig else {
            cleanup(); state = .idle; throw RecordingError.notRecording
        }

        let result = RecordingResult(fileURL: url, duration: elapsedTime,
                                     format: cfg.format, size: cfg.captureRect.size)
        capsoLog("Done: \(url.lastPathComponent) \(elapsedTime)s")
        cleanup(); state = .idle
        return result
    }

    // MARK: - SCStream

    private struct VideoDims { let w: Int; let h: Int }

    private func videoDims(for rect: CGRect) -> VideoDims {
        VideoDims(w: ensureEven(Int(ceil(rect.width)) * 2),
                  h: ensureEven(Int(ceil(rect.height)) * 2))
    }

    private func setupStream(config: RecordingConfig, dims: VideoDims, excludeWindowIDs: [CGWindowID]) async throws {
        let excludeSet = Set(excludeWindowIDs)
        let content = try await shareableContent(excludingWindowIDs: excludeSet)
        guard let display = content.displays.first(where: { $0.displayID == config.displayID }) else {
            throw RecordingError.noMatchingDisplay
        }

        let excludedWindows = excludeSet.isEmpty
            ? []
            : content.windows.filter { excludeSet.contains($0.windowID) }
        if !excludeSet.isEmpty, excludedWindows.count != excludeSet.count {
            let missingIDs = excludeSet.subtracting(excludedWindows.map(\.windowID))
            capsoLog("Proceeding without excluding windows: \(missingIDs)")
        }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let sc = SCStreamConfiguration()

        sc.width = dims.w
        sc.height = dims.h
        sc.sourceRect = config.captureRect
        sc.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        sc.showsCursor = config.showCursor
        sc.queueDepth = 5
        sc.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange  // NV12

        if config.captureSystemAudio {
            sc.capturesAudio = true
            sc.sampleRate = 48000
            sc.excludesCurrentProcessAudio = true
            // Don't set channelCount — use default (stereo).
        }
        if config.captureMicrophone {
            sc.captureMicrophone = true
        }

        capsoLog("Stream: \(dims.w)x\(dims.h) NV12")

        let output = StreamOutput()
        let captureStream = SCStream(filter: filter, configuration: sc, delegate: output)

        let wr = writer
        output.onVideo = { buf in wr.appendVideo(buf) }
        output.onSystemAudio = { buf in wr.appendSystemAudio(buf) }
        output.onMicAudio = { buf in wr.appendMicAudio(buf) }

        let queue = DispatchQueue(label: "com.capso.recording", qos: .userInteractive)
        self.recordingQueue = queue
        try captureStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
        if config.captureSystemAudio {
            try captureStream.addStreamOutput(output, type: .audio, sampleHandlerQueue: queue)
        }
        if config.captureMicrophone {
            try captureStream.addStreamOutput(output, type: .microphone, sampleHandlerQueue: queue)
        }

        self.stream = captureStream; self.streamOutput = output
    }

    private func shareableContent(excludingWindowIDs excludeSet: Set<CGWindowID>) async throws -> SCShareableContent {
        var content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !excludeSet.isEmpty else { return content }

        for attempt in 1...Self.excludedWindowLookupAttempts {
            let matchedIDs = Set(content.windows.map(\.windowID)).intersection(excludeSet)
            if matchedIDs == excludeSet {
                if attempt > 1 {
                    capsoLog("Excluded windows became visible after \(attempt) attempts")
                }
                return content
            }

            if attempt == Self.excludedWindowLookupAttempts {
                let missingIDs = excludeSet.subtracting(matchedIDs)
                capsoLog("Timed out waiting for excluded windows: \(missingIDs)")
                return content
            }

            try? await Task.sleep(for: Self.excludedWindowLookupDelay)
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }

        return content
    }

    private func startElapsedTimer() {
        recordingStartTime = Date()
        let base = elapsedTime
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let s = self.recordingStartTime else { return }
                self.elapsedTime = base + Date().timeIntervalSince(s)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate(); elapsedTimer = nil; recordingStartTime = nil
    }

    private func cleanup() {
        stream = nil; streamOutput = nil; recordingConfig = nil; recordingQueue = nil
        writer.reset(); stopElapsedTimer()
    }
}

private func ensureEven(_ v: Int) -> Int { v % 2 == 0 ? v : v + 1 }

// MARK: - RecordingWriter

/// Writer architecture:
/// - All inputs added before startWriting
/// - .mov container
/// - AAC 48kHz 256kbps with quality + strategy keys
/// - startSession deferred to first frame PTS
private final class RecordingWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var sysAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var active = false
    private var _written = false

    var hasWrittenFrames: Bool { lock.lock(); defer { lock.unlock() }; return _written }
    var error: Error? {
        lock.lock(); defer { lock.unlock() }
        return assetWriter?.status == .failed ? assetWriter?.error : nil
    }

    /// Set up the writer with ALL inputs, then startWriting.
    func setup(outputURL: URL, config: RecordingConfig, videoWidth: Int, videoHeight: Int) throws {
        lock.lock(); defer { lock.unlock() }

        // .mov container (NOT .mp4)
        let w: AVAssetWriter
        do { w = try AVAssetWriter(outputURL: outputURL, fileType: .mov) }
        catch { throw RecordingError.writerSetupFailed(error.localizedDescription) }

        // Video input: H.264, no B-frames
        let pixels = Float(videoWidth * videoHeight)
        let ref = Float(1920 * 1080)
        let fpsR = Float(min(config.fps, 60)) / 30.0
        let bitrate = 5_000_000 + pixels / ref * 2_000_000 + fpsR * 5_000_000

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoMaxKeyFrameIntervalKey: config.fps * 2,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any],
        ]

        let vi = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vi.expectsMediaDataInRealTime = true
        guard w.canAdd(vi) else { throw RecordingError.writerSetupFailed("Can't add video input") }
        w.add(vi)
        videoInput = vi

        // Two separate audio inputs: one for system audio, one for the microphone.
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 256_000,
            AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant,
        ]

        if config.captureSystemAudio {
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            ai.expectsMediaDataInRealTime = true
            if w.canAdd(ai) { w.add(ai); sysAudioInput = ai }
        } else { sysAudioInput = nil }

        if config.captureMicrophone {
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            ai.expectsMediaDataInRealTime = true
            if w.canAdd(ai) { w.add(ai); micAudioInput = ai }
        } else { micAudioInput = nil }

        // Start writing — all inputs already added.
        assetWriter = w
        guard w.startWriting() else {
            capsoLog("startWriting FAILED: \(String(describing: w.error))")
            throw RecordingError.writerFailedToStart
        }
        capsoLog("Writer started: \(videoWidth)x\(videoHeight), sysAudio=\(sysAudioInput != nil), mic=\(micAudioInput != nil)")

        sessionStarted = false; active = false; _written = false
    }

    func activate() { lock.lock(); active = true; lock.unlock() }
    func deactivate() { lock.lock(); active = false; lock.unlock() }

    func appendVideo(_ buf: CMSampleBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard active, let w = assetWriter, w.status == .writing else { return }

        // Start session on first frame PTS
        if !sessionStarted {
            let pts = CMSampleBufferGetPresentationTimeStamp(buf)
            w.startSession(atSourceTime: pts)
            sessionStarted = true

            if let pb = CMSampleBufferGetImageBuffer(buf) {
                capsoLog("Session started: \(CVPixelBufferGetWidth(pb))x\(CVPixelBufferGetHeight(pb)) at \(pts.seconds)s")
            }
        }

        guard let vi = videoInput, vi.isReadyForMoreMediaData else { return }
        if !vi.append(buf) {
            capsoLog("Video append FAILED: \(String(describing: w.error))")
        } else {
            _written = true
        }
    }

    private var sysAudioLogCount = 0
    private var micAudioLogCount = 0

    func appendSystemAudio(_ buf: CMSampleBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard active, sessionStarted else { return }
        guard let w = assetWriter, w.status == .writing else { return }
        guard let ai = sysAudioInput, ai.isReadyForMoreMediaData else { return }
        guard let converted = createCleanAudioBuffer(buf, label: "sys") else { return }
        if !ai.append(converted) {
            if sysAudioLogCount < 3 { capsoLog("SysAudio append FAILED: \(String(describing: w.error))"); sysAudioLogCount += 1 }
        } else if sysAudioLogCount == 0 { capsoLog("SysAudio append OK"); sysAudioLogCount += 1 }
    }

    func appendMicAudio(_ buf: CMSampleBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard active, sessionStarted else { return }
        guard let w = assetWriter, w.status == .writing else { return }
        guard let ai = micAudioInput, ai.isReadyForMoreMediaData else { return }
        guard let converted = createCleanAudioBuffer(buf, label: "mic") else { return }
        if !ai.append(converted) {
            if micAudioLogCount < 3 { capsoLog("MicAudio append FAILED: \(String(describing: w.error))"); micAudioLogCount += 1 }
        } else if micAudioLogCount == 0 { capsoLog("MicAudio append OK"); micAudioLogCount += 1 }
    }

    /// Creates a clean CMSampleBuffer from SCStream audio data by copying
    /// the plane data sequentially into a new CMBlockBuffer, preserving the
    /// non-interleaved layout. We deep-copy the sample data so AVAssetWriter
    /// doesn't hold on to buffers owned by the SCStream lifecycle.
    private var audioFormatLogged = false
    private func createCleanAudioBuffer(_ buf: CMSampleBuffer, label: String) -> CMSampleBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(buf),
              let srcASBD = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return nil }

        let numSamples = CMSampleBufferGetNumSamples(buf)
        let channels = Int(srcASBD.pointee.mChannelsPerFrame)
        let bytesPerSample = Int(srcASBD.pointee.mBitsPerChannel / 8)

        if !audioFormatLogged || (label == "mic" && micAudioLogCount == 0) {
            let a = srcASBD.pointee
            capsoLog("\(label) audio: rate=\(a.mSampleRate) ch=\(channels) flags=\(a.mFormatFlags) samples=\(numSamples) bps=\(bytesPerSample)")
            audioFormatLogged = true
        }

        // Get the raw audio data via CMSampleBufferGetDataBuffer (flat data, no ABL needed)
        guard let dataBuffer = CMSampleBufferGetDataBuffer(buf) else { return nil }

        var dataLength = 0
        var dataPointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &dataLength,
                                          dataPointerOut: &dataPointer) == noErr,
              let srcPtr = dataPointer else { return nil }

        if !audioFormatLogged {
            capsoLog("\(label) data: \(dataLength) bytes, expected=\(numSamples * bytesPerSample * channels)")
        }

        // Create a NEW block buffer with a copy of the data.
        var newBlockBuf: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: dataLength,
            blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: dataLength,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &newBlockBuf
        ) == noErr, let nb = newBlockBuf else { return nil }

        guard CMBlockBufferReplaceDataBytes(
            with: srcPtr, blockBuffer: nb,
            offsetIntoDestination: 0, dataLength: dataLength
        ) == noErr else { return nil }

        // Use the SAME format description from the original buffer
        let pts = CMSampleBufferGetPresentationTimeStamp(buf)
        let dur = CMSampleBufferGetDuration(buf)
        var timing = CMSampleTimingInfo(
            duration: dur.isValid ? dur : CMTime(value: 1, timescale: CMTimeScale(srcASBD.pointee.mSampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        var newSampleBuf: CMSampleBuffer?
        // sampleSize = 0 means "figure it out from the format description"
        guard CMSampleBufferCreate(
            allocator: nil, dataBuffer: nb, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil,
            formatDescription: formatDesc,  // Reuse original format description
            sampleCount: numSamples,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil,
            sampleBufferOut: &newSampleBuf
        ) == noErr else { return nil }

        return newSampleBuf
    }

    private struct Refs { let w: AVAssetWriter?; let v: AVAssetWriterInput?; let sa: AVAssetWriterInput?; let ma: AVAssetWriterInput? }
    private func refs() -> Refs {
        lock.lock(); defer { lock.unlock() }
        return Refs(w: assetWriter, v: videoInput, sa: sysAudioInput, ma: micAudioInput)
    }

    func finalize() async {
        let r = refs()
        r.v?.markAsFinished(); r.sa?.markAsFinished(); r.ma?.markAsFinished()
        if let w = r.w, w.status == .writing { await w.finishWriting() }
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        assetWriter = nil; videoInput = nil; sysAudioInput = nil; micAudioInput = nil
        sessionStarted = false; active = false; _written = false
        sysAudioLogCount = 0; micAudioLogCount = 0; audioFormatLogged = false
    }
}

// MARK: - StreamOutput

private final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onVideo: ((CMSampleBuffer) -> Void)?
    var onSystemAudio: ((CMSampleBuffer) -> Void)?
    var onMicAudio: ((CMSampleBuffer) -> Void)?
    private var sysAudioCount = 0
    private var micAudioCount = 0

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        capsoLog("SCStream error: \(error)")
    }

    func stream(_ s: SCStream, didOutputSampleBuffer buf: CMSampleBuffer, of type: SCStreamOutputType) {
        guard buf.isValid else { return }
        switch type {
        case .screen:
            guard let att = CMSampleBufferGetSampleAttachmentsArray(buf, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let sv = att.first?[.status] as? Int,
                  let st = SCFrameStatus(rawValue: sv), st == .complete else { return }
            onVideo?(buf)
        case .audio:
            sysAudioCount += 1
            if sysAudioCount <= 3 { capsoLog("System audio frame #\(sysAudioCount)") }
            onSystemAudio?(buf)
        case .microphone:
            micAudioCount += 1
            if micAudioCount <= 3 { capsoLog("Mic audio frame #\(micAudioCount)") }
            onMicAudio?(buf)
        @unknown default: break
        }
    }
}
