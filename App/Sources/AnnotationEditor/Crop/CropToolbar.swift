// App/Sources/AnnotationEditor/Crop/CropToolbar.swift
import SwiftUI
import AnnotationKit

struct CropToolbar: View {
    @Binding var preset: CropPreset
    @Binding var selectedCustom: CustomCropRatio?
    @Binding var cropRect: CGRect
    let imageSize: CGSize
    /// When false (e.g. document already has annotations), the rotate and flip
    /// buttons render disabled with an explanatory tooltip.
    let canTransformImage: Bool
    let onRotateCCW: () -> Void
    let onFlipH: () -> Void
    let onCancel: () -> Void
    let onCommit: () -> Void

    @AppStorage("annotationCustomCropRatios") private var customRatios: CustomCropRatioList = CustomCropRatioList(items: [])
    @State private var showAddCustom = false
    @State private var widthDraft: String = ""
    @State private var heightDraft: String = ""
    @FocusState private var focusedField: Field?

    private enum Field { case width, height }

    private var activeRatioLabel: String {
        selectedCustom?.label ?? preset.displayName
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "crop")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor))

            ratioMenu
                .frame(width: 180)

            dimensionField(draft: $widthDraft, field: .width)
                .help("Width in pixels")
            Text("×")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            dimensionField(draft: $heightDraft, field: .height)
                .help("Height in pixels")
            Text("px")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))

            Divider().frame(height: 20)

            Button(action: onRotateCCW) {
                Image(systemName: "rotate.left")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!canTransformImage)
            .help(canTransformImage
                  ? "Rotate 90° counter-clockwise"
                  : "Rotate is disabled while annotations are present")

            Button(action: onFlipH) {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!canTransformImage)
            .help(canTransformImage
                  ? "Flip horizontally"
                  : "Flip is disabled while annotations are present")

            Spacer()

            Button(action: onCancel) {
                Text("Cancel").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)

            Button(action: onCommit) {
                Text("Crop").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear { syncDrafts() }
        .onChange(of: cropRect) { _, _ in
            if focusedField == nil { syncDrafts() }
        }
        .onChange(of: focusedField) { oldField, newField in
            if let oldField, newField != oldField {
                commitDraft(for: oldField)
            }
        }
        .sheet(isPresented: $showAddCustom) {
            AddCustomCropRatioSheet(
                onAdd: { ratio in
                    addCustomRatio(ratio)
                    showAddCustom = false
                },
                onCancel: { showAddCustom = false }
            )
        }
    }

    @ViewBuilder
    private var ratioMenu: some View {
        Menu {
            ForEach(CropPreset.allCases, id: \.self) { p in
                Button {
                    selectedCustom = nil
                    preset = p
                } label: {
                    HStack {
                        Text(p.displayName)
                        if selectedCustom == nil, preset == p {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if !customRatios.items.isEmpty {
                Divider()
                Section("Custom") {
                    ForEach(customRatios.items) { r in
                        Button {
                            selectedCustom = r
                        } label: {
                            HStack {
                                Text(r.label)
                                if selectedCustom == r {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    ForEach(customRatios.items) { r in
                        Button("Remove \(r.label)", role: .destructive) {
                            removeCustomRatio(r)
                        }
                    }
                }
            }
            Divider()
            Button("Add Custom Ratio…") {
                showAddCustom = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(activeRatioLabel)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private func dimensionField(draft: Binding<String>, field: Field) -> some View {
        TextField("", text: draft)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .font(.system(size: 12, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: 60)
            .focused($focusedField, equals: field)
            .onSubmit { commitDraft(for: field) }
    }

    private func syncDrafts() {
        widthDraft = "\(Int(cropRect.width))"
        heightDraft = "\(Int(cropRect.height))"
    }

    private func activeRatio() -> CGFloat? {
        selectedCustom?.ratio ?? preset.ratio(imageSize: imageSize)
    }

    private func commitDraft(for field: Field) {
        let rawW = Int(widthDraft) ?? Int(cropRect.width)
        let rawH = Int(heightDraft) ?? Int(cropRect.height)

        let (finalW, finalH): (Int, Int)
        if let ratio = activeRatio() {
            switch field {
            case .width:
                finalW = rawW
                finalH = Int((CGFloat(rawW) / ratio).rounded())
            case .height:
                finalH = rawH
                finalW = Int((CGFloat(rawH) * ratio).rounded())
            }
        } else {
            finalW = rawW
            finalH = rawH
        }

        let minEdge: CGFloat = 10
        let maxW = imageSize.width - cropRect.minX
        let maxH = imageSize.height - cropRect.minY
        let clampedW = max(minEdge, min(CGFloat(finalW), maxW))
        let clampedH = max(minEdge, min(CGFloat(finalH), maxH))

        cropRect = CGRect(x: cropRect.minX, y: cropRect.minY, width: clampedW, height: clampedH)
        syncDrafts()
    }

    private func addCustomRatio(_ ratio: CustomCropRatio) {
        var list = customRatios
        if !list.items.contains(ratio) {
            list.items.append(ratio)
            customRatios = list
        }
        selectedCustom = ratio
    }

    private func removeCustomRatio(_ ratio: CustomCropRatio) {
        var list = customRatios
        list.items.removeAll { $0 == ratio }
        customRatios = list
        if selectedCustom == ratio {
            selectedCustom = nil
        }
    }
}
