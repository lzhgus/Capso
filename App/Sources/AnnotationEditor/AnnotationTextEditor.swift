// App/Sources/AnnotationEditor/AnnotationTextEditor.swift
import AppKit

@MainActor
protocol AnnotationTextEditorDelegate: AnyObject {
    func textEditor(_ editor: AnnotationTextEditor, didCommitText text: String)
}

@MainActor
final class AnnotationTextEditor: NSScrollView {
    private static let liveGlyphTraceStrokeWidth: CGFloat = 2.0

    weak var editorDelegate: AnnotationTextEditorDelegate?

    var imageOrigin: CGPoint = .zero {
        didSet { updateFrameFromImageGeometry() }
    }
    var boxSize: CGSize = .zero {
        didSet { updateFrameFromImageGeometry() }
    }

    var zoomScale: CGFloat = 1.0 {
        didSet {
            guard zoomScale != oldValue else { return }
            applyAttributes()
            updateFrameFromImageGeometry()
        }
    }

    var fontSize: CGFloat = 48 {
        didSet {
            guard fontSize != oldValue else { return }
            applyAttributes()
        }
    }

    var fontName: String = ".AppleSystemUIFont" {
        didSet {
            guard fontName != oldValue else { return }
            applyAttributes()
        }
    }

    var textColor: NSColor = .red {
        didSet {
            guard textColor != oldValue else { return }
            applyAttributes()
        }
    }

    var fillColor: NSColor?
    var boxOutlineColor: NSColor?
    var glyphStrokeColor: NSColor? {
        didSet {
            applyAttributes()
            invalidateCanvasTrace()
        }
    }

    var text: String { textView.string }
    var viewBoxFrame: CGRect { frame }

    private let textView: InlineTextView
    private let textInset: CGFloat = 4
    private var manuallySizedWidth = false
    private var hasBegunEditing = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        self.textView = InlineTextView(frame: .zero)
        super.init(frame: frameRect)

        configureScrollView()
        configureTextView()
        documentView = textView

        textView.commitHandler = { [weak self] in
            guard let self else { return }
            self.editorDelegate?.textEditor(self, didCommitText: self.textView.string)
        }
        textView.sizeChangeHandler = { [weak self] in
            self?.resizeToFit()
            self?.invalidateCanvasTrace()
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func configureScrollView() {
        hasVerticalScroller = false
        hasHorizontalScroller = false
        autohidesScrollers = true
        drawsBackground = false
        borderType = .noBorder
        contentView.drawsBackground = false
        wantsLayer = true
        layer?.masksToBounds = true
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = true
    }

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

        textView.textContainerInset = NSSize(width: textInset, height: textInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.insertionPointColor = .white
    }

    func beginEditing(initialText: String) {
        hasBegunEditing = true
        textView.string = initialText
        if boxSize == .zero {
            boxSize = defaultBoxSize()
        }
        applyAttributes()
        let len = (textView.string as NSString).length
        textView.setSelectedRange(initialText.isEmpty ? NSRange(location: 0, length: 0) : NSRange(location: 0, length: len))
        resizeToFit()
    }

    func focusTextView() {
        window?.makeFirstResponder(textView)
    }

    func containsCanvasPoint(_ pointInCanvas: CGPoint) -> Bool {
        frame.contains(pointInCanvas)
    }

    func resizeBox(to rect: CGRect) {
        manuallySizedWidth = true
        imageOrigin = rect.origin
        boxSize = rect.size
        layoutTextView()
        invalidateCanvasTrace()
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let effective = max(1, fontSize * zoomScale)
        let font = NSFont(name: fontName, size: effective)
            ?? NSFont.systemFont(ofSize: effective, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        return attrs
    }

    func drawGlyphTraceBehindText() {
        guard let glyphStrokeColor, !text.isEmpty else { return }
        let effective = max(1, fontSize * zoomScale)
        let font = NSFont(name: fontName, size: effective)
            ?? NSFont.systemFont(ofSize: effective, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.clear,
            .strokeColor: glyphStrokeColor,
            .strokeWidth: Self.liveGlyphTraceStrokeWidth,
        ]
        (text as NSString).draw(
            with: frame.insetBy(dx: textInset, dy: textInset),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
    }

    private func applyAttributes() {
        textView.typingAttributes = attributes
        if let storage = textView.textStorage, storage.length > 0 {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
        if hasBegunEditing {
            resizeToFit()
        }
    }

    private func defaultBoxSize() -> CGSize {
        CGSize(width: min(220, maxAutoWidth()), height: max(28, fontSize + 12))
    }

    private func minBoxSize() -> CGSize {
        CGSize(width: 60, height: max(28, fontSize + 12))
    }

    private func maxAutoWidth() -> CGFloat {
        guard let superview else { return 420 }
        let remaining = (superview.bounds.width - imageOrigin.x * zoomScale - 12) / max(zoomScale, 0.1)
        return max(minBoxSize().width, remaining)
    }

    private func resizeToFit() {
        guard hasBegunEditing, let storage = textView.textStorage else { return }

        let minSize = minBoxSize()
        let naturalWidth = naturalTextWidth(storage: storage)
        let targetWidth: CGFloat
        if manuallySizedWidth {
            targetWidth = max(minSize.width, boxSize.width)
        } else {
            targetWidth = min(maxAutoWidth(), max(minSize.width, naturalWidth))
        }

        let measuredHeight = measuredTextHeight(storage: storage, width: targetWidth)
        boxSize = CGSize(width: targetWidth, height: max(minSize.height, measuredHeight))
        layoutTextView()
    }

    private func naturalTextWidth(storage: NSTextStorage) -> CGFloat {
        guard storage.length > 0 else { return boxSize == .zero ? defaultBoxSize().width : boxSize.width }
        let scale = max(zoomScale, 0.1)
        let rect = storage.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.width / scale) + (textInset * 2 + 2) / scale
    }

    private func measuredTextHeight(storage: NSTextStorage, width: CGFloat) -> CGFloat {
        let scale = max(zoomScale, 0.1)
        guard storage.length > 0 else { return fontSize + textInset * 2 / scale }
        let contentWidth = max(1, width * scale - textInset * 2)
        let rect = storage.boundingRect(
            with: NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height / scale) + (textInset * 2) / scale
    }

    private func updateFrameFromImageGeometry() {
        guard boxSize.width > 0, boxSize.height > 0 else { return }
        let scale = max(zoomScale, 0.1)
        frame = CGRect(
            x: imageOrigin.x * scale,
            y: imageOrigin.y * scale,
            width: boxSize.width * scale,
            height: boxSize.height * scale
        )
        layoutTextView()
        invalidateCanvasTrace()
    }

    private func layoutTextView() {
        textView.frame = CGRect(origin: .zero, size: bounds.size)
        textView.textContainer?.containerSize = NSSize(
            width: max(1, bounds.width - textInset * 2),
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    private func invalidateCanvasTrace() {
        superview?.needsDisplay = true
    }
}

@MainActor
private final class InlineTextView: NSTextView {
    var commitHandler: (() -> Void)?
    var sizeChangeHandler: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }
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
