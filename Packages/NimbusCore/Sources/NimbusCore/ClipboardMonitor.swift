import AppKit
import Foundation

@MainActor
public final class ClipboardMonitor {
    public var onChange: ((ClipboardSnapshot) -> Void)?
    public var shouldCapture: (() -> Bool)?
    public var isAppIgnored: ((String?) -> Bool)?

    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private let interval: TimeInterval

    public init(interval: TimeInterval = 0.5) {
        self.interval = interval
    }

    public func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func ignoreCurrentPasteboard() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        let board = NSPasteboard.general
        let changeCount = board.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if shouldCapture?() == false { return }

        let frontApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontApp?.bundleIdentifier
        if isAppIgnored?(bundleID) == true { return }

        // Concealed / password fields often mark pasteboard as transient/confidential.
        if board.pasteboardItems?.contains(where: {
            $0.types.contains(.init("org.nspasteboard.TransientType"))
                || $0.types.contains(.init("org.nspasteboard.ConcealedType"))
                || $0.types.contains(.init("com.agilebits.onepassword"))
        }) == true {
            return
        }

        let source = ClipboardSource(bundleID: bundleID, name: frontApp?.localizedName)
        let string = board.string(forType: .string)
        let imageData = readImageData(from: board)

        if let imageData {
            let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let textIsJustFileName = trimmed.hasSuffix(".png")
                || trimmed.hasSuffix(".heic")
                || trimmed.hasPrefix("Screenshot")
                || trimmed.hasPrefix("Знімок")
            if trimmed.isEmpty || textIsJustFileName {
                onChange?(ClipboardSnapshot(payload: .image(imageData), source: source))
                return
            }
        }

        if let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onChange?(ClipboardSnapshot(payload: .text(string), source: source))
            return
        }

        if let imageData {
            onChange?(ClipboardSnapshot(payload: .image(imageData), source: source))
        }
    }

    private func readImageData(from board: NSPasteboard) -> Data? {
        if let data = board.data(forType: .png) {
            return data
        }
        if let data = board.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: data),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        if board.canReadObject(forClasses: [NSImage.self], options: nil),
           let images = board.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }
}
