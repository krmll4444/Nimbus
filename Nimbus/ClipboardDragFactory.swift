import AppKit
import NimbusCore
import UniformTypeIdentifiers

enum ClipboardDragFactory {
    /// Builds a drag payload similar to the macOS screenshot thumbnail:
    /// images as a real PNG file URL (+ PNG data), text/links as UTF-8 strings.
    static func itemProvider(
        for item: ClipboardItem,
        imageData: Data?
    ) -> NSItemProvider {
        switch item.type {
        case .text, .link:
            let text = item.text ?? item.preview
            return NSItemProvider(object: text as NSString)

        case .image:
            guard let imageData else {
                return NSItemProvider(object: item.preview as NSString)
            }

            let fileURL = temporaryPNGURL(for: item.id, data: imageData)
            let provider: NSItemProvider
            if let fileURL, let fileProvider = NSItemProvider(contentsOf: fileURL) {
                provider = fileProvider
            } else {
                provider = NSItemProvider()
            }

            provider.suggestedName = suggestedName(for: item)

            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.png.identifier,
                visibility: .all
            ) { completion in
                completion(imageData, nil)
                return nil
            }

            // Some targets prefer TIFF.
            if let image = NSImage(data: imageData),
               let tiff = image.tiffRepresentation {
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.tiff.identifier,
                    visibility: .all
                ) { completion in
                    completion(tiff, nil)
                    return nil
                }
            }

            return provider
        }
    }

    private static func temporaryPNGURL(for id: UUID, data: Data) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NimbusDrag", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Screenshot-\(id.uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func suggestedName(for item: ClipboardItem) -> String {
        let stamp = item.createdAt.formatted(.dateTime.year().month().day().hour().minute())
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
            .replacingOccurrences(of: ", ", with: " ")
        return "Screenshot \(stamp).png"
    }
}
