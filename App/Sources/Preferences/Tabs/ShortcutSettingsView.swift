// App/Sources/Preferences/Tabs/ShortcutSettingsView.swift
import SwiftUI
import AppKit
import KeyboardShortcuts
import SharedKit
import Carbon

extension KeyboardShortcuts.Name {
    static let captureAllInOne = Self("captureAllInOne")
    static let captureArea = Self("captureArea", default: .init(.one, modifiers: [.option, .shift]))
    static let captureFullscreen = Self("captureFullscreen", default: .init(.two, modifiers: [.option, .shift]))
    static let captureWindow = Self("captureWindow", default: .init(.three, modifiers: [.option, .shift]))
    static let captureText = Self("captureText", default: .init(.four, modifiers: [.option, .shift]))
    /// Keep the existing storage key so current users retain their recording shortcut.
    static let recordScreen = Self("recordScreen", default: .init(.five, modifiers: [.option, .shift]))
    /// Opt-in to avoid adding another default global shortcut.
    static let recordFullscreen = Self("recordFullscreen")
    static let captureScrolling = Self("captureScrolling", default: .init(.six, modifiers: [.option, .shift]))
    static let captureAreaToClipboard = Self("captureAreaToClipboard", default: .init(.seven, modifiers: [.option, .shift]))
    static let captureAreaAndShare = Self("captureAreaAndShare", default: .init(.zero, modifiers: [.option, .shift]))
    static let captureAreaAndAnnotate = Self("captureAreaAndAnnotate", default: .init(.eight, modifiers: [.option, .shift]))
    static let captureAreaAndPin = Self("captureAreaAndPin")
    static let pinFromClipboard = Self("pinFromClipboard")
    static let editClipboardImage = Self("editClipboardImage")
    static let screenshotHistory = Self("screenshotHistory", default: .init(.nine, modifiers: [.option, .shift]))
    static let captureAndTranslate = Self("captureAndTranslate", default: .init(.t, modifiers: [.option, .shift]))
    static let translateSelectedText = Self("translateSelectedText", default: .init(.y, modifiers: [.option, .shift]))
    static let translateTypedText = Self("translateTypedText")
    static let selfTimerCapture = Self("selfTimerCapture")
    static let captureLastArea = Self("captureLastArea")
    static let togglePins = Self("togglePins")

    static let allCapso: [Self] = [
        .captureAllInOne, .captureArea, .captureFullscreen, .captureWindow, .captureText, .recordScreen,
        .recordFullscreen, .captureScrolling, .captureAreaToClipboard, .captureAreaAndShare,
        .captureAreaAndAnnotate, .captureAreaAndPin, .pinFromClipboard, .editClipboardImage, .screenshotHistory,
        .captureAndTranslate, .translateSelectedText, .translateTypedText, .selfTimerCapture, .captureLastArea, .togglePins,
    ]

    var effectiveShortcut: KeyboardShortcuts.Shortcut? {
        if let shortcut = KeyboardShortcuts.getShortcut(for: self) {
            return shortcut
        }
        let key = "KeyboardShortcuts_" + rawValue
        if let boolVal = UserDefaults.standard.object(forKey: key) as? Bool, !boolVal {
            return nil
        }
        return defaultShortcut
    }

