// App/Sources/AnnotationEditor/AnnotationTextEditor.swift
//
// Inline, in-canvas text editor that replaces the modal NSAlert popup the
// annotation text tool used before. Appears at the click point, grows with
// content, commits on **Esc or outside-click** (no Return-commit — Return and
// Shift+Return both insert newlines, matching CleanShot X). IME composition
// is respected so Chinese / Japanese / Korean users can confirm candidates
// with Return without committing the whole edit.
//
// Visual language: refined native macOS — a hairline accent-tinted rounded
// outline and a soft dark backdrop. Intentionally quieter than CleanShot X,
// so it never fights the content being annotated.

import AppKit

@MainActor
protocol AnnotationTextEditorDelegate: AnyObject {
    /// Called when the user commits the edit (Return / Esc / outside-click).
    /// `text` may be empty — the canvas decides whether to discard or delete.
    func textEditor(_ editor: AnnotationTextEditor, didCommitText text: String)
}

@MainActor
final class AnnotationTextEditor: NSView {
    weak var delegate: AnnotationTextEditorDelegate?

    /// Origin in **image coordinates**. The owning canvas multiplies by
    /// `zoomScale` to position us in its view space.
    var imageOrigin: CGPoint = .zero

    /// Zoom of the owning canvas. Controls the effective on-screen font size
    /// so typed glyphs line up 1:1 with what `TextObject.render` will draw.
    var zoomScale: CGFloat = 1.0 {
        didSet {
            guard zoomScale != oldValue else { return }
            applyAttributes()
        }
    }

    /// Font size in **image coordinates** (what gets stored on TextObject).
    var fontSize: CGFloat = 48 {
        didSet {
            guard fontSize != oldValue else { return }
            applyAttributes()
        }
    }

    /// Font name matches what TextObject uses when rendering.
    var fontName: String = ".AppleSystemUIFont" {
        didSet {
            guard fontName != oldValue else { return }
            applyAttributes()
        }
    }

    /// Text color with style.opacity already applied.
    var textColor: NSColor = .red {
        didSet {
            guard textColor != oldValue else { return }
            applyAttributes()
        }
    }

    /// String currently in the editor.
    var text: String { textView.string }

    private let textView: InlineTextView
    private let innerPadding: CGFloat = 4

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        self.textView = InlineTextView(frame: .zero)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        configureTextView()
        addSubview(textView)

        textView.commitHandler = { [weak self] in
            guard let self else { return }
            self.delegate?.textEditor(self, didCommitText: self.textView.string)
        }
        textView.sizeChangeHandler = { [weak self] in
            self?.resizeToFit()
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func configureTextView() {
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.isFieldEditor = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.importsGraphics = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.smartInsertDeleteEnabled = false

        // Unbounded container so multi-line grows horizontally with longest line.
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        // Make the caret visible on typical dark backgrounds.
        textView.insertionPointColor = .white
    }

    // MARK: - Lifecycle

    /// Seed the editor with `initialText`, apply current style, and select-all
    /// (so that typing replaces a double-click-restored string).
    func beginEditing(initialText: String) {
        textView.string = initialText
        applyAttributes()
        // Place caret at end (new text) or select all (existing text).
        let len = (textView.string as NSString).length
        if initialText.isEmpty {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        } else {
            textView.setSelectedRange(NSRange(location: 0, length: len))
        }
        resizeToFit()
    }

    /// Ask the window to make our text view first responder. Call after the
    /// view is installed in the window hierarchy.
    func focusTextView() {
        window?.makeFirstResponder(textView)
    }

    // MARK: - Attributes / layout

    private var attributes: [NSAttributedString.Key: Any] {
        let effective = max(1, fontSize * zoomScale)
        let font = NSFont(name: fontName, size: effective)
            ?? NSFont.systemFont(ofSize: effective, weight: .medium)
        return [
            .font: font,
            .foregroundColor: textColor,
        ]
    }

    private func applyAttributes() {
        textView.typingAttributes = attributes
        if let storage = textView.textStorage, storage.length > 0 {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
        resizeToFit()
    }

    private func resizeToFit() {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)

        // Reserve width for the caret so it doesn't clip on empty / trailing.
        let caretRoom = max(2, (fontSize * zoomScale) * 0.05)
        let minWidth = max(12, fontSize * zoomScale * 0.6)
        let contentW = max(minWidth, ceil(used.width) + caretRoom)
        let contentH = max(ceil(fontSize * zoomScale), ceil(used.height))

        let outerW = contentW + innerPadding * 2
        let outerH = contentH + innerPadding * 2

        if frame.size.width != outerW || frame.size.height != outerH {
            setFrameSize(NSSize(width: outerW, height: outerH))
        }
        textView.frame = NSRect(
            x: innerPadding, y: innerPadding,
            width: contentW, height: contentH
        )
        needsDisplay = true
    }

    // MARK: - Drawing: thin solid outline + soft backdrop

    override func draw(_ dirtyRect: NSRect) {
        let outline = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: outline, xRadius: 3, yRadius: 3)

        // Soft, nearly-invisible backdrop — just enough to keep light text legible
        // over messy backgrounds without visually competing with the capture.
        NSColor.black.withAlphaComponent(0.08).setFill()
        path.fill()

        // Thin accent outline, intentionally understated.
        NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: - Hit testing

    /// True if `pointInSelfSuperview` (the canvas's coordinate space) lands
    /// inside our frame. Used by the canvas to decide whether a click commits
    /// (outside) or falls through to the text view (inside).
    func containsCanvasPoint(_ pointInSelfSuperview: CGPoint) -> Bool {
        frame.contains(pointInSelfSuperview)
    }
}

// MARK: - Inline text view with commit-on-Return semantics

/// NSTextView subclass that commits on Esc and lets every other keystroke
/// (including Return and Shift+Return) fall through to the default multi-line
/// NSTextView behavior — which is to insert a newline. This mirrors the
/// behavior the user confirmed in CleanShot X: no keystroke commits; only
/// losing focus (Esc, or clicking outside the editor) finalizes the edit.
///
/// IME composition (`hasMarkedText()`) always bypasses interception so that
/// Return confirms a Chinese / Japanese / Korean candidate instead of acting
/// on the editor itself.
@MainActor
private final class InlineTextView: NSTextView {
    var commitHandler: (() -> Void)?
    var sizeChangeHandler: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // While IME has marked text, let the input manager handle everything.
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        // Escape (keyCode 53) commits. Everything else — including Return and
        // Shift+Return — falls through and gets the default newline-insertion
        // behavior for a multi-line NSTextView.
        if event.keyCode == 53 {
            commitHandler?()
            return
        }

        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        sizeChangeHandler?()
    }
}
