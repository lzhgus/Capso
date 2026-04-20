// App/Sources/Recording/CountdownWindow.swift
import AppKit
import SwiftUI

@MainActor
final class CountdownWindow: NSPanel {
    private let value: ValueHolder
    private var countdownTask: Task<Void, Never>?

    /// Create a countdown window positioned above the given selection rectangle on the given screen.
    init(selectionRect: CGRect, screen: NSScreen) {
        self.value = ValueHolder(value: 3)

        let windowSize: CGFloat = 120
        let screenFrame = screen.frame

        // Position centered horizontally on the selection, just above it.
        // selectionRect uses CG (top-left origin) coordinates relative to the screen.
        let viewY = screenFrame.height - selectionRect.minY  // top of selection in NS coords
        let x = screenFrame.origin.x + selectionRect.midX - windowSize / 2
        let y = screenFrame.origin.y + viewY + 20  // 20pt above selection top

        // Clamp to screen bounds
        let clampedX = max(screenFrame.minX + 8, min(x, screenFrame.maxX - windowSize - 8))
        let clampedY = max(screenFrame.minY + 8, min(y, screenFrame.maxY - windowSize - 8))

        super.init(
            contentRect: NSRect(x: clampedX, y: clampedY, width: windowSize, height: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.sharingType = .none

        let view = CountdownContent(holder: value)
        self.contentView = NSHostingView(rootView: view)
    }

    /// Run the countdown 3 → 2 → 1 then call `completion`.
    /// Each tick takes ~1 second.
    func runCountdown(completion: @escaping @MainActor () -> Void) {
        countdownTask?.cancel()
        self.makeKeyAndOrderFront(nil)

        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                for number in [3, 2, 1] {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        self.value.value = number
                    }
                    try await Task.sleep(for: .seconds(1))
                }
            } catch {
                self.countdownTask = nil
                return
            }

            guard !Task.isCancelled else { return }
            self.countdownTask = nil
            self.close()
            completion()
        }
    }

    func cancel() {
        countdownTask?.cancel()
        countdownTask = nil
        close()
    }

    @MainActor
    final class ValueHolder: ObservableObject {
        @Published var value: Int
        init(value: Int) { self.value = value }
    }
}

private struct CountdownContent: View {
    @ObservedObject var holder: CountdownWindow.ValueHolder

    var body: some View {
        CountdownView(value: holder.value)
    }
}
