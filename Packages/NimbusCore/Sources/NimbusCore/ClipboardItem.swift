import Foundation

public enum ClipboardContentType: String, Codable, Sendable, Hashable, CaseIterable {
    case text
    case link
    case image
}

public struct ClipboardItem: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let createdAt: Date
    public let type: ClipboardContentType
    public let text: String?
    public let imageFileName: String?
    public let preview: String
    public let contentFingerprint: String
    public var isPinned: Bool
    public var ocrText: String?
    public var sourceAppBundleID: String?
    public var sourceAppName: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        type: ClipboardContentType,
        text: String? = nil,
        imageFileName: String? = nil,
        preview: String,
        contentFingerprint: String,
        isPinned: Bool = false,
        ocrText: String? = nil,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.type = type
        self.text = text
        self.imageFileName = imageFileName
        self.preview = preview
        self.contentFingerprint = contentFingerprint
        self.isPinned = isPinned
        self.ocrText = ocrText
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, type, text, imageFileName, preview, contentFingerprint
        case isPinned, ocrText, sourceAppBundleID, sourceAppName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        type = try container.decode(ClipboardContentType.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
        preview = try container.decode(String.self, forKey: .preview)
        contentFingerprint = try container.decodeIfPresent(String.self, forKey: .contentFingerprint) ?? ""
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
        sourceAppBundleID = try container.decodeIfPresent(String.self, forKey: .sourceAppBundleID)
        sourceAppName = try container.decodeIfPresent(String.self, forKey: .sourceAppName)
    }
}

public struct ClipboardSource: Sendable, Equatable {
    public let bundleID: String?
    public let name: String?

    public init(bundleID: String?, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }
}