    @MainActor
    func resetRevertingConflicts() {
        if let defaultShortcut = self.defaultShortcut {
            for otherName in KeyboardShortcuts.Name.allCapso where otherName != self {
                if let otherShortcut = otherName.effectiveShortcut, otherShortcut.isConflicting(with: defaultShortcut) {
                    if otherName.defaultShortcut != nil {
                        KeyboardShortcuts.reset(otherName)
                        if let resetShortcut = otherName.effectiveShortcut, resetShortcut.isConflicting(with: defaultShortcut) {
                            KeyboardShortcuts.setShortcut(nil, for: otherName)
                            let otherKey = "KeyboardShortcuts_" + otherName.rawValue
                            UserDefaults.standard.set(false, forKey: otherKey)
                        }
                    } else {
                        KeyboardShortcuts.setShortcut(nil, for: otherName)
                        let otherKey = "KeyboardShortcuts_" + otherName.rawValue
                        UserDefaults.standard.removeObject(forKey: otherKey)
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
                        object: nil,
                        userInfo: ["name": otherName]
                    )
                }
            }
        }
        KeyboardShortcuts.reset(self)
        let key = "KeyboardShortcuts_" + rawValue
        if UserDefaults.standard.object(forKey: key) as? Bool == false {
            UserDefaults.standard.removeObject(forKey: key)
        }
        NotificationCenter.default.post(
            name: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
            object: nil,
            userInfo: ["name": self]
        )
    }
}

extension KeyboardShortcuts.Shortcut {
    var normalizedKeyCode: Int {
        switch carbonKeyCode {
        case kVK_ANSI_Keypad0: return kVK_ANSI_0
        case kVK_ANSI_Keypad1: return kVK_ANSI_1
        case kVK_ANSI_Keypad2: return kVK_ANSI_2
        case kVK_ANSI_Keypad3: return kVK_ANSI_3
        case kVK_ANSI_Keypad4: return kVK_ANSI_4
        case kVK_ANSI_Keypad5: return kVK_ANSI_5
        case kVK_ANSI_Keypad6: return kVK_ANSI_6
        case kVK_ANSI_Keypad7: return kVK_ANSI_7
        case kVK_ANSI_Keypad8: return kVK_ANSI_8
        case kVK_ANSI_Keypad9: return kVK_ANSI_9
        case kVK_ANSI_KeypadEnter: return kVK_Return
        case kVK_ANSI_KeypadEquals: return kVK_ANSI_Equal
        case kVK_ANSI_KeypadMinus: return kVK_ANSI_Minus
        case kVK_ANSI_KeypadDivide: return kVK_ANSI_Slash
        case kVK_ANSI_KeypadDecimal: return kVK_ANSI_Period
        default: return carbonKeyCode
        }
    }

    var normalizedModifiers: NSEvent.ModifierFlags {
        modifiers.intersection([.command, .option, .control, .shift])
    }

    @MainActor
    func isConflicting(with other: KeyboardShortcuts.Shortcut) -> Bool {
        if self == other {
            return true
        }
        if normalizedModifiers == other.normalizedModifiers && normalizedKeyCode == other.normalizedKeyCode {
            return true
        }
        let cleanSelf = description.replacingOccurrences(of: "\u{20e3}", with: "")
        let cleanOther = other.description.replacingOccurrences(of: "\u{20e3}", with: "")
        if !cleanSelf.isEmpty && cleanSelf == cleanOther {
            return true
        }
        return false
    }
}

