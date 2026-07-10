# Automation URLs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add opt-in `capso://grab/area`, `capso://grab/fullscreen`, and `capso://grab/window` entry points that reuse Capso's existing capture workflows.

**Architecture:** `SharedKit` owns a Foundation-only URL parser, a one-item cold-launch request buffer, and the persisted enablement setting. `AppDelegate` receives URLs and dispatches buffered actions to `CaptureCoordinator`; the coordinator exposes a read-only busy state without leaking its window implementation. Preferences documents and controls the feature.

**Tech Stack:** Swift 6.0, Foundation, AppKit `NSApplicationDelegate`, SwiftUI, Swift Testing, XcodeGen, XCStrings.

## Global Constraints

- Target macOS 15.0 or newer and preserve Swift 6.0 strict concurrency.
- Support exactly `capso://grab/area`, `capso://grab/fullscreen`, and `capso://grab/window`.
- Scheme and host are case-insensitive; action paths are exact lowercase names.
- Reject query items, fragments, credentials, ports, and extra path components.
- Keep Automation URLs disabled by default.
- Retain at most one cold-launch action; never queue multiple actions.
- Ignore an Automation URL while interactive capture selection is active.
- Reuse existing capture and post-capture workflows; do not add `then=`, OCR, scrolling, recording, callbacks, CLI commands, or third-party workflow artifacts.
- Localize new Preferences strings for `en`, `ja`, `ko`, and `zh-Hans`.

---

### Task 1: Add The Tested Automation URL Protocol

**Files:**
- Create: `Packages/SharedKit/Sources/SharedKit/AutomationURLAction.swift`
- Create: `Packages/SharedKit/Tests/SharedKitTests/AutomationURLActionTests.swift`

**Interfaces:**
- Consumes: `Foundation.URL`.
- Produces: `public enum AutomationURLAction: Equatable, Sendable` and `public struct AutomationURLRequestBuffer: Sendable`.

- [ ] **Step 1: Write failing parser and buffer tests**

Create `AutomationURLActionTests.swift` with these cases:

```swift
import Foundation
import Testing
@testable import SharedKit

@Suite("Automation URL actions")
struct AutomationURLActionTests {
    @Test("Supported URLs map to capture actions")
    func supportedURLs() {
        let cases: [(String, AutomationURLAction)] = [
            ("capso://grab/area", .captureArea),
            ("capso://grab/fullscreen", .captureFullscreen),
            ("capso://grab/window", .captureWindow),
            ("CAPSO://GRAB/area", .captureArea),
        ]

        for (rawURL, expected) in cases {
            #expect(AutomationURLAction(url: URL(string: rawURL)!) == expected)
        }
    }

    @Test("Unsupported or parameterized URLs are rejected")
    func unsupportedURLs() {
        let urls = [
            "https://grab/area",
            "capso://capture/area",
            "capso://grab",
            "capso://grab/AREA",
            "capso://grab/ocr",
            "capso://grab/area/extra",
            "capso://grab/area?then=save",
            "capso://grab/area#fragment",
            "capso://user@grab/area",
            "capso://grab:123/area",
        ]

        for rawURL in urls {
            #expect(AutomationURLAction(url: URL(string: rawURL)!) == nil)
        }
    }

    @Test("Request buffer retains only the first action until ready")
    func retainsFirstAction() {
        var buffer = AutomationURLRequestBuffer()
        buffer.enqueue(.captureArea)
        buffer.enqueue(.captureWindow)

        #expect(buffer.takeIfReady(
            coordinatorIsReady: false,
            captureSelectionIsActive: false
        ) == nil)
        #expect(buffer.takeIfReady(
            coordinatorIsReady: true,
            captureSelectionIsActive: false
        ) == .captureArea)
        #expect(buffer.takeIfReady(
            coordinatorIsReady: true,
            captureSelectionIsActive: false
        ) == nil)
    }

    @Test("Busy selection consumes and discards the pending action")
    func busySelectionDropsAction() {
        var buffer = AutomationURLRequestBuffer()
        buffer.enqueue(.captureFullscreen)

        #expect(buffer.takeIfReady(
            coordinatorIsReady: true,
            captureSelectionIsActive: true
        ) == nil)
        #expect(buffer.takeIfReady(
            coordinatorIsReady: true,
            captureSelectionIsActive: false
        ) == nil)
    }
}
```

- [ ] **Step 2: Run the tests and verify the RED state**

Run:

```bash
rtk swift test --package-path Packages/SharedKit
```

Expected: compilation fails because `AutomationURLAction` and `AutomationURLRequestBuffer` do not exist.

- [ ] **Step 3: Implement the minimal parser and one-item buffer**

Create `AutomationURLAction.swift`:

