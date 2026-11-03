import AppKit
import CryptoKit
import Foundation

public enum ClipboardPayload: Sendable, Equatable {
    case text(String)
    case image(Data)
}

public struct ClipboardSnapshot: Sendable, Equatable {
    public let payload: ClipboardPayload
    public let fingerprint: String
    public let source: ClipboardSource?

    public init(payload: ClipboardPayload, source: ClipboardSource? = nil) {
        self.payload = payload
        self.source = source
        switch payload {
        case .text(let value):
            self.fingerprint = Self.fingerprint(forText: value)
        case .image(let data):
            self.fingerprint = Self.fingerprint(forImageData: data)
        }
    }

    public static func fingerprint(forText value: String) -> String {
        hash("text:" + value)
    }

    public static func fingerprint(forImageData data: Data) -> String {
        if let pixelHash = pixelFingerprint(for: data) {
            return pixelHash
        }
        let digest = SHA256.hash(data: data)
        return "image-bytes:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func pixelFingerprint(for data: Data) -> String? {
        guard let image = NSImage(data: data) else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }

        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return nil }

        let maxSide = 128
        let scale = min(1.0, CGFloat(maxSide) / CGFloat(max(width, height)))
        let tw = max(1, Int(CGFloat(width) * scale))
        let th = max(1, Int(CGFloat(height) * scale))
        let bytesPerRow = tw * 4
        var pixels = [UInt8](repeating: 0, count: th * bytesPerRow)

        guard let ctx = CGContext(
            data: &pixels,
            width: tw,
            height: th,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))

        var hasher = SHA256()
        withUnsafeBytes(of: Int32(tw)) { hasher.update(bufferPointer: $0) }
        withUnsafeBytes(of: Int32(th)) { hasher.update(bufferPointer: $0) }
        pixels.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        let digest = hasher.finalize()
        return "image-px:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
