// App/Sources/QuickAccess/QuickAccessView.swift
import SwiftUI

struct QuickAccessView: View {
    let thumbnail: NSImage
    let onCopy: () -> Void
    let onSave: () -> Void
    let onAnnotate: () -> Void
    let onPin: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 200, maxHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(8)

            VStack(spacing: 6) {
                quickActionButton("Copy", systemImage: "doc.on.doc", action: onCopy)
                quickActionButton("Save", systemImage: "square.and.arrow.down", action: onSave)
                quickActionButton("Annotate", systemImage: "pencil.tip.crop.circle", action: onAnnotate)
                quickActionButton("Pin", systemImage: "pin.fill", action: onPin)
            }
            .frame(width: 110)
            .padding(.trailing, 8)
            .padding(.vertical, 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .padding(.top, 6)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }

    private func quickActionButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