```swift
import Foundation

public enum AutomationURLAction: Equatable, Sendable {
    case captureArea
    case captureFullscreen
    case captureWindow

    public init?(url: URL) {
        guard url.scheme?.caseInsensitiveCompare("capso") == .orderedSame,
              url.host?.caseInsensitiveCompare("grab") == .orderedSame,
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.query == nil,
              url.fragment == nil else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count == 1 else { return nil }

        switch pathComponents[0] {
        case "area": self = .captureArea
        case "fullscreen": self = .captureFullscreen
        case "window": self = .captureWindow
        default: return nil
        }
    }
}

public struct AutomationURLRequestBuffer: Sendable {
    private var pendingAction: AutomationURLAction?

    public init() {}

    public mutating func enqueue(_ action: AutomationURLAction) {
        guard pendingAction == nil else { return }
        pendingAction = action
    }

    public mutating func takeIfReady(
        coordinatorIsReady: Bool,
        captureSelectionIsActive: Bool
    ) -> AutomationURLAction? {
        guard coordinatorIsReady, let action = pendingAction else { return nil }
        pendingAction = nil
        guard !captureSelectionIsActive else { return nil }
        return action
    }
}
```

- [ ] **Step 4: Run SharedKit tests and verify GREEN**

Run:

```bash
rtk swift test --package-path Packages/SharedKit
```

Expected: all existing tests plus the four Automation URL tests pass.

- [ ] **Step 5: Commit the protocol**

```bash
rtk git add Packages/SharedKit/Sources/SharedKit/AutomationURLAction.swift Packages/SharedKit/Tests/SharedKitTests/AutomationURLActionTests.swift
rtk git commit -m "feat: add automation URL protocol"
```

---

### Task 2: Persist Opt-In Enablement

**Files:**
- Modify: `Packages/SharedKit/Sources/SharedKit/Settings/AppSettings.swift:194-211`
- Modify: `Packages/SharedKit/Tests/SharedKitTests/AppSettingsTests.swift:155-191`

**Interfaces:**
- Consumes: the existing injected `UserDefaults` in `AppSettings`.
- Produces: `public var automationURLsEnabled: Bool`, defaulting to `false`.

- [ ] **Step 1: Write failing settings tests**

Add beside the diagnostic logging tests:

```swift
@Test("Automation URLs are disabled by default")
func defaultAutomationURLsEnabled() {
    let suite = "test.automationURLs.default"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let settings = AppSettings(defaults: defaults)
    #expect(settings.automationURLsEnabled == false)
}

@Test("Automation URL preference persists across instances")
func automationURLsEnabledPersists() {
    let suite = "test.automationURLs.persists"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let first = AppSettings(defaults: defaults)
    first.automationURLsEnabled = true
    let second = AppSettings(defaults: defaults)
    #expect(second.automationURLsEnabled == true)
}
```

- [ ] **Step 2: Run the focused package tests and verify RED**

Run:

```bash
rtk swift test --package-path Packages/SharedKit
```

Expected: compilation fails because `AppSettings.automationURLsEnabled` does not exist.

- [ ] **Step 3: Add the persisted setting**

Add under `diagnosticLoggingEnabled`:

```swift
public var automationURLsEnabled: Bool {
    get { defaults.object(forKey: "automationURLsEnabled") as? Bool ?? false }
    set { defaults.set(newValue, forKey: "automationURLsEnabled") }
}
```

- [ ] **Step 4: Run SharedKit tests and verify GREEN**

Run `rtk swift test --package-path Packages/SharedKit`.

Expected: all SharedKit tests pass.

- [ ] **Step 5: Commit the preference**

```bash
rtk git add Packages/SharedKit/Sources/SharedKit/Settings/AppSettings.swift Packages/SharedKit/Tests/SharedKitTests/AppSettingsTests.swift
rtk git commit -m "feat: persist automation URL preference"
```

---

### Task 3: Expose Capture Selection Busy State

**Files:**
- Modify: `App/Sources/Capture/CaptureCoordinator.swift:14-42, 215-330, 360-430, 660-720, 897-925`

**Interfaces:**
- Consumes: the coordinator's existing overlay, all-in-one toolbar, and self-timer lifecycle.
- Produces: internal read-only `var isCaptureSelectionActive: Bool` for `AppDelegate`.

- [ ] **Step 1: Re-run the tested busy-discard policy before integration**

Run `rtk swift test --package-path Packages/SharedKit`.

Expected: the request-buffer test `Busy selection consumes and discards the pending action` passes.

- [ ] **Step 2: Track selection flows scheduled before overlays exist**

Add near `overlayWindows`:

```swift
private var isSelectionFlowStarting = false

var isCaptureSelectionActive: Bool {
    isSelectionFlowStarting
        || !overlayWindows.isEmpty
        || allInOneToolbarWindow != nil
        || selfTimerHUD != nil
}
```

