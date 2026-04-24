// App/Sources/AnnotationEditor/Crop/CustomCropRatio.swift
import SwiftUI

/// A user-defined aspect ratio. Persisted in UserDefaults as a JSON array
/// (wrapped by `CustomCropRatioStore` for @AppStorage compatibility).
struct CustomCropRatio: Codable, Hashable, Identifiable {
    let width: Int
    let height: Int

    var id: String { "\(width):\(height)" }
    var label: String { "\(width) : \(height)" }

    /// Aspect ratio as width / height.
    var ratio: CGFloat {
        guard height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }
}

/// Thin wrapper to serialize `[CustomCropRatio]` through `@AppStorage`,
/// which only supports `RawRepresentable` with `String` or `Int` raw value.
struct CustomCropRatioList: RawRepresentable, Equatable {
    var items: [CustomCropRatio]

    init(items: [CustomCropRatio]) { self.items = items }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([CustomCropRatio].self, from: data)
        else { return nil }
        self.items = decoded
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(items),
              let str = String(data: data, encoding: .utf8)
        else { return "[]" }
        return str
    }
}

// MARK: - Add-custom sheet

struct AddCustomCropRatioSheet: View {
    let onAdd: (CustomCropRatio) -> Void
    let onCancel: () -> Void

    @State private var widthText: String = ""
    @State private var heightText: String = ""
    @FocusState private var focused: Field?

    private enum Field { case width, height }

    private var parsed: (Int, Int)? {
        guard let w = Int(widthText), let h = Int(heightText),
              w > 0, h > 0 else { return nil }
        return (w, h)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Ratio")
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 8) {
                TextField("Width", text: $widthText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .focused($focused, equals: .width)
                Text(":")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                TextField("Height", text: $heightText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .focused($focused, equals: .height)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    if let (w, h) = parsed {
                        onAdd(CustomCropRatio(width: w, height: h))
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(parsed == nil)
            }
        }
        .padding(16)
        .frame(width: 260)
        .onAppear { focused = .width }
    }
}
