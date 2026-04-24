// App/Sources/AnnotationEditor/Crop/CropEditorView.swift
import SwiftUI
import AnnotationKit

struct CropEditorView: View {
    let sourceImage: CGImage
    let initialCropRect: CGRect?
    /// True when the document already has annotations. Rotate and flip are
    /// disabled in that case to avoid orphaning annotations whose coordinates
    /// assume the pre-transform image space.
    let canTransformImage: Bool
    let onCancel: () -> Void
    /// Receives the (possibly transformed) image and the committed crop rect.
    /// `image` is nil if no rotate/flip was applied (caller keeps its existing
    /// source image). `cropRect` is nil when the rect covers the full image.
    let onCommit: (_ image: CGImage?, _ cropRect: CGRect?) -> Void

    /// The live preview image. Starts equal to `sourceImage` and accumulates
    /// rotate/flip transforms on user action. Never mutated by Cancel.
    @State private var displayImage: CGImage
    @State private var cropRect: CGRect
    /// Persist the most recently chosen ratio preset across editor sessions.
    @AppStorage("annotationLastCropPreset") private var preset: CropPreset = .freeform
    @AppStorage("annotationCropSnapEnabled") private var snapEnabled: Bool = true
    @State private var zoomScale: CGFloat = 1.0
    /// Non-nil when a user-defined ratio is the active constraint; its
    /// aspect overrides `preset.ratio(imageSize:)`. Cleared when the user
    /// selects a built-in preset from the menu. Not persisted.
    @State private var selectedCustom: CustomCropRatio?

    /// Undo/redo stacks for modal-local edits. Each snapshot captures both
    /// `cropRect` and `preset` so reverting feels like undoing a gesture.
    @State private var undoStack: [(CGRect, CropPreset)] = []
    @State private var redoStack: [(CGRect, CropPreset)] = []
    /// True while we're programmatically restoring a snapshot. Prevents
    /// `onChange(of: preset)` from both re-recording the restore AND
    /// running `applyPresetRatio` which would mutate cropRect.
    @State private var isApplyingHistory = false

    /// `true` once the user has applied a rotate or flip. Drives the commit
    /// callback so the caller knows to swap its source image.
    @State private var didTransformImage: Bool = false

    init(
        sourceImage: CGImage,
        initialCropRect: CGRect?,
        canTransformImage: Bool,
        onCancel: @escaping () -> Void,
        onCommit: @escaping (_ image: CGImage?, _ cropRect: CGRect?) -> Void
    ) {
        self.sourceImage = sourceImage
        self.initialCropRect = initialCropRect
        self.canTransformImage = canTransformImage
        self.onCancel = onCancel
        self.onCommit = onCommit
        let size = CGSize(width: sourceImage.width, height: sourceImage.height)
        self._displayImage = State(initialValue: sourceImage)
        self._cropRect = State(initialValue: initialCropRect ?? CGRect(origin: .zero, size: size))
    }

    private var imageSize: CGSize {
        CGSize(width: displayImage.width, height: displayImage.height)
    }

    private var isIdentityCrop: Bool {
        abs(cropRect.origin.x) < 0.5 &&
        abs(cropRect.origin.y) < 0.5 &&
        abs(cropRect.width - imageSize.width) < 0.5 &&
        abs(cropRect.height - imageSize.height) < 0.5
    }