Set `isSelectionFlowStarting = true` at the beginning of:

```swift
func captureAllInOne()
private func startAreaCapture()
func captureScrolling()
func captureAreaWithSelfTimer()
func captureWindow()
```

In `captureWindow()`, set it back to `false` before returning for no windows and inside `catch`.

At the start of `dismissOverlay()`, reset it:

```swift
private func dismissOverlay() {
    isSelectionFlowStarting = false
    dismissSelectionOverlays()
    dismissFreezeWindows()
}
```

The overlay presentation methods call `dismissOverlay()` synchronously before appending their windows, so the computed property moves directly from `isSelectionFlowStarting` to `!overlayWindows.isEmpty` without a main-run-loop gap.

- [ ] **Step 3: Regenerate and build the app**

Run:

```bash
rtk xcodegen generate
rtk xcodebuild -project Capso.xcodeproj -scheme Capso -configuration Debug build
```

Expected: build succeeds with no new Swift concurrency errors.

- [ ] **Step 4: Commit the busy-state boundary**

```bash
rtk git add App/Sources/Capture/CaptureCoordinator.swift
rtk git commit -m "feat: expose capture selection activity"
```

---

### Task 4: Register And Dispatch Automation URLs

**Files:**
- Modify: `App/Resources/Info.plist:1-20`
- Modify: `App/Sources/AppDelegate.swift:9-105, 121-180`

**Interfaces:**
- Consumes: `AutomationURLAction`, `AutomationURLRequestBuffer`, `AppSettings.automationURLsEnabled`, and `CaptureCoordinator.isCaptureSelectionActive`.
- Produces: macOS registration for `capso://` and warm/cold lifecycle dispatch.

- [ ] **Step 1: Register the bundle URL type**

Add after `CFBundleExecutable`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>Capso Automation</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>capso</string>
        </array>
    </dict>
</array>
```

- [ ] **Step 2: Add the one-item request buffer and URL delegate callback**

Add to `AppDelegate` properties:

```swift
private var automationURLRequestBuffer = AutomationURLRequestBuffer()
```

Add the delegate callback and dispatch helpers:

```swift
func application(_ application: NSApplication, open urls: [URL]) {
    guard settings.automationURLsEnabled else {
        logAutomationURL("Ignored request because Automation URLs are disabled")
        return
    }
    guard let action = urls.lazy.compactMap(AutomationURLAction.init(url:)).first else {
        logAutomationURL("Ignored unsupported request")
        return
    }

    automationURLRequestBuffer.enqueue(action)
    performPendingAutomationURLAction()
}

private func performPendingAutomationURLAction() {
    let selectionIsActive = captureCoordinator?.isCaptureSelectionActive ?? false
    guard let action = automationURLRequestBuffer.takeIfReady(
        coordinatorIsReady: captureCoordinator != nil,
        captureSelectionIsActive: selectionIsActive
    ), let captureCoordinator else {
        return
    }

    switch action {
    case .captureArea:
        captureCoordinator.captureArea()
    case .captureFullscreen:
        captureCoordinator.captureFullscreen()
    case .captureWindow:
        captureCoordinator.captureWindow()
    }
    logAutomationURL("Performed action \(String(describing: action))")
}

private func logAutomationURL(_ message: String) {
    guard settings.diagnosticLoggingEnabled else { return }
    DiagnosticLogger.append(message, category: "AutomationURL")
}
```

Call `performPendingAutomationURLAction()` in `applicationDidFinishLaunching` after `registerGlobalShortcuts()` so a cold-launch request is consumed once coordinators are ready.

- [ ] **Step 3: Validate plist and build integration**

Run:

```bash
rtk plutil -lint App/Resources/Info.plist
rtk xcodegen generate
rtk xcodebuild -project Capso.xcodeproj -scheme Capso -configuration Debug \
  -derivedDataPath /tmp/CapsoAutomationURLsDerivedData build
```

Expected: plist reports `OK` and the app builds successfully.

- [ ] **Step 4: Verify the generated app contains the scheme**

Run:

```bash
rtk plutil -extract CFBundleURLTypes json -o - \
  /tmp/CapsoAutomationURLsDerivedData/Build/Products/Debug/Capso.app/Contents/Info.plist
```

Expected: JSON includes the `capso` scheme and `Capso Automation` name.

- [ ] **Step 5: Commit lifecycle integration**

```bash
rtk git add App/Resources/Info.plist App/Sources/AppDelegate.swift
rtk git commit -m "feat: dispatch capso automation URLs"
```

---

### Task 5: Add Preferences UI And Localizations

**Files:**
- Modify: `App/Sources/Preferences/PreferencesViewModel.swift:35-72`
- Modify: `App/Sources/Preferences/Tabs/GeneralSettingsView.swift:24-55`
- Modify: `App/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `AppSettings.automationURLsEnabled`.
- Produces: a General > Automation toggle and visible list of supported URLs.

