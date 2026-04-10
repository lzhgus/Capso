// App/Sources/Recording/RecordingToolbar.swift
import SwiftUI
import AVFoundation
import SharedKit

enum RecordingFormatChoice: String, CaseIterable {
    case video
    case gif
}

/// Recording toolbar with a two-section layout: controls row + action rows.
struct RecordingToolbarView: View {
    let width: Int
    let height: Int
    @Binding var cameraEnabled: Bool
    @Binding var selectedCameraID: String?
    @Binding var micEnabled: Bool
    @Binding var systemAudioEnabled: Bool
    let settings: SharedKit.AppSettings
    let onRecordVideo: () -> Void
    let onRecordGIF: () -> Void
    let onCancel: () -> Void
    let onCameraSettingsChanged: () -> Void

    @State private var selectedMicName: String = ""
    @State private var cameraMenuRevision = 0

    var body: some View {
        VStack(spacing: 0) {
            // Top section: dimensions + controls
            VStack(spacing: 8) {
                // Dimensions display
                HStack(spacing: 6) {
                    Text("\(width)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(minWidth: 40)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text("\u{00D7}")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))

                    Text("\(height)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(minWidth: 40)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // Controls row
                HStack(spacing: 4) {
                    // Mic menu
                    micMenuButton

                    toolbarToggle(
                        icon: systemAudioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        isOn: $systemAudioEnabled,
                        tooltip: "System Audio"
                    )

                    // Camera menu
                    cameraMenuButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .background(.white.opacity(0.15))

            // Action rows
            VStack(spacing: 0) {
                // Record GIF
                Button(action: onRecordGIF) {
                    HStack(spacing: 10) {
                        Text("GIF")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.purple.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text("Record GIF")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)

                        Spacer()

                        HStack(spacing: 2) {
                            shortcutKey("\u{2325}")  // Option
                            shortcutKey("\u{21A9}")  // Return
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()
                    .background(.white.opacity(0.1))

                // Record Video
                Button(action: onRecordVideo) {
                    HStack(spacing: 10) {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)

                        Text("Record Video")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)

                        Spacer()

                        shortcutKey("\u{21A9}")  // Return
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 220)
        .background(.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    }

    // MARK: - Mic Menu

    private var micMenuButton: some View {
        Menu {
            Button {
                micEnabled = false
                selectedMicName = ""
            } label: {
                if !micEnabled {
                    Label("Do Not Record Microphone", systemImage: "checkmark")
                } else {
                    Text("Do Not Record Microphone")
                }
            }

            Divider()

            ForEach(micDevices(), id: \.uniqueID) { device in
                Button {
                    micEnabled = true
                    selectedMicName = device.localizedName
                } label: {
                    if micEnabled && selectedMicName == device.localizedName {
                        Label(device.localizedName, systemImage: "checkmark")
                    } else {
                        Text(device.localizedName)
                    }
                }
            }
        } label: {
            Image(systemName: micEnabled ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: 14))
                .foregroundStyle(micEnabled ? .white : .white.opacity(0.4))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 36, height: 30)
        .background(micEnabled ? .white.opacity(0.15) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help("Microphone")
    }

    // MARK: - Camera Menu

    private var cameraMenuButton: some View {
        Menu {
            cameraDeviceMenuItems

            Divider()

            cameraShapeMenuItems

            Divider()

            cameraSizeMenuItems

            Divider()

            Button {
                settings.cameraMirror.toggle()
                cameraMenuRevision += 1
                onCameraSettingsChanged()
            } label: {
                if settings.cameraMirror {
                    Label("Mirror", systemImage: "checkmark")
                } else {
                    Text("Mirror")
                }
            }
        } label: {
            Image(systemName: cameraEnabled ? "camera.fill" : "camera")
                .font(.system(size: 14))
                .foregroundStyle(cameraEnabled ? .white : .white.opacity(0.4))
        }
        .id(cameraMenuRevision)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 36, height: 30)
        .background(cameraEnabled ? .white.opacity(0.15) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help("Camera")
    }

    @ViewBuilder
    private var cameraDeviceMenuItems: some View {
        Button {
            cameraEnabled = false
            selectedCameraID = nil
        } label: {
            if !cameraEnabled || selectedCameraID == nil {
                Label("None", systemImage: "checkmark")
            } else {
                Text("None")
            }
        }

        ForEach(cameraDevices(), id: \.uniqueID) { device in
            Button {
                cameraEnabled = true
                selectedCameraID = device.uniqueID
            } label: {
                if cameraEnabled && selectedCameraID == device.uniqueID {
                    Label(device.localizedName, systemImage: "checkmark")
                } else {
                    Text(device.localizedName)
                }
            }
        }
    }

    @ViewBuilder
    private var cameraShapeMenuItems: some View {
        Text("SHAPE")

        ForEach(CameraShape.allCases, id: \.rawValue) { shape in
            Button {
                settings.cameraShape = shape
                cameraMenuRevision += 1
                onCameraSettingsChanged()
            } label: {
                if settings.cameraShape == shape {
                    Label(shape.displayName, systemImage: "checkmark")
                } else {
                    Label(shape.displayName, systemImage: shape.iconName)
                }
            }
        }
    }

    @ViewBuilder
    private var cameraSizeMenuItems: some View {
        Text("SIZE")

        ForEach(SharedKit.CameraSize.allCases, id: \.rawValue) { size in
            Button {
                settings.cameraSize = size
                settings.cameraCustomSizePt = 0
                cameraMenuRevision += 1
                onCameraSettingsChanged()
            } label: {
                if settings.cameraCustomSizePt <= 0 && settings.cameraSize == size {
                    Label(size.displayName, systemImage: "checkmark")
                } else {
                    Text(size.displayName)
                }
            }
        }
    }

    // MARK: - Helpers

    private func toolbarIcon(systemName: String, active: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14))
            .foregroundStyle(active ? .white : .white.opacity(0.4))
            .frame(width: 36, height: 30)
            .background(active ? .white.opacity(0.15) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func toolbarToggle(icon: String, isOn: Binding<Bool>, tooltip: LocalizedStringKey) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isOn.wrappedValue ? .white : .white.opacity(0.4))
                .frame(width: 36, height: 30)
                .background(isOn.wrappedValue ? .white.opacity(0.15) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func shortcutKey(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func micDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private func cameraDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
    }
}

private extension CameraShape {
    var displayName: LocalizedStringKey {
        switch self {
        case .circle: "Circle"
        case .square: "Square"
        case .landscape: "Landscape (16:9)"
        case .portrait: "Portrait (9:16)"
        }
    }

    var iconName: String {
        switch self {
        case .circle: "circle"
        case .square: "square"
        case .landscape: "rectangle"
        case .portrait: "rectangle.portrait"
        }
    }
}

private extension SharedKit.CameraSize {
    var displayName: LocalizedStringKey {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}