struct ShortcutSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel
    private struct ContextualShortcut: Identifiable {
        let id: String
        let scope: LocalizedStringKey
        let action: LocalizedStringKey
        /// One or more keycaps to render for this action. `.copy` in
        /// All-in-One lists all three bindings (⌘C, Return, ⌘⇧C) so users
        /// discover Return and ⌘⇧C alongside ⌘C — see issue #237.
        let shortcuts: [String]
    }

    private let contextualShortcuts: [ContextualShortcut] = [
        ContextualShortcut(id: "all-in-one-copy", scope: "All-in-One", action: "Copy selected area", shortcuts: ["⌘C", "⏎", "⌘⇧C"]),
        ContextualShortcut(id: "all-in-one-save", scope: "All-in-One", action: "Save selected area", shortcuts: ["⌘S"]),
        ContextualShortcut(id: "all-in-one-pin", scope: "All-in-One", action: "Pin selected area", shortcuts: ["⌘P"]),
        ContextualShortcut(id: "all-in-one-cancel", scope: "All-in-One", action: "Cancel", shortcuts: ["Esc"]),
        ContextualShortcut(id: "window-multi-select", scope: "Window Capture", action: "Select multiple windows", shortcuts: ["⇧ + click"]),
        ContextualShortcut(id: "window-multi-confirm", scope: "Window Capture", action: "Capture selected windows", shortcuts: ["Release ⇧"]),
        ContextualShortcut(id: "quick-access-copy", scope: "Quick Access", action: "Copy", shortcuts: ["⌘C"]),
        ContextualShortcut(id: "quick-access-save", scope: "Quick Access", action: "Save", shortcuts: ["⌘S"]),
        ContextualShortcut(id: "quick-access-annotate", scope: "Quick Access", action: "Annotate", shortcuts: ["⌘E"]),
        ContextualShortcut(id: "quick-access-pin", scope: "Quick Access", action: "Pin", shortcuts: ["⌘P"])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SystemScreenshotShortcutsCard()

            SettingGroup(title: "Customizable Shortcuts") {
                SettingCard {
                    shortcutRow("All-in-One", name: .captureAllInOne)
                    shortcutRow("Capture Area", name: .captureArea, showDivider: true)
                    shortcutRow("Capture Fullscreen", name: .captureFullscreen, showDivider: true)
                    shortcutRow("Capture Window", name: .captureWindow, showDivider: true)
                    shortcutRow("Capture Text (OCR)", name: .captureText, showDivider: true)
                    shortcutRow("Scrolling Capture", name: .captureScrolling, showDivider: true)
                    shortcutRow("Self-Timer", name: .selfTimerCapture, showDivider: true)
                    shortcutRow("Capture Area to Clipboard", name: .captureAreaToClipboard, showDivider: true)
                    shortcutRow("Capture and Share to Cloud", name: .captureAreaAndShare, showDivider: true)
                    shortcutRow("Capture Area & Annotate", name: .captureAreaAndAnnotate, showDivider: true)
                    shortcutRow("Capture Area & Pin", name: .captureAreaAndPin, showDivider: true)
                    shortcutRow(
                        "Pin from Clipboard",
                        name: .pinFromClipboard,
                        showDivider: true,
                        help: "Float copied images, text, colors, or files above other windows"
                    )
                    shortcutRow(
                        "Edit Clipboard Image",
                        name: .editClipboardImage,
                        showDivider: true,
                        help: "Open the image currently copied to the clipboard in Annotate"
                    )
                    shortcutRow("Hide / Show All Pins", name: .togglePins, showDivider: true)
                    shortcutRow("Capture & Translate", name: .captureAndTranslate, showDivider: true)
                    shortcutRow("Translate Selected Text", name: .translateSelectedText, showDivider: true)
                    shortcutRow("Translate Typed Text", name: .translateTypedText, showDivider: true)
                    shortcutRow("Capture Previous Area", name: .captureLastArea, showDivider: true)
                    shortcutRow("Record Area", name: .recordScreen, showDivider: true)
                    shortcutRow("Record Full Screen", name: .recordFullscreen, showDivider: true)
                    shortcutRow("Screenshot History", name: .screenshotHistory, showDivider: true)
                }
            }

            SettingGroup(title: "Contextual Shortcuts") {
                SettingCard {
                    centerLockRow
                    ForEach(Array(contextualShortcuts.enumerated()), id: \.element.id) { _, item in
                        contextualShortcutRow(item, showDivider: true)
                    }
                }
            }
        }
    }

    private var centerLockRow: some View {
        SettingRow(
            label: "Center 1:1 from click",
            sublabel: "Selection",
            showDivider: false
        ) {
            HStack(spacing: 6) {
                ShortcutKeycap(text: "⇧")
                Text("+")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                SquareCenterLockKeyRecorder(shortcut: $viewModel.squareCenterLockShortcut)
            }
        }
        .help("Hold Shift for 1:1, then this extra key to grow from the click as the center. Shift cannot be changed.")
    }

    @ViewBuilder
    private func shortcutRow(
        _ label: LocalizedStringKey,
        name: KeyboardShortcuts.Name,
        showDivider: Bool = false,
        help: LocalizedStringKey? = nil
    ) -> some View {
        let row = SettingRow(label: label, showDivider: showDivider) {
            CustomShortcutRecorder(name: name)
        }

        if let help {
            row.help(help)
        } else {
            row
        }
    }

    private func contextualShortcutRow(_ item: ContextualShortcut, showDivider: Bool = false) -> some View {
        SettingRow(label: item.action, sublabel: item.scope, showDivider: showDivider) {
            HStack(spacing: 6) {
                ForEach(Array(item.shortcuts.enumerated()), id: \.offset) { _, shortcut in
                    ShortcutKeycap(text: shortcut)
                }
            }
        }
    }
}