- [ ] **Step 1: Add the observable view-model binding**

Add beside `diagnosticLoggingEnabled`:

```swift
var automationURLsEnabled: Bool {
    get {
        access(keyPath: \.automationURLsEnabled)
        return settings.automationURLsEnabled
    }
    set {
        withMutation(keyPath: \.automationURLsEnabled) {
            settings.automationURLsEnabled = newValue
        }
    }
}
```

- [ ] **Step 2: Add the Automation settings group**

Insert between Startup and Sound:

```swift
SettingGroup(title: "Automation") {
    SettingCard {
        SettingRow(
            label: "Automation URLs",
            sublabel: "Allow Alfred, Raycast, Shortcuts, and other apps to trigger captures"
        ) {
            Toggle("", isOn: $viewModel.automationURLsEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        SettingRow(label: "Supported URLs", showDivider: true) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: "capso://grab/area")
                Text(verbatim: "capso://grab/fullscreen")
                Text(verbatim: "capso://grab/window")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
    }
}
```

- [ ] **Step 3: Add localized catalog entries**

Add these exact translations to `Localizable.xcstrings`:

| Key | en | ja | ko | zh-Hans |
|---|---|---|---|---|
| `Automation` | Automation | 自動化 | 자동화 | 自动化 |
| `Automation URLs` | Automation URLs | 自動化 URL | 자동화 URL | 自动化 URL |
| `Allow Alfred, Raycast, Shortcuts, and other apps to trigger captures` | Allow Alfred, Raycast, Shortcuts, and other apps to trigger captures | Alfred、Raycast、ショートカットなどのアプリからキャプチャを実行できるようにします | Alfred, Raycast, 단축어 및 기타 앱에서 캡처를 실행하도록 허용 | 允许 Alfred、Raycast、快捷指令和其他应用触发截图 |
| `Supported URLs` | Supported URLs | 対応 URL | 지원되는 URL | 支持的 URL |

- [ ] **Step 4: Run tests and build**

Run:

```bash
rtk swift test --package-path Packages/SharedKit
rtk xcodegen generate
rtk xcodebuild -project Capso.xcodeproj -scheme Capso -configuration Debug build
```

Expected: SharedKit tests and the app build pass.

- [ ] **Step 5: Commit Preferences**

```bash
rtk git add App/Sources/Preferences/PreferencesViewModel.swift App/Sources/Preferences/Tabs/GeneralSettingsView.swift App/Resources/Localizable.xcstrings
rtk git commit -m "feat: add automation URL settings"
```

---

### Task 6: Complete Verification

**Files:**
- Verify only; modify implementation files only if a failing check identifies a defect in this feature.

**Interfaces:**
- Consumes: all outputs from Tasks 1-5.
- Produces: evidence that parsing, persistence, registration, build, and repository tests pass.

- [ ] **Step 1: Verify formatting and generated project consistency**

Run:

```bash
rtk git diff --check origin/main...HEAD
rtk xcodegen generate
rtk git status --short
```

Expected: no whitespace errors; only intended tracked files differ from `origin/main`; generated `Capso.xcodeproj` remains ignored.

- [ ] **Step 2: Run all package tests**

Run each package test command:

```bash
rtk swift test --package-path Packages/SharedKit
rtk swift test --package-path Packages/CaptureKit
rtk swift test --package-path Packages/AnnotationKit
rtk swift test --package-path Packages/CameraKit
rtk swift test --package-path Packages/RecordingKit
rtk swift test --package-path Packages/OCRKit
rtk swift test --package-path Packages/TranslationKit
rtk swift test --package-path Packages/EffectsKit
rtk swift test --package-path Packages/ExportKit
rtk swift test --package-path Packages/EditorKit
rtk swift test --package-path Packages/HistoryKit
rtk swift test --package-path Packages/ShareKit
```

Expected: all package test suites pass.

- [ ] **Step 3: Run the final App build**

Run:

```bash
rtk xcodebuild -project Capso.xcodeproj -scheme Capso -configuration Debug build
```

Expected: `BUILD SUCCEEDED` with no new errors introduced by this branch.

- [ ] **Step 4: Inspect the final diff and commit any verification-only correction**

Run:

```bash
rtk git diff --stat origin/main...HEAD
rtk git diff origin/main...HEAD
rtk git status --short --branch
```

Expected: the diff contains only the approved Automation URL protocol, setting, capture busy boundary, app routing, Info.plist registration, Preferences UI, localization, tests, and planning docs. If verification required a correction, commit it with a scoped `fix:` message; otherwise create no empty commit.
