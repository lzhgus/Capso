// Packages/CameraKit/Sources/CameraKit/CameraManager.swift
import Foundation
import AVFoundation
import CoreImage
import AppKit
import Observation

public enum CameraClipShape: String, CaseIterable, Sendable {
    case circle
    case roundedRect
}

public enum CameraPosition: String, CaseIterable, Sendable {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight
}

public enum CameraError: Error, LocalizedError {
    case permissionDenied

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera access is required. Grant permission in System Settings → Privacy & Security → Camera."
        }
    }
}

public struct CameraDevice: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isBuiltIn: Bool

    public init(from device: AVCaptureDevice) {
        self.id = device.uniqueID
        self.name = device.localizedName
        self.isBuiltIn = device.deviceType == .builtInWideAngleCamera
    }
}

@MainActor
@Observable
public final class CameraManager {
    public private(set) var isRunning = false
    public private(set) var availableDevices: [CameraDevice] = []
    public private(set) var currentFrame: CGImage?

    public var selectedDeviceID: String?
    public var shape: CameraClipShape = .circle
    public var position: CameraPosition = .bottomRight

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var frameDelegate: CameraFrameDelegate?

    public init() {}

    public func refreshDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        availableDevices = discoverySession.devices.map { CameraDevice(from: $0) }
        if selectedDeviceID == nil {
            selectedDeviceID = availableDevices.first?.id
        }
    }

    /// Request camera permission (if not yet determined) and start the
    /// capture session. Shows the system prompt on first use. Throws
    /// ``CameraError/permissionDenied`` if the user declines or has
    /// previously denied access.
    public func requestAccessAndStart() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw CameraError.permissionDenied }
        default:
            throw CameraError.permissionDenied
        }
        try start()
    }

    public func start() throws {
        guard !isRunning else { return }
        guard let deviceID = selectedDeviceID,
              let device = AVCaptureDevice(uniqueID: deviceID) else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .medium

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let delegate = CameraFrameDelegate { [weak self] image in
            Task { @MainActor in
                self?.currentFrame = image
            }
        }
        output.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "com.capso.camera"))
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        captureSession = session
        videoOutput = output
        frameDelegate = delegate
        session.startRunning()
        isRunning = true
    }

    public func stop() {
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        frameDelegate = nil
        currentFrame = nil
        isRunning = false
    }
}

private final class CameraFrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let onFrame: (CGImage) -> Void
    private let context = CIContext(options: [.cacheIntermediates: false, .priorityRequestLow: false])

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        onFrame(cgImage)
    }
}