private struct SquareCenterLockKeyRecorder: View {
    @Binding var shortcut: SquareCenterLockShortcut
    @State private var isRecording = false

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            Text(isRecording ? "…" : shortcut.displayCharacter)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    Color.primary.opacity(isRecording ? 0.12 : 0.08),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isRecording ? Color.accentColor : Color.primary.opacity(0.10),
                            lineWidth: isRecording ? 1.5 : 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Extra key for centered 1:1")
        .accessibilityValue(shortcut.displayCharacter)
        .help("Click to record a different extra key")
        .background {
            if isRecording {
                KeyCapture(
                    onKeyDown: { event in
                        if event.keyCode == 53 {
                            isRecording = false
                            return
                        }
                        if let recorded = SquareCenterLockShortcut(event: event) {
                            shortcut = recorded
                            isRecording = false
                        }
                    },
                    onFlagsChanged: { _ in }
                )
            }
        }
    }
}

/// Local key & flags monitor for key recording.
private struct KeyCapture: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Void
    var onFlagsChanged: (NSEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown, onFlagsChanged: onFlagsChanged)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
        context.coordinator.onFlagsChanged = onFlagsChanged
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        var onKeyDown: (NSEvent) -> Void
        var onFlagsChanged: (NSEvent) -> Void
        private var monitor: Any?

        init(onKeyDown: @escaping (NSEvent) -> Void, onFlagsChanged: @escaping (NSEvent) -> Void) {
            self.onKeyDown = onKeyDown
            self.onFlagsChanged = onFlagsChanged
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                if event.type == .flagsChanged {
                    self?.onFlagsChanged(event)
                    return nil
                } else if event.type == .keyDown {
                    self?.onKeyDown(event)
                    return nil
                }
                return event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private struct ShortcutKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
    }
}

private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 6
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0
        ))
    }
}

private struct CustomShortcutRecorder: View {
    let name: KeyboardShortcuts.Name
    @State private var currentShortcut: KeyboardShortcuts.Shortcut?
    @State private var isRecording = false
    @State private var pressedModifiers: NSEvent.ModifierFlags = []
    @State private var errorMessage: String?
    @State private var shakeAttempts: CGFloat = 0
    @State private var errorDismissTask: Task<Void, Never>?
    @State private var isHovering = false

    private let recorderWidth: CGFloat = 135
    private let recorderHeight: CGFloat = 26

