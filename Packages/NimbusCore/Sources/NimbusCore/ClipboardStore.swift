import AppKit
import Combine
import Foundation

@MainActor
public final class ClipboardStore: ObservableObject {
    @Published public private(set) var items: [ClipboardItem] = []

    public var maxItemsLimit: Int = 100 {
        didSet {
            guard maxItemsLimit != oldValue else { return }
            trimIfNeeded()
            persist()
        }
    }

    public var onInternalPasteboardWrite: (() -> Void)?
    public var onImageIngested: ((ClipboardItem, Data) -> Void)?

    private let fileManager: FileManager
    private let rootURL: URL
    private let indexURL: URL
    private let imagesURL: URL
    private var lastFingerprint: String?

    public convenience init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.init(
            rootURL: support.appendingPathComponent("Nimbus", isDirectory: true),
            fileManager: fileManager
        )
    }

    /// Test / custom storage root (isolated from the live Application Support history).
    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = rootURL
        indexURL = rootURL.appendingPathComponent("history.json")
        imagesURL = rootURL.appendingPathComponent("images", isDirectory: true)
        try? fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        load()
    }

    @discardableResult
    public func ingest(_ snapshot: ClipboardSnapshot) -> ClipboardItem? {
        let fingerprint = snapshot.fingerprint
        guard fingerprint != lastFingerprint else { return nil }

        if let index = items.firstIndex(where: { !$0.contentFingerprint.isEmpty && $0.contentFingerprint == fingerprint }) {
            lastFingerprint = fingerprint
            promoteItem(at: index)
            return items.first
        }

        if let index = items.firstIndex(where: { $0.matches(snapshot, imagesURL: imagesURL) }) {
            lastFingerprint = fingerprint
            promoteItem(at: index)
            return items.first
        }

        lastFingerprint = fingerprint

        let item: ClipboardItem
        var imageData: Data?
        switch snapshot.payload {
        case .text(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let isLink = Self.looksLikeURL(trimmed)
            item = ClipboardItem(
                type: isLink ? .link : .text,
                text: trimmed,
                preview: Self.makePreview(trimmed),
                contentFingerprint: fingerprint,
                sourceAppBundleID: snapshot.source?.bundleID,
                sourceAppName: snapshot.source?.name
            )
        case .image(let data):
            // Always own a heap copy — source may be a temp/mmap'd screenshot that vanishes.
            let owned = Data(data)
            let fileName = "\(UUID().uuidString).png"
            let url = imagesURL.appendingPathComponent(fileName)
            guard (try? owned.write(to: url, options: .atomic)) != nil else { return nil }
            imageData = owned
            item = ClipboardItem(
                type: .image,
                imageFileName: fileName,
                preview: "Screenshot",
                contentFingerprint: fingerprint,
                sourceAppBundleID: snapshot.source?.bundleID,
                sourceAppName: snapshot.source?.name
            )
        }

        items.insert(item, at: 0)
        trimIfNeeded()
        persist()

        if let imageData {
            onImageIngested?(item, imageData)
        }
        return item
    }

    public func copyToPasteboard(_ item: ClipboardItem, plainText: Bool = false) {
        let board = NSPasteboard.general
        board.clearContents()

        switch item.type {
        case .text, .link:
            guard let text = item.text else { return }
            board.setString(text, forType: .string)
            lastFingerprint = item.contentFingerprint.isEmpty
                ? ClipboardSnapshot.fingerprint(forText: text)
                : item.contentFingerprint
        case .image:
            if plainText, let ocr = item.ocrText, !ocr.isEmpty {
                board.setString(ocr, forType: .string)
                lastFingerprint = ClipboardSnapshot.fingerprint(forText: ocr)
            } else {
                guard
                    let name = item.imageFileName,
                    let data = try? Data(contentsOf: imagesURL.appendingPathComponent(name))
                else { return }
                board.setData(data, forType: .png)
                if let image = NSImage(data: data) {
                    board.writeObjects([image])
                }
                lastFingerprint = item.contentFingerprint.isEmpty
                    ? ClipboardSnapshot.fingerprint(forImageData: data)
                    : item.contentFingerprint
            }
        }

        onInternalPasteboardWrite?()
    }

    public func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        sortPinnedFirst()
        persist()
    }

    public func updateOCRText(for id: UUID, text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].ocrText = text
        persist()
    }

    @discardableResult
    public func updateText(for id: UUID, text: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard items[index].type == .text || items[index].type == .link else { return false }

        let fingerprint = ClipboardSnapshot.fingerprint(forText: trimmed)
        // If another item already has this content, drop the duplicate we're editing into.
        if let other = items.firstIndex(where: {
            $0.id != id && !$0.contentFingerprint.isEmpty && $0.contentFingerprint == fingerprint
        }) {
            items.remove(at: index)
            // Adjust index after removal.
            let promote = other > index ? other - 1 : other
            promoteItem(at: promote)
            return true
        }

        let isLink = Self.looksLikeURL(trimmed)
        items[index] = ClipboardItem(
            id: items[index].id,
            createdAt: items[index].createdAt,
            type: isLink ? .link : .text,
            text: trimmed,
            imageFileName: nil,
            preview: Self.makePreview(trimmed),
            contentFingerprint: fingerprint,
            isPinned: items[index].isPinned,
            ocrText: nil,
            sourceAppBundleID: items[index].sourceAppBundleID,
            sourceAppName: items[index].sourceAppName
        )
        lastFingerprint = fingerprint
        persist()
        return true
    }

    public func delete(_ item: ClipboardItem) {
        if let name = item.imageFileName {
            try? fileManager.removeItem(at: imagesURL.appendingPathComponent(name))
        }
        items.removeAll { $0.id == item.id }
        // If deleted item was the "current" fingerprint, clear so re-copy can re-enter.
        if lastFingerprint == item.contentFingerprint {
            lastFingerprint = items.first?.contentFingerprint
        }
        persist()
    }

    public func clearAll(keepingPinned: Bool = true) {
        let kept = keepingPinned ? items.filter(\.isPinned) : []
        let removed = keepingPinned ? items.filter { !$0.isPinned } : items
        for item in removed {
            if let name = item.imageFileName {
                try? fileManager.removeItem(at: imagesURL.appendingPathComponent(name))
            }
        }
        items = kept
        lastFingerprint = kept.first?.contentFingerprint
        persist()
    }

    public func image(for item: ClipboardItem) -> NSImage? {
        guard let name = item.imageFileName else { return nil }
        return NSImage(contentsOf: imagesURL.appendingPathComponent(name))
    }

    public func imageData(for item: ClipboardItem) -> Data? {
        guard let name = item.imageFileName else { return nil }
        return try? Data(contentsOf: imagesURL.appendingPathComponent(name))
    }

    private func promoteItem(at index: Int) {
        guard index > 0 else {
            persist()
            return
        }
        let item = items.remove(at: index)
        items.insert(item, at: 0)
        sortPinnedFirst()
        persist()
    }

    private func sortPinnedFirst() {
        let pinned = items.filter(\.isPinned)
        let rest = items.filter { !$0.isPinned }
        items = pinned + rest
    }

    private func trimIfNeeded() {
        let pinned = items.filter(\.isPinned)
        var unpinned = items.filter { !$0.isPinned }
        let unpinnedLimit = max(0, maxItemsLimit - pinned.count)
        guard unpinned.count > unpinnedLimit else { return }
        let removed = Array(unpinned.suffix(from: unpinnedLimit))
        for item in removed {
            if let name = item.imageFileName {
                try? fileManager.removeItem(at: imagesURL.appendingPathComponent(name))
            }
        }
        unpinned = Array(unpinned.prefix(unpinnedLimit))
        items = pinned + unpinned
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: indexURL),
            let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data)
        else {
            items = []
            return
        }

        items = decoded.map { item in
            guard item.contentFingerprint.isEmpty else { return item }
            switch item.type {
            case .text, .link:
                guard let text = item.text else { return item }
                return ClipboardItem(
                    id: item.id,
                    createdAt: item.createdAt,
                    type: item.type,
                    text: item.text,
                    imageFileName: item.imageFileName,
                    preview: item.preview,
                    contentFingerprint: ClipboardSnapshot.fingerprint(forText: text),
                    isPinned: item.isPinned,
                    ocrText: item.ocrText,
                    sourceAppBundleID: item.sourceAppBundleID,
                    sourceAppName: item.sourceAppName
                )
            case .image:
                guard
                    let name = item.imageFileName,
                    let data = try? Data(contentsOf: imagesURL.appendingPathComponent(name))
                else { return item }
                return ClipboardItem(
                    id: item.id,
                    createdAt: item.createdAt,
                    type: item.type,
                    text: item.text,
                    imageFileName: item.imageFileName,
                    preview: item.preview,
                    contentFingerprint: ClipboardSnapshot.fingerprint(forImageData: data),
                    isPinned: item.isPinned,
                    ocrText: item.ocrText,
                    sourceAppBundleID: item.sourceAppBundleID,
                    sourceAppName: item.sourceAppName
                )
            }
        }
        sortPinnedFirst()
        persist()

        if let first = items.first, !first.contentFingerprint.isEmpty {
            lastFingerprint = first.contentFingerprint
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private static func looksLikeURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else {
            return value.hasPrefix("www.")
        }
        return scheme == "http" || scheme == "https"
    }

    private static func makePreview(_ value: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= 120 { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 120)
        return String(collapsed[..<end]) + "…"
    }
}

private extension ClipboardItem {
    func matches(_ snapshot: ClipboardSnapshot, imagesURL: URL) -> Bool {
        switch (type, snapshot.payload) {
        case (.text, .text(let value)), (.link, .text(let value)):
            return text == value
        case (.image, .image(let data)):
            guard let name = imageFileName else { return false }
            guard let existing = try? Data(contentsOf: imagesURL.appendingPathComponent(name)) else { return false }
            return ClipboardSnapshot.fingerprint(forImageData: existing)
                == ClipboardSnapshot.fingerprint(forImageData: data)
        default:
            return false
        }
    }
}
