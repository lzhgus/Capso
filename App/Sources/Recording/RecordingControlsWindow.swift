// App/Sources/Recording/RecordingControlsWindow.swift
import AppKit
import SwiftUI
import RecordingKit

@MainActor
final class RecordingControlsWindow: NSPanel {
    init(recordingFrame: CGRect, screen: NSScreen, recorder: ScreenRecorder, onStop: @escaping () -> Void, onRestart: @escaping () -> Void, onDelete: @escaping () -> Void) {
        let width: CGFloat = 250
        let height: CGFloat = 52

        let screenFrame = screen.visibleFrame
        var x = recordingFrame.midX - width / 2
        var y = recordingFrame.minY - height - 18

        // If there isn't enough room below, place above the selection instead.
        if y < screenFrame.minY + 8 {
            y = recordingFrame.maxY + 18
        }

        // Clamp horizontally and vertically to the visible screen.
        x = max(screenFrame.minX + 8, min(x, screenFrame.maxX - width - 8))
        y = max(screenFrame.minY + 8, min(y, screenFrame.maxY - height - 8))

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.isMovableByWindowBackground = true
        self.sharingType = .none

        let view = RecordingControlsView(recorder: recorder, onStop: onStop, onRestart: onRestart, onDelete: onDelete)
        self.contentView = NSHostingView(rootView: view)
    }

    func show() { makeKeyAndOrderFront(nil) }
}

private struct RecordingControlsView: View {
    let recorder: ScreenRecorder
    let onStop: () -> Void
    let onRestart: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.red.opacity(0.95))
                    .frame(width: 28, height: 28)
                    .background(.red.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Stop recording")

            Text(formatTime(recorder.elapsedTime))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.red.opacity(0.95))
                .frame(minWidth: 52, alignment: .leading)

            Divider().frame(height: 18)

            Button(action: {
                if recorder.state == .recording {
                    recorder.pause()
                } else if recorder.state == .paused {
                    recorder.resume()
                }
            }) {
                Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(recorder.state == .paused ? "Resume recording" : "Pause recording")

            Button(action: onRestart) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Restart recording")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Delete recording")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.78))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
