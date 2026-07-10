# Automation URLs Design

## Context

GitHub discussion #124 asks Capso to expose a custom URL scheme so Alfred, Raycast, Shortcuts, scripts, and other apps can trigger existing capture actions. Capso's product design already names the initial routes:

- `capso://grab/area`
- `capso://grab/fullscreen`
- `capso://grab/window`

Capso already routes menu items and global shortcuts through `CaptureCoordinator`, so Automation URLs should be another thin app-shell entry point rather than a new capture implementation.

MacShot demonstrates the smallest viable integration: register a URL scheme, receive URLs in `NSApplicationDelegate`, and dispatch recognized actions to existing methods. Capso will follow that behavior while keeping parsing testable, preserving cold-launch requests, and respecting its existing capture-flow lifecycle.

## Goals

- Let external apps trigger area, fullscreen, and window capture through the three documented `capso://grab/...` routes.
- Keep Automation URLs opt-in through a persisted Preferences toggle that defaults to off.
- Support both warm launches and launches caused by opening an Automation URL.
- Reuse the same `CaptureCoordinator` methods as menu items and global shortcuts, including existing post-capture settings.
- Ignore Automation URLs while an interactive capture selection flow is already active.
- Add focused unit tests for route parsing and setting persistence without opening capture UI.
- Document the supported commands in Preferences.
- Localize the new Preferences copy in every locale already present in Capso's string catalog.

## Non-Goals

- Do not add Shottr-style `then=` post-capture parameters.
- Do not add OCR, scrolling capture, recording, history, settings, file-open, or callback routes.
- Do not add a command-line interface, Alfred workflow, Raycast extension, or Shortcuts action.
- Do not queue multiple Automation URLs.
- Do not interrupt, restart, or notify an existing capture selection flow.
- Do not change normal menu or global-shortcut behavior.

## Considered Approaches

### 1. Parse and switch directly in `AppDelegate`

This is the smallest code diff and closely resembles MacShot. It also leaves URL grammar embedded in a large lifecycle class, makes parser behavior difficult to unit test, and encourages future routes to grow an unstructured string switch.

### 2. Add an app-specific Xcode unit-test target

This keeps every type in the app target and can test an app-local parser. It also adds project and hosted-test configuration solely for a small Foundation-only value type. Capso's generated scheme currently has no test action, so this adds disproportionate test infrastructure.

### 3. Put the parser and setting in `SharedKit`, keep execution in the app shell

This keeps the route grammar in a small Foundation-only enum with existing Swift Package tests. `AppDelegate` remains responsible for lifecycle and dispatch, while `CaptureCoordinator` exposes only the minimal busy-state query needed by the app shell.

This is the selected approach because it fits Capso's thin-app-shell architecture and provides focused tests without new project-level test infrastructure.

## URL Grammar

`AutomationURLAction` in `SharedKit` recognizes exactly these URLs:

| URL | Action |
|---|---|
| `capso://grab/area` | `.captureArea` |
| `capso://grab/fullscreen` | `.captureFullscreen` |
| `capso://grab/window` | `.captureWindow` |

Parsing rules:

- Scheme and host comparisons are case-insensitive.
- The path contains exactly one supported action component.
- Query items, fragments, credentials, ports, empty actions, extra path components, unsupported hosts, and unsupported schemes are rejected.
- Invalid or unsupported URLs have no side effects.

## Persistence And Preferences

Add `AppSettings.automationURLsEnabled`, backed by `UserDefaults` and defaulting to `false`.

Preferences > General gains an **Automation** group containing:

- `Automation URLs` toggle.
- Explanatory text stating that other apps can trigger Capso captures.
- A monospaced list of the three supported URLs.

The URL scheme remains registered in `Info.plist`; disabling the setting makes Capso ignore recognized Automation URLs because macOS does not dynamically register and unregister bundle URL types.

## Application Flow

1. macOS delivers opened URLs through `application(_:open:)`.
2. `AppDelegate` ignores URLs when Automation URLs are disabled.
3. `AutomationURLAction` parses recognized URLs.
4. `AppDelegate` stores at most the first recognized action when coordinators are not ready. Additional actions are ignored rather than queued.
5. After launch initialization creates `CaptureCoordinator`, `AppDelegate` consumes the pending action.
6. Before dispatch, `AppDelegate` checks the coordinator's capture-selection busy state.
7. If busy, the action is discarded without interrupting, queueing, or notifying.
8. Otherwise, the action calls the corresponding existing coordinator method.

Recognized actions are consumed exactly once. Unknown URLs and ignored actions may write a diagnostic entry when diagnostic logging is enabled, but never show user-facing errors.

## Capture Busy State

`CaptureCoordinator` exposes a read-only `isCaptureSelectionActive` property for app-shell routing. It reports true while:

- an area, window, scrolling, self-timer, or all-in-one selection is scheduled but its overlay has not appeared yet;
- capture selection overlays are visible;
- the all-in-one toolbar or self-timer HUD continues the interactive selection flow.

The state returns to false when the flow completes or is cancelled. The coordinator continues to own this state; `AppDelegate` does not inspect window arrays or UI implementation details.

## Error Handling And Safety

- The toggle defaults to off so an external app or webpage cannot trigger captures until the user opts in.
- Unsupported or malformed URLs are silently ignored.
- Busy-state requests are silently ignored, matching the existing product design.
- Cold-launch handling retains one action only until coordinators are ready.
- Automation actions reuse current permission checks and capture behavior; no new permissions are introduced.

## Tests And Verification

`SharedKit` tests cover:

- each supported URL maps to the correct action;
- case-insensitive scheme and host handling;
- malformed, unsupported, parameterized, and extra-component URLs are rejected;
- the preference defaults to off and persists when enabled.

Integration verification covers:

- `xcodegen generate` succeeds;
- all Swift package tests pass;
- the Capso app builds under Swift 6 strict concurrency;
- with the setting disabled, `open 'capso://grab/area'` has no effect;
- with the setting enabled, each supported route starts its existing capture flow;
- launching Capso through a supported URL consumes the action once;
- a second URL during an active selection does not replace the current flow.
