// App/Sources/History/HistoryCollectionDetailView.swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import HistoryKit

/// Ordered multi-page PDF collection view where imported PDF pages and
/// interleaved screenshots can be annotated, reordered, and exported back to PDF.
struct HistoryCollectionDetailView: View {
    let collection: HistoryCollectionSummary
    let coordinator: HistoryCoordinator
    var onQuickLook: ([URL]) -> Void = { _ in }

    @State private var selection: Set<UUID> = []
    @State private var anchorID: UUID?
    @State private var draggingEntryID: UUID?
    @State private var dropTargetEntryID: UUID?
    @State private var isExternalDropTargeted = false
    @State private var showAddScreenshotsSheet = false
    @State private var showRenameSheet = false
    @State private var renameDraft = ""
    @State private var columns = 1
    @FocusState private var isGridFocused: Bool

    private var entries: [HistoryEntry] {
        coordinator.activeCollectionEntries
    }

    private var selectedEntries: [HistoryEntry] {
        entries.filter { selection.contains($0.id) }
    }

    private var insertIndexAfterSelection: Int? {
        guard let anchorID, let idx = entries.firstIndex(of: entries.first(where: { $0.id == anchorID }) ?? entries[0]) else {
            return nil
        }
        return idx + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if let progress = coordinator.pdfImportProgress {
                HStack(spacing: 10) {
                    ProgressView(value: progress.fraction)
                        .frame(width: 120)
                    Text("Importing \(progress.fileName) (\(progress.completedPages)/\(progress.totalPages))…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Cancel") {
                        coordinator.cancelPDFImport()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.25))
                Divider()
            }

            if entries.isEmpty {
                emptyDeckState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 165), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                pageCard(entry: entry, index: index)
                            }
                        }
                        .padding(16)
                        .background(GeometryReader { geo in
                            Color.clear.onAppear { updateColumns(geo.size.width) }
                                .onChange(of: geo.size.width) { _, width in updateColumns(width) }
                        })
                    }
                    .focusable()
                    .focused($isGridFocused)
                    .focusEffectDisabled()
                    .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                        moveSelection(press.key, extending: press.modifiers.contains(.shift))
                        if let anchorID { proxy.scrollTo(anchorID) }
                        return .handled
                    }
                    .onKeyPress(.space) {
                        onQuickLook(selectedEntries.compactMap { coordinator.fullImageURL(for: $0) })
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        coordinator.closeCollection()
                        return .handled
                    }
                    .onKeyPress(keys: [.delete, .deleteForward, KeyEquivalent("\u{7F}")]) { _ in
                        guard !selectedEntries.isEmpty else { return .ignored }
                        coordinator.removeEntries(selectedEntries, fromCollection: collection.id)
                        selection.removeAll()
                        anchorID = nil
                        return .handled
                    }
                }
            }

            Divider()
            footerBar
        }
        .overlay {
            if isExternalDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Color.accentColor.opacity(0.08))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isExternalDropTargeted, perform: handleExternalFileDrop)
        .sheet(isPresented: $showAddScreenshotsSheet) {
            AddScreenshotsToCollectionSheet(
                coordinator: coordinator,
                collectionID: collection.id,
                defaultInsertIndex: insertIndexAfterSelection,
                onDismiss: { showAddScreenshotsSheet = false }
            )
        }
        .sheet(isPresented: $showRenameSheet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Rename PDF Collection")
                    .font(.system(size: 14, weight: .semibold))
                TextField("Collection Title", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showRenameSheet = false }
                    Button("Save") {
                        coordinator.renameCollection(collection.id, to: renameDraft)
                        showRenameSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            Button {
                coordinator.closeCollection()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("History")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("[", modifiers: .command)

            Divider()
                .frame(height: 16)

            Button {
                renameDraft = collection.collection.title
                showRenameSheet = true
            } label: {
                HStack(spacing: 5) {
                    Text(collection.collection.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .help("Rename PDF Collection")

            Text("\(entries.count) pages")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                showAddScreenshotsSheet = true
            } label: {
                Label(String(localized: "Add Screenshots"), systemImage: "photo.badge.plus")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Insert screenshots from history into this PDF")

            Button {
                _ = coordinator.pasteImageIntoCollection(collection.id, insertAt: insertIndexAfterSelection)
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 11.5))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("v", modifiers: .command)
            .help("Paste Image from Clipboard (⌘V)")

            Button {
                coordinator.importPDFWithPanel(intoCollectionID: collection.id, insertAt: insertIndexAfterSelection)
            } label: {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 11.5))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Append Pages from Another PDF")

            Button {
                coordinator.exportCollectionAsPDF(collection.collection)
            } label: {
                Label(String(localized: "Export PDF"), systemImage: "square.and.arrow.up")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(entries.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Page Card & Drag Reordering

    private func pageCard(entry: HistoryEntry, index: Int) -> some View {
        HistoryItemView(
            entry: entry,
            coordinator: coordinator,
            isSelected: selection.contains(entry.id),
            pageNumber: index + 1,
            onRemoveFromCollection: {
                coordinator.removeEntries([entry], fromCollection: collection.id)
                selection.remove(entry.id)
            },
            onMoveEarlier: index > 0 ? {
                coordinator.moveEntry(entry.id, by: -1, inCollection: collection.id)
            } : nil,
            onMoveLater: index < entries.count - 1 ? {
                coordinator.moveEntry(entry.id, by: 1, inCollection: collection.id)
            } : nil
        )
        .id(entry.id)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: dropTargetEntryID == entry.id ? 2.5 : 0)
        )
        .opacity(draggingEntryID == entry.id ? 0.45 : 1)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            coordinator.editEntry(entry)
        })
        .simultaneousGesture(TapGesture(count: 1).onEnded {
            select(entry.id, modifiers: NSEvent.modifierFlags)
        })
        .onDrag {
            draggingEntryID = entry.id
            return NSItemProvider(object: entry.id.uuidString as NSString)
        }
        .onDrop(
            of: [.text],
            delegate: CollectionPageDropDelegate(
                targetEntryID: entry.id,
                collectionID: collection.id,
                coordinator: coordinator,
                draggingEntryID: $draggingEntryID,
                dropTargetEntryID: $dropTargetEntryID
            )
        )
    }

    // MARK: - Empty & Footer

    private var emptyDeckState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.richtext")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("This PDF collection is empty")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Add screenshots from history, paste from clipboard (⌘V), or drop images/PDFs here")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            Text("Drag cards to reorder • Double-click a page to annotate • Drop images or PDFs to add")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Text("Order: 1 → \(entries.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    // MARK: - Helpers

    private func updateColumns(_ width: CGFloat) {
        columns = max(1, Int((width - 32 + 12) / (165 + 12)))
    }

    private func select(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        isGridFocused = true
        let ids = entries.map(\.id)
        if modifiers.contains(.command) {
            if selection.remove(id) == nil { selection.insert(id) }
            anchorID = id
        } else if modifiers.contains(.shift), let anchorID,
                  let from = ids.firstIndex(of: anchorID), let to = ids.firstIndex(of: id) {
            selection = Set(ids[min(from, to)...max(from, to)])
        } else {
            selection = [id]
            anchorID = id
        }
    }

    private func moveSelection(_ key: KeyEquivalent, extending: Bool) {
        let ids = entries.map(\.id)
        guard !ids.isEmpty else { return }
        guard let current = anchorID.flatMap(ids.firstIndex(of:)) else {
            selection = [ids[0]]
            anchorID = ids[0]
            return
        }
        let step: Int
        switch key {
        case .leftArrow: step = -1
        case .rightArrow: step = 1
        case .upArrow: step = -columns
        default: step = columns
        }
        let next = ids[min(max(current + step, 0), ids.count - 1)]
        if extending {
            selection.insert(next)
        } else {
            selection = [next]
        }
        anchorID = next
    }

    private func handleExternalFileDrop(providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !matching.isEmpty else { return false }

        let targetCollectionID = collection.id
        let targetInsertIndex = insertIndexAfterSelection
        Task { @MainActor in
            var urls: [URL] = []
            for provider in matching {
                if let url = await HistoryView.loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            let images = urls.filter { $0.pathExtension.lowercased() != "pdf" }
            if !images.isEmpty {
                coordinator.addImageFiles(images, toCollection: targetCollectionID, insertAt: targetInsertIndex)
            }
            if !pdfs.isEmpty {
                coordinator.importPDFFiles(pdfs, intoCollectionID: targetCollectionID, insertAt: targetInsertIndex)
            }
        }
        return true
    }
}

// MARK: - Drag-to-Reorder Drop Delegate

@MainActor
private struct CollectionPageDropDelegate: DropDelegate {
    let targetEntryID: UUID
    let collectionID: UUID
    let coordinator: HistoryCoordinator
    @Binding var draggingEntryID: UUID?
    @Binding var dropTargetEntryID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingEntryID, draggingEntryID != targetEntryID else { return }
        dropTargetEntryID = targetEntryID
        withAnimation(.easeInOut(duration: 0.15)) {
            coordinator.moveEntry(draggingEntryID, before: targetEntryID, inCollection: collectionID)
        }
    }

    func dropExited(info: DropInfo) {
        if dropTargetEntryID == targetEntryID {
            dropTargetEntryID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingEntryID = nil
        dropTargetEntryID = nil
        return true
    }
}

// MARK: - Add Screenshots Picker Sheet

private struct AddScreenshotsToCollectionSheet: View {
    let coordinator: HistoryCoordinator
    let collectionID: UUID
    let defaultInsertIndex: Int?
    let onDismiss: () -> Void

    @State private var screenshots: [HistoryEntry] = []
    @State private var pickedIDs: [UUID] = []
    @State private var insertAfterSelected = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Screenshots to PDF")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if defaultInsertIndex != nil {
                    Toggle("Insert after selected page", isOn: $insertAfterSelected)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }
            }
            .padding(16)

            Divider()

            if screenshots.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("No screenshots in history yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(screenshots) { entry in
                            let pickIndex = pickedIDs.firstIndex(of: entry.id)
                            PickerScreenshotTile(
                                entry: entry,
                                coordinator: coordinator,
                                orderBadge: pickIndex.map { $0 + 1 }
                            )
                            .onTapGesture {
                                if let idx = pickedIDs.firstIndex(of: entry.id) {
                                    pickedIDs.remove(at: idx)
                                } else {
                                    pickedIDs.append(entry.id)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }

            Divider()

            HStack {
                Text(pickedIDs.isEmpty ? "Click screenshots in the order you want to insert them" : "\(pickedIDs.count) selected")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onDismiss)
                Button("Insert (\(pickedIDs.count))") {
                    let entryMap = Dictionary(uniqueKeysWithValues: screenshots.map { ($0.id, $0) })
                    let ordered = pickedIDs.compactMap { entryMap[$0] }
                    let targetIndex = (insertAfterSelected ? defaultInsertIndex : nil)
                    coordinator.addEntries(ordered, toCollection: collectionID, insertAt: targetIndex)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pickedIDs.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 600, height: 440)
        .onAppear {
            let existingIDs = Set(coordinator.activeCollectionEntries.map(\.id))
            screenshots = coordinator.availableScreenshots().filter { !existingIDs.contains($0.id) }
        }
    }
}

private struct PickerScreenshotTile: View {
    let entry: HistoryEntry
    let coordinator: HistoryCoordinator
    let orderBadge: Int?
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle().fill(.quaternary.opacity(0.3))
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if let orderBadge {
                    Text("\(orderBadge)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .padding(5)
                }
            }

            Text(entry.sourceAppName ?? String(localized: "Screenshot"))
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .background(.white.opacity(orderBadge != nil ? 0.1 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(orderBadge != nil ? Color.accentColor : .white.opacity(0.06), lineWidth: orderBadge != nil ? 2 : 0.5)
        )
        .onAppear {
            if let url = coordinator.thumbnailURL(for: entry) {
                thumbnail = NSImage(contentsOf: url)
            }
        }
    }
}