    var body: some View {
        ZStack {
            // Main button to start/stop recording, fills entire pill width
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                HStack(spacing: 4) {
                    if let errorMessage {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.red)
                        Text(errorMessage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.red)
                            .lineLimit(1)
                    } else if isRecording {
                        if !pressedModifiers.isEmpty {
                            Text(modifierSymbols(for: pressedModifiers))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Text("Type Shortcut")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    } else if let currentShortcut {
                        Text(formattedShortcut(currentShortcut.description))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    } else {
                        Text("Record Shortcut")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shortcut for \(displayName(for: name))")
            .accessibilityValue(currentShortcut?.description ?? "Not set")

            // Inline action buttons anchored to the right side of the pill
            if !isRecording && errorMessage == nil {
                HStack(spacing: 4) {
                    Spacer()

                    if isModifiedFromDefault {
                        Button {
                            resetToDefault()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Reset to default (\(name.defaultShortcut?.description ?? "none"))")
                    }

                    if currentShortcut != nil {
                        Button {
                            clearShortcut()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Clear shortcut")
                    }
                }
                .padding(.trailing, 6)
            }
        }
        .frame(width: recorderWidth, height: recorderHeight)
        .background(
            backgroundColor,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    borderColor,
                    lineWidth: (isRecording || errorMessage != nil) ? 1.5 : (isHovering ? 0.8 : 0.5)
                )
        )
        .modifier(ShakeEffect(animatableData: shakeAttempts))
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            currentShortcut = name.effectiveShortcut
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"))) { notification in
            if let changedName = notification.userInfo?["name"] as? KeyboardShortcuts.Name, changedName == name {
                currentShortcut = name.effectiveShortcut
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange"))) { notification in
            let isActive = (notification.userInfo?["isActive"] as? Bool) ?? false
            let activeName = notification.userInfo?["name"] as? KeyboardShortcuts.Name
            // Mutual exclusivity: if another recorder became active, stop recording this one
            if isActive, activeName != name, isRecording {
                stopRecording(notify: false)
            }
        }
        .background {
            if isRecording {
                KeyCapture(
                    onKeyDown: { event in
                        handleKeyEvent(event)
                    },
                    onFlagsChanged: { event in
                        handleFlagsChanged(event)
                    }
                )
            }
        }
    }

    private func formattedShortcut(_ description: String) -> String {
        // Space out glyphs and keycap for clean, professional macOS legibility (e.g. ⇧ ⌘ 1)
        var parts: [String] = []
        for char in description {
            parts.append(String(char))
        }
        return parts.joined(separator: " ")
    }

    private var isModifiedFromDefault: Bool {
        guard let defaultShortcut = name.defaultShortcut else {
            return false
        }
        guard let currentShortcut else {
            return true
        }
        return !currentShortcut.isConflicting(with: defaultShortcut)
    }

    private var backgroundColor: Color {
        if errorMessage != nil {
            return Color.red.opacity(0.12)
        } else if isRecording {
            return Color.accentColor.opacity(0.12)
        } else if isHovering {
            return Color.primary.opacity(0.08)
        } else {
            return Color.primary.opacity(0.05)
        }
    }

    private var borderColor: Color {
        if errorMessage != nil {
            return Color.red
        } else if isRecording {
            return Color.accentColor
        } else if isHovering {
            return Color.primary.opacity(0.20)
        } else {
            return Color.primary.opacity(0.12)
        }
    }

    private func startRecording() {
        errorDismissTask?.cancel()
        errorMessage = nil
        pressedModifiers = []
        isRecording = true

        // Temporarily unregister Carbon hotkeys so the keystrokes reach this recorder
        KeyboardShortcuts.disable(KeyboardShortcuts.Name.allCapso)

        NotificationCenter.default.post(
            name: Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange"),
            object: nil,
            userInfo: [
                "isActive": true,
                "name": name
            ]
        )
    }

    private func stopRecording(notify: Bool = true) {
        isRecording = false
        pressedModifiers = []

        // Re-enable Carbon hotkeys
        KeyboardShortcuts.enable(KeyboardShortcuts.Name.allCapso)

        if notify {
            NotificationCenter.default.post(
                name: Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange"),
                object: nil,
                userInfo: [
                    "isActive": false,
                    "name": name
                ]
            )
        }
    }

    private func clearShortcut() {
        KeyboardShortcuts.setShortcut(nil, for: name)
        if name.defaultShortcut != nil {
            UserDefaults.standard.set(false, forKey: "KeyboardShortcuts_" + name.rawValue)
        }
        currentShortcut = nil
        errorMessage = nil
    }

    private func resetToDefault() {
        name.resetRevertingConflicts()
        currentShortcut = name.effectiveShortcut
        errorMessage = nil
    }

    private func showInvalid(reason: String) {
        NSSound.beep()
        errorMessage = reason
        isRecording = false
        pressedModifiers = []
        withAnimation(.default) {
            shakeAttempts += 1
        }

        // Re-enable Carbon hotkeys when stopping with error
        KeyboardShortcuts.enable(KeyboardShortcuts.Name.allCapso)

        NotificationCenter.default.post(
            name: Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange"),
            object: nil,
            userInfo: [
                "isActive": false,
                "name": name
            ]
        )
        errorDismissTask?.cancel()
        errorDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.25)) {
                    errorMessage = nil
                }
            }
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let active = event.modifierFlags.intersection([.command, .option, .control, .shift])
        pressedModifiers = active
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Escape cancels recording without changing
        if event.keyCode == 53 {
            stopRecording()
            return
        }

        // Delete / Backspace clears shortcut
        if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            if event.keyCode == 51 || event.keyCode == 117 {
                clearShortcut()
                stopRecording()
                return
            }
        }

