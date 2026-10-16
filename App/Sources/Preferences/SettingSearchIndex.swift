// App/Sources/Preferences/SettingSearchIndex.swift
import SwiftUI

struct SettingSearchItem: Identifiable, Hashable, Sendable {
    let id: String
    let tab: PreferencesTab
    let title: String
    let section: String
    let subtitle: String?
    let keywords: [String]

    init(
        id: String,
        tab: PreferencesTab,
        title: String,
        section: String,
        subtitle: String? = nil,
        keywords: [String] = []
    ) {
        self.id = id
        self.tab = tab
        self.title = title
        self.section = section
        self.subtitle = subtitle
        self.keywords = keywords
    }

    var breadcrumb: String {
        if section.lowercased() == tab.displayTitle.lowercased() || section.isEmpty {
            return tab.displayTitle
        }
        return "\(tab.displayTitle) > \(section)"
    }

    func matches(query: String) -> Bool {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return false }

        let tokens = cleaned.split(separator: " ")
        if tokens.isEmpty { return false }

        return tokens.allSatisfy { token in
            let term = String(token)
            if title.localizedCaseInsensitiveContains(term) { return true }
            if section.localizedCaseInsensitiveContains(term) { return true }
            if tab.displayTitle.localizedCaseInsensitiveContains(term) { return true }
            if let subtitle, subtitle.localizedCaseInsensitiveContains(term) { return true }
            return keywords.contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }
}

