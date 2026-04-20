// Packages/ExportKit/Sources/ExportKit/MP4Exporter.swift
import Foundation
import AVFoundation
import SharedKit

enum MP4Exporter {
    static func export(
        source: URL,
        quality: ExportQuality,
        destination: URL,
        timeRange: CMTimeRange? = nil,
        progress: (@Sendable (Double) -> Void)?,
        status: (@Sendable (ExportStatus) -> Void)?
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        status?(ExportStatus(stage: .preparing, fractionCompleted: 0))

        // Recordings that captured system audio + microphone end up with two
        // AAC tracks in the container. Passthrough export preserves both tracks,
        // but most consumer tools (Slack, Linear, macOS Services) only read the
        // first one — so the shared file sounds silent even though both tracks
        // are present. Merge them into a single mixed track. (issue #55)
        if audioTracks.count > 1 {
            status?(ExportStatus(stage: .encoding, fractionCompleted: 0.05))
            return try await exportWithMergedAudio(
                asset: asset,
                audioTracks: audioTracks,
                destination: destination,
                progress: progress,
                status: status
            )
        }

        let presetName = switch quality {
        case .maximum: AVAssetExportPresetPassthrough
        case .social: AVAssetExportPreset1920x1080
        case .web: AVAssetExportPreset1280x720
        }

        // For social/web, check if source is already <= target resolution.
        // If so, use passthrough to avoid unnecessary re-encode.
        let effectivePreset: String
        if quality != .maximum {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let size = try await track.load(.naturalSize)
                let targetWidth: CGFloat = quality == .social ? 1920 : 1280
                if size.width <= targetWidth {
                    effectivePreset = AVAssetExportPresetPassthrough
                } else {
                    effectivePreset = presetName
                }
            } else {
                effectivePreset = presetName
            }
        } else {
            effectivePreset = presetName
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: effectivePreset) else {
            throw ExportError.exportSessionFailed("Could not create export session with preset \(effectivePreset)")
        }

        session.shouldOptimizeForNetworkUse = true
        if let timeRange {
            session.timeRange = timeRange
            status?(ExportStatus(stage: .trimming, fractionCompleted: 0.1))
        }
        status?(ExportStatus(stage: .encoding, fractionCompleted: 0.12))

        // AVAssetExportSession cannot overwrite existing files
        try? FileManager.default.removeItem(at: destination)

        do {
            try await session.export(to: destination, as: .mp4)
        } catch is CancellationError {
            throw ExportError.cancelled
        } catch {
            throw ExportError.exportSessionFailed(error.localizedDescription)
        }