        // Requirement: Must contain at least 1 modifier key (or function key)
        let relevantModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let isOnlyShift = (relevantModifiers == .shift)
        let isFunctionKey = (event.modifierFlags.contains(.function) && event.keyCode >= 96 && event.keyCode <= 122)

        if relevantModifiers.isEmpty && !isFunctionKey {
            showInvalid(reason: "Modifier required")
            return
        }

        if isOnlyShift {
            showInvalid(reason: "Modifier required")
            return
        }

        guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
            showInvalid(reason: "Invalid key")
            return
        }

        // Duplicate conflict check across all Capso shortcuts
        if let conflict = conflictingShortcutName(for: shortcut) {
            showInvalid(reason: "Used by \(conflict)")
            return
        }

        // Conflict check against App main menu items and system/menu commands (e.g. ⌘Q, ⌘W, ⌘C, ⌘V, ⌘,)
        if let menuTitle = conflictingMenuItemTitle(for: event) {
            showInvalid(reason: "Used by \(menuTitle)")
            return
        }

        // Conflict check against system shortcuts (e.g. ⌘⇧3, ⌘⇧4, ⌘⇧5, Spotlight)
        if isSystemShortcut(shortcut) {
            showInvalid(reason: "Used by macOS")
            return
        }

        // Valid key combination: save and finish
        KeyboardShortcuts.setShortcut(shortcut, for: name)
        currentShortcut = shortcut
        stopRecording()
    }

    private func conflictingMenuItemTitle(for event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let unshiftedKey = unshiftedCharacter(for: event.keyCode, fallback: event.charactersIgnoringModifiers) else { return nil }

        // 1. Check NSApp.mainMenu
        if let mainMenu = NSApp.mainMenu,
           let item = findMenuItem(matching: unshiftedKey, modifiers: flags, in: mainMenu) {
            return cleanMenuTitle(item.title)
        }

        // 2. Check MenuBar status menu
        if let appDelegate = NSApp.delegate as? AppDelegate,
           let statusMenu = appDelegate.statusMenu,
           let item = findMenuItem(matching: unshiftedKey, modifiers: flags, in: statusMenu) {
            return cleanMenuTitle(item.title)
        }

        // 3. Check standard macOS reserved application shortcuts
        if flags == .command {
            switch unshiftedKey.lowercased() {
            case "q": return "Quit"
            case "w": return "Close"
            case "m": return "Minimize"
            case "h": return "Hide"
            case ",": return "Settings"
            case "c": return "Copy"
            case "v": return "Paste"
            case "x": return "Cut"
            case "a": return "Select All"
            case "z": return "Undo"
            case "s": return "Save"
            case "p": return "Print"
            case "o": return "Open"
            default: break
            }
        } else if flags == [.command, .shift] {
            switch unshiftedKey.lowercased() {
            case "z": return "Redo"
            case "q": return "Log Out"
            default: break
            }
        }

        return nil
    }

    private func cleanMenuTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "...", with: "")
            .replacingOccurrences(of: "…", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findMenuItem(matching key: String, modifiers: NSEvent.ModifierFlags, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            guard !item.keyEquivalent.isEmpty else {
                if let submenu = item.submenu, let found = findMenuItem(matching: key, modifiers: modifiers, in: submenu) {
                    return found
                }
                continue
            }

            var expectedModifiers = item.keyEquivalentModifierMask.intersection([.command, .option, .control, .shift])
            var itemKey = item.keyEquivalent
            if itemKey != itemKey.lowercased() {
                expectedModifiers.insert(.shift)
                itemKey = itemKey.lowercased()
            }

            if itemKey == key.lowercased() && expectedModifiers == modifiers {
                return item
            }

            if let submenu = item.submenu, let found = findMenuItem(matching: key, modifiers: modifiers, in: submenu) {
                return found
            }
        }
        return nil
    }

    private func unshiftedCharacter(for keyCode: UInt16, fallback: String? = nil) -> String? {
        switch Int(keyCode) {
        case kVK_ANSI_Keypad0: return "0"
        case kVK_ANSI_Keypad1: return "1"
        case kVK_ANSI_Keypad2: return "2"
        case kVK_ANSI_Keypad3: return "3"
        case kVK_ANSI_Keypad4: return "4"
        case kVK_ANSI_Keypad5: return "5"
        case kVK_ANSI_Keypad6: return "6"
        case kVK_ANSI_Keypad7: return "7"
        case kVK_ANSI_Keypad8: return "8"
        case kVK_ANSI_Keypad9: return "9"
        case kVK_ANSI_KeypadEnter, kVK_Return: return "\r"
        case kVK_ANSI_KeypadEquals: return "="
        case kVK_ANSI_KeypadMinus: return "-"
        case kVK_ANSI_KeypadDivide: return "/"
        case kVK_ANSI_KeypadDecimal: return "."
        default: break
        }

        let maxStringLength = 4
        var actualStringLength = 0
        var unicodeString = [UniChar](repeating: 0, count: maxStringLength)

        if let inputSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() ?? TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let layoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) {
            let layout = unsafeBitCast(layoutData, to: CFData.self)
            let layoutPtr = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<CoreServices.UCKeyboardLayout>.self)

            var deadKeyState: UInt32 = 0
            let result = CoreServices.UCKeyTranslate(
                layoutPtr,
                keyCode,
                UInt16(CoreServices.kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(CoreServices.kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                maxStringLength,
                &actualStringLength,
                &unicodeString
            )
            if result == noErr, actualStringLength > 0 {
                return String(utf16CodeUnits: unicodeString, count: actualStringLength)
            }
        }

        return fallback
    }

    private func isSystemShortcut(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        var shortcutsUnmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&shortcutsUnmanaged) == noErr,
              let shortcuts = shortcutsUnmanaged?.takeRetainedValue() as? [[String: Any]] else {
            return false
        }
        for item in shortcuts {
            let isEnabled = (item[kHISymbolicHotKeyEnabled] as? Bool) ?? ((item[kHISymbolicHotKeyEnabled] as? Int) == 1)
            guard isEnabled,
                  let carbonKeyCode = (item[kHISymbolicHotKeyCode] as? Int) ?? (item[kHISymbolicHotKeyCode] as? NSNumber)?.intValue,
                  let carbonModifiers = (item[kHISymbolicHotKeyModifiers] as? Int) ?? (item[kHISymbolicHotKeyModifiers] as? NSNumber)?.intValue else {
                continue
            }
            let systemShortcut = KeyboardShortcuts.Shortcut(
                carbonKeyCode: carbonKeyCode,
                carbonModifiers: carbonModifiers
            )
            if systemShortcut.isConflicting(with: shortcut) {
                return true
            }
        }
        return false
    }

    private func conflictingShortcutName(for shortcut: KeyboardShortcuts.Shortcut) -> String? {
        for otherName in KeyboardShortcuts.Name.allCapso where otherName != name {
            if let otherShortcut = otherName.effectiveShortcut, otherShortcut.isConflicting(with: shortcut) {
                return displayName(for: otherName)
            }
        }
        return nil
    }

    private func displayName(for name: KeyboardShortcuts.Name) -> String {
        switch name {
        case .captureAllInOne: return "All-in-One"
        case .captureArea: return "Capture Area"
        case .captureFullscreen: return "Fullscreen"
        case .captureWindow: return "Capture Window"
        case .captureText: return "Capture Text"
        case .recordScreen: return "Record Area"
        case .recordFullscreen: return "Record Fullscreen"
        case .captureScrolling: return "Scrolling Capture"
        case .captureAreaToClipboard: return "Area to Clipboard"
        case .captureAreaAndShare: return "Share to Cloud"
        case .captureAreaAndAnnotate: return "Area & Annotate"
        case .captureAreaAndPin: return "Area & Pin"
        case .pinFromClipboard: return "Pin Clipboard"
        case .editClipboardImage: return "Edit Clipboard"
        case .screenshotHistory: return "History"
        case .captureAndTranslate: return "Translate"
        case .translateSelectedText: return "Translate Text"
        case .translateTypedText: return "Translate Typed"
        case .selfTimerCapture: return "Self-Timer"
        case .captureLastArea: return "Previous Area"
        case .togglePins: return "Toggle Pins"
        default: return name.rawValue
        }
    }

    private func modifierSymbols(for flags: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols.isEmpty ? "Type Shortcut" : symbols
    }
}