enum SettingSearchIndex {
    static let items: [SettingSearchItem] = [
        // MARK: - General
        SettingSearchItem(
            id: "general-tab",
            tab: .general,
            title: "General",
            section: "General",
            keywords: ["app settings", "preferences", "config", "options"]
        ),
        SettingSearchItem(
            id: "general-launch-at-login",
            tab: .general,
            title: "Launch at Login",
            section: "Startup",
            subtitle: "Start Capso when you log in",
            keywords: ["startup", "boot", "autostart", "open at login", "login item"]
        ),
        SettingSearchItem(
            id: "general-menu-bar-icon",
            tab: .general,
            title: "Show Menu Bar Icon",
            section: "Startup",
            subtitle: "Hide for a minimalist menu bar — shortcuts still work",
            keywords: ["menu bar", "status bar", "dock", "tray icon", "hide icon", "minimalist"]
        ),
        SettingSearchItem(
            id: "general-automation-urls",
            tab: .general,
            title: "Automation URLs",
            section: "Automation",
            subtitle: "Allow Alfred, Raycast, Shortcuts, and other apps to trigger captures",
            keywords: ["url scheme", "raycast", "alfred", "apple shortcuts", "x-callback-url", "cli", "scripts", "deep link"]
        ),
        SettingSearchItem(
            id: "general-supported-urls",
            tab: .general,
            title: "Supported URLs",
            section: "Automation",
            subtitle: "View all commands for Raycast, Alfred, and Shortcuts",
            keywords: ["url commands", "deep links", "actions"]
        ),
        SettingSearchItem(
            id: "general-shutter-sound",
            tab: .general,
            title: "Shutter Sound",
            section: "Sound",
            subtitle: "Play sound after capture",
            keywords: ["sound", "audio", "camera sound", "click", "beep", "mute", "chime"]
        ),
        SettingSearchItem(
            id: "general-check-updates",
            tab: .general,
            title: "Automatically Check for Updates",
            section: "Updates",
            subtitle: "Look for new versions in the background",
            keywords: ["software update", "sparkle", "new version", "upgrade", "check for updates"]
        ),
        SettingSearchItem(
            id: "general-check-frequency",
            tab: .general,
            title: "Check Frequency",
            section: "Updates",
            subtitle: "Hourly, Daily, Weekly, Monthly",
            keywords: ["interval", "how often", "schedule"]
        ),
        SettingSearchItem(
            id: "general-auto-install-updates",
            tab: .general,
            title: "Automatically Install Updates",
            section: "Updates",
            subtitle: "Install updates in the background when available",
            keywords: ["auto update", "silent install", "automatic install"]
        ),
        SettingSearchItem(
            id: "general-check-now",
            tab: .general,
            title: "Check for Updates",
            section: "Updates",
            subtitle: "Look for a new version now",
            keywords: ["update now", "check updates now"]
        ),
        SettingSearchItem(
            id: "general-save-history",
            tab: .general,
            title: "Save to History",
            section: "History",
            subtitle: "Automatically save all captures",
            keywords: ["history", "database", "recent captures", "store", "save screenshots"]
        ),
        SettingSearchItem(
            id: "general-keep-history",
            tab: .general,
            title: "Keep History",
            section: "History",
            subtitle: "Auto-delete older captures",
            keywords: ["retention", "cleanup", "duration", "auto-delete", "1 week", "2 weeks", "1 month", "unlimited"]
        ),
        SettingSearchItem(
            id: "general-diagnostic-logging",
            tab: .general,
            title: "Diagnostic Logging",
            section: "Diagnostics",
            subtitle: "Write local troubleshooting logs when enabled",
            keywords: ["troubleshooting", "debug", "logs", "error log"]
        ),
        SettingSearchItem(
            id: "general-diagnostic-logs",
            tab: .general,
            title: "Diagnostic Logs",
            section: "Diagnostics",
            subtitle: "Open Capso's local log folder",
            keywords: ["log folder", "finder", "log files"]
        ),
        SettingSearchItem(
            id: "general-crash-reports",
            tab: .general,
            title: "Crash Reports",
            section: "Diagnostics",
            subtitle: "Open macOS DiagnosticReports",
            keywords: ["crash", "panic", "diagnostic reports"]
        ),
        SettingSearchItem(
            id: "general-about",
            tab: .general,
            title: "About Capso",
            section: "About",
            subtitle: "Version, Report a Bug, Request a Feature, GitHub",
            keywords: ["version", "build", "report bug", "feature request", "github", "source code", "x.com", "twitter"]
        ),

        // MARK: - Permissions
        SettingSearchItem(
            id: "permissions-tab",
            tab: .permissions,
            title: "Permissions",
            section: "Privacy & Security",
            keywords: ["privacy", "security", "tcc", "access", "system settings"]
        ),
        SettingSearchItem(
            id: "permissions-screen-recording",
            tab: .permissions,
            title: "Screen Recording Permission",
            section: "Privacy & Security",
            subtitle: "Required for screenshots and recording",
            keywords: ["screen capture", "record screen", "capture display", "permission"]
        ),
        SettingSearchItem(
            id: "permissions-accessibility",
            tab: .permissions,
            title: "Accessibility Permission",
            section: "Privacy & Security",
            subtitle: "Required for selected text translation",
            keywords: ["selected text", "accessibility access", "auxiliary"]
        ),
        SettingSearchItem(
            id: "permissions-input-monitoring",
            tab: .permissions,
            title: "Input Monitoring Permission",
            section: "Privacy & Security",
            subtitle: "Required to show key presses while recording",
            keywords: ["keystroke", "keycastr", "keys", "keyboard monitoring"]
        ),
        SettingSearchItem(
            id: "permissions-camera",
            tab: .permissions,
            title: "Camera Permission",
            section: "Privacy & Security",
            subtitle: "Required for camera overlay",
            keywords: ["webcam", "facetime", "pip camera", "camera access"]
        ),
        SettingSearchItem(
            id: "permissions-microphone",
            tab: .permissions,
            title: "Microphone Permission",
            section: "Privacy & Security",
            subtitle: "Required for microphone recording",
            keywords: ["mic", "audio input", "voice recording", "sound recording", "microphone access"]
        ),

        // MARK: - Screenshots
        SettingSearchItem(
            id: "screenshots-tab",
            tab: .screenshots,
            title: "Screenshots",
            section: "Screenshots",
            keywords: ["screen capture", "snip", "snapshot", "image capture"]
        ),
        SettingSearchItem(
            id: "screenshots-show-preview",
            tab: .screenshots,
            title: "Show Preview",
            section: "After Capture",
            subtitle: "Display thumbnail with quick actions",
            keywords: ["thumbnail", "floating preview", "quick access", "popup"]
        ),
        SettingSearchItem(
            id: "screenshots-copy-clipboard",
            tab: .screenshots,
            title: "Copy to Clipboard",
            section: "After Capture",
            subtitle: "Copy screenshot immediately",
            keywords: ["clipboard", "paste", "auto copy"]
        ),
        SettingSearchItem(
            id: "screenshots-clipboard-content",
            tab: .screenshots,
            title: "Clipboard Content",
            section: "After Capture",
            subtitle: "Image or file path",
            keywords: ["paste image", "paste path", "file path"]
        ),
        SettingSearchItem(
            id: "screenshots-clipboard-format",
            tab: .screenshots,
            title: "Clipboard Format",
            section: "After Capture",
            subtitle: "PNG, JPEG, TIFF",
            keywords: ["format", "png", "jpeg", "tiff", "lossless"]
        ),
        SettingSearchItem(
            id: "screenshots-auto-save",
            tab: .screenshots,
            title: "Auto Save",
            section: "After Capture",
            subtitle: "Save to file automatically",
            keywords: ["save screenshot", "auto save", "disk"]
        ),
        SettingSearchItem(
            id: "screenshots-show-cursor",
            tab: .screenshots,
            title: "Show Cursor in Screenshots",
            section: "Capture",
            subtitle: "Include the mouse pointer in screenshots",
            keywords: ["mouse", "pointer", "cursor", "arrow"]
        ),
        SettingSearchItem(
            id: "screenshots-window-shadow",
            tab: .screenshots,
            title: "Capture Window Shadow",
            section: "Capture",
            subtitle: "Include shadow in window captures",
            keywords: ["window shadow", "border", "transparent shadow"]
        ),
        SettingSearchItem(
            id: "screenshots-add-timestamp",
            tab: .screenshots,
            title: "Add Timestamp",
            section: "Timestamp",
            subtitle: "Draw the capture time onto screenshots",
            keywords: ["time", "date", "watermark", "overlay timestamp", "clock"]
        ),
        SettingSearchItem(
            id: "screenshots-timestamp-customization",
            tab: .screenshots,
            title: "Timestamp Position, Format & Style",
            section: "Timestamp",
            subtitle: "Customize position, date format, font size, and color",
            keywords: ["font size", "color hex", "format", "bottom right", "top left"]
        ),
        SettingSearchItem(
            id: "screenshots-beautify",
            tab: .screenshots,
            title: "Beautify Every Screenshot",
            section: "Beautify",
            subtitle: "Uses background, padding, corners and shadow from editor",
            keywords: ["background", "padding", "rounded corners", "shadow", "canvas", "beautify", "card"]
        ),
        SettingSearchItem(
            id: "screenshots-self-timer-duration",
            tab: .screenshots,
            title: "Self-Timer Duration",
            section: "Self-Timer",
            subtitle: "Delay before the screenshot fires",
            keywords: ["delay", "timer", "seconds", "countdown", "delayed screenshot"]
        ),
        SettingSearchItem(
            id: "screenshots-self-timer-tick",
            tab: .screenshots,
            title: "Self-Timer Tick Sound",
            section: "Self-Timer",
            subtitle: "Play a sound on each second of the countdown",
            keywords: ["sound", "tick", "beep", "countdown audio"]
        ),
        SettingSearchItem(
            id: "screenshots-capture-presets",
            tab: .screenshots,
            title: "Capture Presets",
            section: "Capture Presets",
            subtitle: "Constrain area capture to aspect ratios or fixed sizes",
            keywords: ["aspect ratio", "16:9", "4:3", "1:1", "fixed size", "presets", "dimensions", "resolution"]
        ),

        // MARK: - Recording
        SettingSearchItem(
            id: "recording-tab",
            tab: .recording,
            title: "Recording",
            section: "Recording",
            keywords: ["screen recording", "video", "screen record", "screencast", "movie"]
        ),
        SettingSearchItem(
            id: "recording-show-cursor",
            tab: .recording,
            title: "Show Cursor in Recording",
            section: "Cursor",
            keywords: ["mouse", "pointer", "cursor", "arrow"]
        ),
        SettingSearchItem(
            id: "recording-highlight-clicks",
            tab: .recording,
            title: "Highlight Clicks",
            section: "Cursor",
            subtitle: "Radial pulse on mouse click",
            keywords: ["click effect", "mouse click", "pulse", "rings", "highlight"]
        ),
        SettingSearchItem(
            id: "recording-show-key-presses",
            tab: .recording,
            title: "Show Key Presses",
            section: "Cursor",
            subtitle: "KeyCastr-style overlay of keys while recording",
            keywords: ["keycastr", "keystroke overlay", "hotkeys on screen", "typing", "input monitoring"]
        ),
        SettingSearchItem(
            id: "recording-show-countdown",
            tab: .recording,
            title: "Show Countdown",
            section: "Behavior",
            subtitle: "3-second countdown before recording",
            keywords: ["countdown", "delay", "3 seconds", "timer"]
        ),
        SettingSearchItem(
            id: "recording-hide-desktop-icons",
            tab: .recording,
            title: "Hide Desktop Icons",
            section: "Behavior",
            subtitle: "Cover desktop icons with the wallpaper while recording",
            keywords: ["clean desktop", "hide icons", "wallpaper", "desktop wallpaper"]
        ),
        SettingSearchItem(
            id: "recording-open-editor",
            tab: .recording,
            title: "Open Editor After Recording",
            section: "Behavior",
            subtitle: "Edit, trim, and add effects before exporting",
            keywords: ["trim", "video editor", "cut", "effects", "post production"]
        ),
        SettingSearchItem(
            id: "recording-copy-clipboard",
            tab: .recording,
            title: "Copy Recording to Clipboard",
            section: "Behavior",
            subtitle: "Copy the finished recording as an MP4 or GIF file",
            keywords: ["clipboard", "auto copy video", "gif copy", "mp4"]
        ),
        SettingSearchItem(
            id: "recording-remember-area",
            tab: .recording,
            title: "Remember Last Recording Area",
            section: "Behavior",
            keywords: ["previous area", "last bounds", "same area"]
        ),
        SettingSearchItem(
            id: "recording-camera-fade",
            tab: .recording,
            title: "Camera PiP Fade on Hover",
            section: "Camera PiP",
            subtitle: "Nearly transparent on hover so you can see behind it",
            keywords: ["webcam", "camera opacity", "fade", "hover", "transparent"]
        ),
        SettingSearchItem(
            id: "recording-camera-click-through",
            tab: .recording,
            title: "Click Through PiP",
            section: "Camera PiP",
            subtitle: "Clicks pass through to whatever is behind camera view",
            keywords: ["pass through", "click through", "webcam overlay", "click behind"]
        ),

        // MARK: - Quick Access
        SettingSearchItem(
            id: "quickaccess-tab",
            tab: .quickAccess,
            title: "Quick Access",
            section: "Quick Access",
            keywords: ["floating thumbnail", "preview overlay", "snip overlay", "floating window"]
        ),
        SettingSearchItem(
            id: "quickaccess-position",
            tab: .quickAccess,
            title: "Preview Position",
            section: "Position",
            subtitle: "Bottom Left, Center, Bottom Right",
            keywords: ["corner", "placement", "bottom left", "bottom right", "center screen", "where preview appears"]
        ),
        SettingSearchItem(
            id: "quickaccess-auto-close",
            tab: .quickAccess,
            title: "Auto-Close Preview",
            section: "Auto-Close",
            subtitle: "Dismiss preview after timeout (5s, 10s, 15s, 30s)",
            keywords: ["timeout", "duration", "auto dismiss", "close timer", "close after"]
        ),
        SettingSearchItem(
            id: "quickaccess-close-after-drag",
            tab: .quickAccess,
            title: "Close After Dragging",
            section: "Auto-Close",
            subtitle: "Close the preview once it's dropped into another app",
            keywords: ["drag and drop", "drop", "dismiss on drag"]
        ),

        // MARK: - Cloud Share
        SettingSearchItem(
            id: "cloudshare-tab",
            tab: .cloudShare,
            title: "Cloud Share",
            section: "Cloud Share",
            keywords: ["upload", "cloud storage", "share link", "s3", "r2", "supabase", "bucket", "hosting"]
        ),
        SettingSearchItem(
            id: "cloudshare-provider",
            tab: .cloudShare,
            title: "Cloud Storage Provider",
            section: "Provider",
            subtitle: "AWS S3, Cloudflare R2, Supabase, MinIO, Custom S3",
            keywords: ["amazon s3", "cloudflare r2", "supabase", "bucket", "endpoint", "credentials", "access key", "secret key"]
        ),
        SettingSearchItem(
            id: "cloudshare-auto-upload",
            tab: .cloudShare,
            title: "Automatic Uploads",
            section: "Upload",
            subtitle: "Upload every capture and copy share link to clipboard",
            keywords: ["auto upload", "share link", "public url", "automatic share"]
        ),

        // MARK: - Export
        SettingSearchItem(
            id: "export-tab",
            tab: .export,
            title: "Export",
            section: "Export",
            keywords: ["save", "output", "format", "destination", "folder", "naming"]
        ),
        SettingSearchItem(
            id: "export-quality",
            tab: .export,
            title: "Export Quality",
            section: "Quality",
            subtitle: "Maximum, Social, Web (for video and GIF exports)",
            keywords: ["bitrate", "resolution", "video quality", "gif quality", "compression"]
        ),
        SettingSearchItem(
            id: "export-screenshot-format",
            tab: .export,
            title: "Screenshot Format",
            section: "Quality",
            subtitle: "PNG, JPEG, HEIC",
            keywords: ["file format", "png", "heic", "jpeg", "lossless", "smallest file"]
        ),
        SettingSearchItem(
            id: "export-screenshot-quality",
            tab: .export,
            title: "Screenshot Quality",
            section: "Quality",
            subtitle: "Quality percent for lossy formats",
            keywords: ["lossy quality", "compression percent", "image quality"]
        ),
        SettingSearchItem(
            id: "export-location",
            tab: .export,
            title: "Export Location",
            section: "Save Location",
            subtitle: "Default folder where files are saved",
            keywords: ["folder", "directory", "save to", "desktop", "downloads", "path", "choose folder"]
        ),
        SettingSearchItem(
            id: "export-monthly-folders",
            tab: .export,
            title: "Monthly Screenshot Folders",
            section: "Save Location",
            subtitle: "Save screenshots into yyyy-MM subfolders",
            keywords: ["subfolder", "date folder", "organization", "year month", "monthly"]
        ),
        SettingSearchItem(
            id: "export-filename-template",
            tab: .export,
            title: "Filename Template",
            section: "Save Location",
            subtitle: "Custom filename pattern with tokens",
            keywords: ["file naming", "tokens", "pattern", "timestamp", "name template", "filename format"]
        ),
        SettingSearchItem(
            id: "export-opened-images",
            tab: .export,
            title: "When Saving an Opened Image",
            section: "Opened Images",
            subtitle: "Ask Every Time, Overwrite Original, Save Next to Original",
            keywords: ["overwrite", "save behavior", "save copy", "opened image"]
        ),

        // MARK: - Text & Translation
        SettingSearchItem(
            id: "ocr-tab",
            tab: .ocr,
            title: "Text & Translation",
            section: "Text & Translation",
            keywords: ["ocr", "optical character recognition", "translate", "languages", "extract text"]
        ),
        SettingSearchItem(
            id: "ocr-line-breaks",
            tab: .ocr,
            title: "Keep Line Breaks",
            section: "Text Recognition",
            subtitle: "Preserve original line structure in recognized text",
            keywords: ["line breaks", "formatting", "ocr lines", "newline"]
        ),
        SettingSearchItem(
            id: "ocr-detect-links",
            tab: .ocr,
            title: "Detect Links",
            section: "Text Recognition",
            subtitle: "Auto-detect and linkify URLs in recognized text",
            keywords: ["url detection", "clickable links", "linkify", "hyperlink"]
        ),
        SettingSearchItem(
            id: "ocr-target-language",
            tab: .ocr,
            title: "Target Language",
            section: "Translation",
            subtitle: "Language to translate text into",
            keywords: ["destination language", "translate language", "english", "chinese", "spanish", "japanese", "french", "german"]
        ),
        SettingSearchItem(
            id: "ocr-provider",
            tab: .ocr,
            title: "Translation Provider",
            section: "Translation",
            subtitle: "Apple Translate, DeepL, OpenAI, Google, Ollama",
            keywords: ["deepl", "openai", "chatgpt", "google translate", "offline translation", "local ai", "ollama", "provider"]
        ),
        SettingSearchItem(
            id: "ocr-api-key",
            tab: .ocr,
            title: "Translation API Key",
            section: "Translation",
            subtitle: "Stored securely in Keychain",
            keywords: ["api token", "secret key", "keychain", "api key"]
        ),
        SettingSearchItem(
            id: "ocr-endpoint-model",
            tab: .ocr,
            title: "Translation Endpoint & Model",
            section: "Translation",
            subtitle: "Custom base URL endpoint and model name",
            keywords: ["custom model", "base url", "endpoint", "llm model"]
        ),

        // MARK: - Shortcuts
        SettingSearchItem(
            id: "shortcuts-tab",
            tab: .shortcuts,
            title: "Shortcuts",
            section: "Shortcuts",
            keywords: ["hotkeys", "key bindings", "keyboard shortcuts", "commands", "keys"]
        ),
        SettingSearchItem(
            id: "shortcuts-all-in-one",
            tab: .shortcuts,
            title: "All-in-One Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Default: ⇧⌘1",
            keywords: ["capture all-in-one", "main shortcut", "cmd shift 1", "default shortcut"]
        ),
        SettingSearchItem(
            id: "shortcuts-capture-area",
            tab: .shortcuts,
            title: "Capture Area Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Select region to screenshot",
            keywords: ["area capture", "selection screenshot", "region", "snip area"]
        ),
        SettingSearchItem(
            id: "shortcuts-capture-fullscreen",
            tab: .shortcuts,
            title: "Capture Fullscreen Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Capture entire screen",
            keywords: ["fullscreen screenshot", "full screen", "entire display"]
        ),
        SettingSearchItem(
            id: "shortcuts-capture-window",
            tab: .shortcuts,
            title: "Capture Window Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Capture a single application window",
            keywords: ["window capture", "window shot", "single window"]
        ),
        SettingSearchItem(
            id: "shortcuts-capture-text",
            tab: .shortcuts,
            title: "Capture Text (OCR) Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Extract text from screen region",
            keywords: ["ocr shortcut", "copy text from image", "extract text", "snip text"]
        ),
        SettingSearchItem(
            id: "shortcuts-scrolling-capture",
            tab: .shortcuts,
            title: "Scrolling Capture Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Capture long scrollable page or window",
            keywords: ["long screenshot", "scrollable", "webpage capture", "scrolling"]
        ),
        SettingSearchItem(
            id: "shortcuts-self-timer",
            tab: .shortcuts,
            title: "Self-Timer Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Delayed screenshot",
            keywords: ["timer capture", "delayed screenshot", "countdown capture"]
        ),
        SettingSearchItem(
            id: "shortcuts-area-to-clipboard",
            tab: .shortcuts,
            title: "Capture Area to Clipboard Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Snip directly to clipboard",
            keywords: ["quick copy", "clipboard area", "snip to clipboard"]
        ),
        SettingSearchItem(
            id: "shortcuts-area-and-share",
            tab: .shortcuts,
            title: "Capture and Share to Cloud Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Snip and upload immediately",
            keywords: ["cloud share shortcut", "upload snip", "share link shortcut"]
        ),
        SettingSearchItem(
            id: "shortcuts-area-and-annotate",
            tab: .shortcuts,
            title: "Capture Area & Annotate Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Snip and open immediately in editor",
            keywords: ["annotate shortcut", "edit snip", "draw on screenshot", "editor"]
        ),
        SettingSearchItem(
            id: "shortcuts-area-and-pin",
            tab: .shortcuts,
            title: "Capture Area & Pin Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Snip and float on screen as pin",
            keywords: ["pin area", "float screenshot", "sticky note", "pin to screen"]
        ),
        SettingSearchItem(
            id: "shortcuts-pin-clipboard",
            tab: .shortcuts,
            title: "Pin from Clipboard Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Float copied image, text, or file",
            keywords: ["clipboard pin", "paste as pin", "float clipboard"]
        ),
        SettingSearchItem(
            id: "shortcuts-edit-clipboard",
            tab: .shortcuts,
            title: "Edit Clipboard Image Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Open clipboard image in Annotate",
            keywords: ["edit clipboard", "open in editor", "annotate clipboard"]
        ),
        SettingSearchItem(
            id: "shortcuts-toggle-pins",
            tab: .shortcuts,
            title: "Hide / Show All Pins Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Toggle visibility of floating pins",
            keywords: ["toggle pins", "hide pins", "show pins", "minimize pins"]
        ),
        SettingSearchItem(
            id: "shortcuts-capture-and-translate",
            tab: .shortcuts,
            title: "Capture & Translate Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "OCR and translate screen area",
            keywords: ["translate capture", "screen translator", "ocr translate"]
        ),
        SettingSearchItem(
            id: "shortcuts-translate-selected-text",
            tab: .shortcuts,
            title: "Translate Selected Text Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Translate text currently highlighted in any app",
            keywords: ["selected text", "instant translate", "highlight translate"]
        ),
        SettingSearchItem(
            id: "shortcuts-translate-typed-text",
            tab: .shortcuts,
            title: "Translate Typed Text Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Open quick translate input box",
            keywords: ["type to translate", "translate box", "quick translate"]
        ),
        SettingSearchItem(
            id: "shortcuts-capture-last-area",
            tab: .shortcuts,
            title: "Capture Previous Area Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Recapture the exact same area again",
            keywords: ["repeat capture", "last area", "same bounds", "previous area"]
        ),
        SettingSearchItem(
            id: "shortcuts-record-area",
            tab: .shortcuts,
            title: "Record Area Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Default: ⇧⌘2",
            keywords: ["screen recording shortcut", "video area", "cmd shift 2", "record video"]
        ),
        SettingSearchItem(
            id: "shortcuts-record-fullscreen",
            tab: .shortcuts,
            title: "Record Full Screen Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Record entire screen video",
            keywords: ["record fullscreen shortcut", "video full screen", "full screen recording"]
        ),
        SettingSearchItem(
            id: "shortcuts-screenshot-history",
            tab: .shortcuts,
            title: "Screenshot History Shortcut",
            section: "Customizable Shortcuts",
            subtitle: "Open recent captures gallery",
            keywords: ["history shortcut", "recent screenshots", "gallery"]
        ),
        SettingSearchItem(
            id: "shortcuts-center-lock",
            tab: .shortcuts,
            title: "Center 1:1 from Click",
            section: "Contextual Shortcuts",
            subtitle: "Hold Shift + extra key (default: C)",
            keywords: ["square lock", "center lock", "shift c", "aspect ratio lock", "centered square"]
        ),
        SettingSearchItem(
            id: "shortcuts-contextual-actions",
            tab: .shortcuts,
            title: "Contextual Shortcuts (Copy, Save, Pin, Esc)",
            section: "Contextual Shortcuts",
            subtitle: "⌘C, ⏎, ⌘S, ⌘P, Esc in All-in-One",
            keywords: ["contextual", "copy", "save", "pin", "cancel", "esc", "return", "enter"]
        )
    ]
}