    /// Effective aspect ratio for the currently-selected constraint.
    /// Custom ratios win when active; otherwise fall back to the built-in preset.
    private var activeAspectRatio: CGFloat? {
        selectedCustom?.ratio ?? preset.ratio(imageSize: imageSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            CropToolbar(
                preset: $preset,
                selectedCustom: $selectedCustom,
                cropRect: $cropRect,
                imageSize: imageSize,
                canTransformImage: canTransformImage,
                onRotateCCW: rotateCCW,
                onFlipH: flipHorizontal,
                onCancel: onCancel,
                onCommit: {
                    onCommit(
                        didTransformImage ? displayImage : nil,
                        isIdentityCrop ? nil : cropRect
                    )
                }
            )
            Divider()

            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        Image(decorative: displayImage, scale: 1.0)
                            .resizable()
                            .frame(
                                width: imageSize.width * zoomScale,
                                height: imageSize.height * zoomScale
                            )
                        CropAreaView(
                            cropRect: $cropRect,
                            imageSize: imageSize,
                            zoomScale: zoomScale,
                            aspectRatio: activeAspectRatio,
                            snapEnabled: snapEnabled,
                            onDragEnded: { oldRect in
                                pushHistory(rect: oldRect, preset: preset)
                            }
                        )
                        .frame(
                            width: imageSize.width * zoomScale,
                            height: imageSize.height * zoomScale
                        )
                    }
                    .frame(
                        width: imageSize.width * zoomScale,
                        height: imageSize.height * zoomScale
                    )
                }
                .background(Color(white: 0.12))
                .onAppear { fitToWindow(available: geo.size) }
                .onChange(of: geo.size) { _, newSize in
                    fitToWindow(available: newSize)
                }
                .onChange(of: preset) { oldPreset, newPreset in
                    guard !isApplyingHistory else { return }
                    pushHistory(rect: cropRect, preset: oldPreset)
                    applyRatio(newPreset.ratio(imageSize: imageSize))
                }
                .onChange(of: selectedCustom) { _, newCustom in
                    guard !isApplyingHistory else { return }
                    if let newCustom { applyRatio(newCustom.ratio) }
                }
            }

            Divider()
            bottomBar
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: ["r"]) { press in
            cyclePreset(forward: !press.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(keys: ["1", "2", "3", "4", "5", "6"]) { press in
            selectPreset(byDigit: press.characters)
            return .handled
        }
        .onKeyPress(keys: ["z"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.modifiers.contains(.shift) {
                redo(); return .handled
            }
            undo(); return .handled
        }
    }

    private func pushHistory(rect: CGRect, preset: CropPreset) {
        undoStack.append((rect, preset))
        redoStack.removeAll()
    }

    private func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append((cropRect, preset))
        isApplyingHistory = true
        cropRect = snapshot.0
        preset = snapshot.1
        DispatchQueue.main.async { isApplyingHistory = false }
    }

    private func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append((cropRect, preset))
        isApplyingHistory = true
        cropRect = snapshot.0
        preset = snapshot.1
        DispatchQueue.main.async { isApplyingHistory = false }
    }

    private func cyclePreset(forward: Bool) {
        let cases = CropPreset.allCases
        guard let idx = cases.firstIndex(of: preset) else { return }
        let next = forward
            ? (idx + 1) % cases.count
            : (idx - 1 + cases.count) % cases.count
        preset = cases[next]
    }

    private func selectPreset(byDigit digit: String) {
        guard let n = Int(digit), (1...CropPreset.allCases.count).contains(n) else { return }
        preset = CropPreset.allCases[n - 1]
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text("\(Int(zoomScale * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44)

            Toggle("Snap handles to image edges", isOn: $snapEnabled)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("When dragging a crop handle near the image boundary, snap it exactly to that edge. Hold ⌘ while dragging to temporarily disable.")
            Text("Hold ⌘ while dragging to disable temporarily.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if !isIdentityCrop {
                Button("Revert to Original") {
                    cropRect = CGRect(origin: .zero, size: imageSize)
                    preset = .freeform
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func rotateCCW() {
        guard let newImage = ImageTransforms.rotate90CCW(displayImage) else { return }
        let oldSize = imageSize
        displayImage = newImage
        cropRect = RectTransforms.rotate90CCW(cropRect, in: oldSize)
        didTransformImage = true
        selectedCustom = nil
        // History is not tracked across transforms in v1: undo after a rotate
        // would need to also roll back the displayImage, not just the rect.
        undoStack.removeAll()
        redoStack.removeAll()
    }

    private func flipHorizontal() {
        guard let newImage = ImageTransforms.flipHorizontal(displayImage) else { return }
        displayImage = newImage
        cropRect = RectTransforms.flipHorizontal(cropRect, in: imageSize)
        didTransformImage = true
        selectedCustom = nil
        undoStack.removeAll()
        redoStack.removeAll()
    }

    private func fitToWindow(available: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let toolbarH: CGFloat = 80
        let availW = available.width - 24
        let availH = available.height - toolbarH
        let scaleX = availW / imageSize.width
        let scaleY = availH / imageSize.height
        zoomScale = min(scaleX, scaleY, 1.0)
    }

    /// Re-fit the current crop rect to enforce a new aspect ratio, keeping
    /// the center fixed and clamping to the image bounds. Called when either
    /// the built-in preset or the active custom ratio changes.
    private func applyRatio(_ ratio: CGFloat?) {
        guard let ratio else { return }
        let center = CGPoint(x: cropRect.midX, y: cropRect.midY)
        let currentRatio = cropRect.width / max(cropRect.height, 1)
        var newW = cropRect.width
        var newH = cropRect.height
        if currentRatio > ratio {
            newW = cropRect.height * ratio
        } else {
            newH = cropRect.width / ratio
        }
        var newRect = CGRect(x: center.x - newW / 2, y: center.y - newH / 2, width: newW, height: newH)
        if newRect.minX < 0 { newRect.origin.x = 0 }
        if newRect.minY < 0 { newRect.origin.y = 0 }
        if newRect.maxX > imageSize.width { newRect.origin.x = imageSize.width - newRect.width }
        if newRect.maxY > imageSize.height { newRect.origin.y = imageSize.height - newRect.height }
        cropRect = newRect
    }
}
