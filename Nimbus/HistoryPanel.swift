import AppKit
import NimbusCore
import SwiftUI

struct HistoryPanel: View {
    @ObservedObject var controller: ClipboardController
    @ObservedObject private var settings = AppSettings.shared
    @State private var query = ""
    @State private var filter: HistoryFilter = .all
    @State private var editingItem: ClipboardItem?
    @State private var confirmClearAll = false

    private var filtered: [ClipboardItem] {
        var items = controller.store.items
        switch filter {
        case .all: break
        case .text: items = items.filter { $0.type == .text }
        case .link: items = items.filter { $0.type == .link }
        case .image: items = items.filter { $0.type == .image }
        case .pinned: items = items.filter(\.isPinned)
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.preview.localizedCaseInsensitiveContains(q)
                || ($0.text?.localizedCaseInsensitiveContains(q) ?? false)
                || ($0.ocrText?.localizedCaseInsensitiveContains(q) ?? false)
                || ($0.sourceAppName?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            if settings.pauseCapture {
                pauseBanner
            }
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(width: 460, height: 580)
        .background(.ultraThinMaterial)
        .onAppear { controller.visibleItemIDs = filtered.map(\.id) }
        .onChange(of: query) { syncVisibleIDs() }
        .onChange(of: filter) { syncVisibleIDs() }
        .onChange(of: controller.store.items) { syncVisibleIDs() }
        .sheet(item: $editingItem) { item in
            EditTextSheet(
                item: item,
                onSave: { text in
                    _ = controller.updateText(item, text: text)
                    editingItem = nil
                },
                onCancel: { editingItem = nil }
            )
        }
    }

    private func syncVisibleIDs() {
        controller.visibleItemIDs = filtered.map(\.id)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("NimbusMark")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)
            TextField(settings.t(.searchHistory), text: $query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            if !controller.store.items.filter({ !$0.isPinned }).isEmpty {
                NimbusTextButton(
                    title: settings.t(.clearAll),
                    help: settings.t(.clearAll),
                    role: .destructive
                ) {
                    confirmClearAll = true
                }
                .confirmationDialog(
                    settings.t(.clearAllTitle),
                    isPresented: $confirmClearAll,
                    titleVisibility: .visible
                ) {
                    Button(settings.t(.clearAll), role: .destructive) {
                        controller.clearAll()
                    }
                    Button(settings.t(.cancel), role: .cancel) {}
                } message: {
                    Text(settings.t(.clearAllMessage))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(HistoryFilter.allCases) { item in
                NimbusFilterChip(
                    title: filterTitle(item),
                    selected: filter == item
                ) {
                    filter = item
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var pauseBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
            Text(settings.t(.capturePaused))
            Spacer()
            NimbusTextButton(
                title: settings.t(.resumeCapture),
                prominent: true
            ) {
                controller.togglePause()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image("NimbusMark")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(0.9)
            Text(settings.t(.clipboardEmpty))
                .foregroundStyle(.secondary)
            Text(settings.t(.clipboardEmptyHint))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filtered) { item in
                    HistoryRow(
                        item: item,
                        image: item.type == .image ? controller.store.image(for: item) : nil,
                        imageData: item.type == .image ? controller.store.imageData(for: item) : nil,
                        onPaste: { controller.paste(item) },
                        onCopy: { controller.copy(item) },
                        onPastePlain: { controller.paste(item, plainText: true) },
                        onPin: { controller.togglePin(item) },
                        onEdit: (item.type == .text || item.type == .link)
                            ? { editingItem = item }
                            : nil,
                        onDelete: { controller.delete(item) }
                    )
                }
            }
            .padding(8)
        }
    }

    private func filterTitle(_ filter: HistoryFilter) -> String {
        switch filter {
        case .all: return settings.t(.filterAll)
        case .text: return settings.t(.filterText)
        case .link: return settings.t(.filterLinks)
        case .image: return settings.t(.filterImages)
        case .pinned: return settings.t(.filterPinned)
        }
    }
}

private struct HistoryRow: View {
    let item: ClipboardItem
    let image: NSImage?
    let imageData: Data?
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onPastePlain: () -> Void
    let onPin: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var hovering = false

    private var useFullWidthImage: Bool {
        item.type == .image
            && image != nil
            && settings.screenshotPreviewStyle == .fullWidth
    }

    var body: some View {
        Group {
            if useFullWidthImage {
                fullWidthCard
            } else {
                compactCard
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(rowFillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovering ? 0.10 : 0), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onDrag {
            ClipboardDragFactory.itemProvider(for: item, imageData: imageData)
        } preview: {
            dragPreview
        }
        .contextMenu {
            Button(settings.t(.paste), action: onPaste)
            Button(settings.t(.pastePlain), action: onPastePlain)
            Button(settings.t(.copy), action: onCopy)
            if let onEdit {
                Button(settings.t(.edit), action: onEdit)
            }
            Divider()
            Button(item.isPinned ? settings.t(.unpin) : settings.t(.pin), action: onPin)
            Button(settings.t(.deleteConfirm), role: .destructive, action: onDelete)
        }
    }

    private var rowFillOpacity: Double {
        if hovering { return item.isPinned ? 0.12 : 0.08 }
        return item.isPinned ? 0.08 : 0.04
    }

    @ViewBuilder
    private var dragPreview: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 180, maxHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(radius: 6, y: 2)
                .padding(6)
        } else {
            Text(item.preview)
                .lineLimit(3)
                .frame(width: 160, alignment: .leading)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// Compact: thumbnail | text | actions
    private var compactCard: some View {
        HStack(alignment: .center, spacing: 12) {
            smallThumbnail
                .onTapGesture(perform: onPaste)
            metaColumn
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onPaste)
            actionButtons
        }
    }

    /// Wide screenshot: row1 = photo full width, row2 = caption + buttons
    private var fullWidthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onPaste)
            }

            HStack(alignment: .center, spacing: 10) {
                metaColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onPaste)
                actionButtons
            }
        }
    }

    private var metaColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.preview)
                    .font(useFullWidthImage ? .body.weight(.medium) : .body)
                    .lineLimit(useFullWidthImage ? 1 : 2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 6) {
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let source = item.sourceAppName {
                    Text("·")
                    Text(source)
                }
                if item.ocrText != nil {
                    Text("·")
                    Text("OCR")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            NimbusCircleIconButton(
                systemName: item.isPinned ? "pin.fill" : "pin",
                help: item.isPinned ? settings.t(.unpin) : settings.t(.pin),
                action: onPin
            )
            .opacity(hovering || item.isPinned ? 1 : 0.55)

            if let onEdit {
                NimbusCircleIconButton(
                    systemName: "pencil",
                    help: settings.t(.edit),
                    action: onEdit
                )
                .opacity(hovering ? 1 : 0.55)
            }

            NimbusCircleIconButton(
                systemName: "trash",
                help: settings.t(.deleteConfirm),
                role: .destructive,
                action: onDelete
            )
            .opacity(hovering ? 1 : 0.55)
        }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    @ViewBuilder
    private var smallThumbnail: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 36, height: 36)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var iconName: String {
        switch item.type {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        }
    }
}

private struct EditTextSheet: View {
    let item: ClipboardItem
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.t(.editItem))
                .font(.headline)

            TextEditor(text: $draft)
                .font(.body)
                .focused($focused)
                .frame(minHeight: 160)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

            HStack(spacing: 8) {
                Spacer()
                NimbusTextButton(title: settings.t(.cancel), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(settings.t(.save)) {
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420, height: 260)
        .onAppear {
            draft = item.text ?? ""
            focused = true
        }
    }
}