/// Helps hand ⇧⌘3 / ⇧⌘4 / ⇧⌘5 over from the macOS screenshot tool to Capso.
private struct SystemScreenshotShortcutsCard: View {
    @State private var systemShortcutsOn = SystemScreenshotShortcuts.areEnabled
    @State private var capsoUsesAny = Self.capsoUsesAnySystemKey

    private static let assignments: [(KeyboardShortcuts.Name, KeyboardShortcuts.Key)] = [
        (.captureFullscreen, .three), (.captureArea, .four), (.captureAllInOne, .five),
    ]

    /// Once any Capso action uses one of these keys, the user has set them up themselves.
    private static var capsoUsesAnySystemKey: Bool {
        let systemKeys = assignments.map { KeyboardShortcuts.Shortcut($0.1, modifiers: [.command, .shift]) }
        return KeyboardShortcuts.Name.allCapso.contains { name in
            name.effectiveShortcut.map(systemKeys.contains) ?? false
        }
    }

    var body: some View {
        Group {
            if systemShortcutsOn {
                banner(
                    icon: "exclamationmark.triangle",
                    tint: .orange,
                    text: "macOS still uses ⇧⌘3, ⇧⌘4 and ⇧⌘5 for its own screenshots. To use them for Capso, turn off the shortcuts under Keyboard Shortcuts → Screenshots."
                ) {
                    Button("Open Keyboard Settings") { NSWorkspace.shared.open(SystemScreenshotShortcuts.settingsURL) }
                }
            } else if !capsoUsesAny {
                banner(
                    icon: "keyboard",
                    tint: .blue,
                    text: "The macOS screenshot shortcuts are off. Capso can take them over: ⇧⌘3 Capture Fullscreen, ⇧⌘4 Capture Area, ⇧⌘5 All-in-One."
                ) {
                    Button("Use ⇧⌘3 / ⇧⌘4 / ⇧⌘5") {
                        for (name, key) in Self.assignments {
                            KeyboardShortcuts.setShortcut(.init(key, modifiers: [.command, .shift]), for: name)
                        }
                        capsoUsesAny = true
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            systemShortcutsOn = SystemScreenshotShortcuts.areEnabled
            capsoUsesAny = Self.capsoUsesAnySystemKey
        }
    }

    private func banner(icon: String, tint: Color, text: LocalizedStringKey, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.2), lineWidth: 0.5))
    }
}