        status?(ExportStatus(stage: .finalizing, fractionCompleted: 1.0))
        progress?(1.0)
        return destination
    }

    /// Merge multiple source audio tracks into a single AAC track using
    /// `AVAssetReaderAudioMixOutput` (which sums/mixes all supplied tracks
    /// to PCM) and re-encode through `AVAssetWriter`. Video is passed
    /// through uncompressed.
    private static func exportWithMergedAudio(
        asset: AVURLAsset,
        audioTracks: [AVAssetTrack],
        destination: URL,
        progress: (@Sendable (Double) -> Void)?,
        status: (@Sendable (ExportStatus) -> Void)?
    ) async throws -> URL {
        try? FileManager.default.removeItem(at: destination)

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        } catch {
            throw ExportError.exportSessionFailed(error.localizedDescription)
        }
        writer.shouldOptimizeForNetworkUse = true
        status?(ExportStatus(stage: .encoding, fractionCompleted: 0.1))

        // Video track: read compressed samples, write them through unchanged.
        var videoPair: (output: AVAssetReaderOutput, input: AVAssetWriterInput)?
        if let sourceVideo = try await asset.loadTracks(withMediaType: .video).first {
            let output = AVAssetReaderTrackOutput(track: sourceVideo, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw ExportError.exportSessionFailed("Could not add video reader output")
            }
            reader.add(output)

            let formatDescriptions = try await sourceVideo.load(.formatDescriptions)
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: nil,
                sourceFormatHint: formatDescriptions.first
            )
            input.expectsMediaDataInRealTime = false
            input.transform = try await sourceVideo.load(.preferredTransform)
            guard writer.canAdd(input) else {
                throw ExportError.exportSessionFailed("Could not add video writer input")
            }
            writer.add(input)
            videoPair = (output, input)
        }

        // Audio: mix all source tracks into a single PCM stream, encode as AAC.
        let pcmSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: pcmSettings)
        audioOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(audioOutput) else {
            throw ExportError.exportSessionFailed("Could not add audio mix output")
        }
        reader.add(audioOutput)

        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256_000,
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(audioInput) else {
            throw ExportError.exportSessionFailed("Could not add audio writer input")
        }
        writer.add(audioInput)

        guard reader.startReading() else {
            throw ExportError.exportSessionFailed(reader.error?.localizedDescription ?? "Reader failed to start")
        }
        guard writer.startWriting() else {
            throw ExportError.exportSessionFailed(writer.error?.localizedDescription ?? "Writer failed to start")
        }
        writer.startSession(atSourceTime: .zero)

        // Round-robin drain on a dedicated thread so the reader's internal
        // buffers for both tracks stay balanced. AVFoundation types aren't
        // Sendable, so wrap the work in a non-Sendable closure via a
        // continuation rather than a Swift Task.
        try await runDrain(videoPair: videoPair, audioOutput: audioOutput, audioInput: audioInput)
        progress?(0.9)
        status?(ExportStatus(stage: .finalizing, fractionCompleted: 0.9))

        if reader.status == .failed {
            throw ExportError.exportSessionFailed(reader.error?.localizedDescription ?? "Reader failed")
        }

        await writer.finishWriting()
        if writer.status != .completed {
            throw ExportError.exportSessionFailed(writer.error?.localizedDescription ?? "Writer did not complete")
        }

        status?(ExportStatus(stage: .finalizing, fractionCompleted: 1.0))
        progress?(1.0)
        return destination
    }

    /// Round-robin pull from each reader output into the matching writer input
    /// until both sources are drained. Runs on a private dispatch queue so the
    /// caller's actor isn't blocked.
    private static func runDrain(
        videoPair: (output: AVAssetReaderOutput, input: AVAssetWriterInput)?,
        audioOutput: AVAssetReaderOutput,
        audioInput: AVAssetWriterInput
    ) async throws {
        let queue = DispatchQueue(label: "com.capso.mp4exporter.drain")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                var videoDone = videoPair == nil
                var audioDone = false
                while !videoDone || !audioDone {
                    var madeProgress = false
                    if !videoDone, let pair = videoPair, pair.input.isReadyForMoreMediaData {
                        if let buffer = pair.output.copyNextSampleBuffer() {
                            if !pair.input.append(buffer) {
                                pair.input.markAsFinished()
                                audioInput.markAsFinished()
                                cont.resume(throwing: ExportError.exportSessionFailed(
                                    "Failed to append video sample"))
                                return
                            }
                            madeProgress = true
                        } else {
                            pair.input.markAsFinished()
                            videoDone = true
                            madeProgress = true
                        }
                    }
                    if !audioDone, audioInput.isReadyForMoreMediaData {
                        if let buffer = audioOutput.copyNextSampleBuffer() {
                            if !audioInput.append(buffer) {
                                audioInput.markAsFinished()
                                videoPair?.input.markAsFinished()
                                cont.resume(throwing: ExportError.exportSessionFailed(
                                    "Failed to append audio sample"))
                                return
                            }
                            madeProgress = true
                        } else {
                            audioInput.markAsFinished()
                            audioDone = true
                            madeProgress = true
                        }
                    }
                    if !madeProgress {
                        Thread.sleep(forTimeInterval: 0.001)
                    }
                }
                cont.resume()
            }
        }
    }
}
