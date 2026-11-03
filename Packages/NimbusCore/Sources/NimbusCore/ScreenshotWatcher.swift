import AppKit
import CoreGraphics
import CoreServices
import Foundation

/// Event-driven screenshot capture.
///
/// Priority (location-agnostic — Desktop is only the *default* save folder):
/// 1. Live session: drag pasteboard, general pasteboard, floating thumbnail window
/// 2. Temp staging: `$TMPDIR/TemporaryItems/NSIRD_screencaptureui_*`
/// 3. Configured save folder from `com.apple.screencapture` `location` (Desktop,
///    Pictures, custom path — whatever the user set in System Settings)
///
/// Every capture is handed off as in-memory PNG bytes; `ClipboardStore` persists
/// its own copy under Application Support so deleted temp/Desktop originals are fine.
@MainActor
public final class ScreenshotWatcher {
    public var onCapture: ((Data) -> Void)?

    private var directories: [URL] = []
    private var known: Set<String> = []
    private var knownIngestedFingerprints: Set<String> = []
    private var startedAt = Date()
    private var isCapturingSession = false

    private var eventStream: FSEventStreamRef?
    private var metadataQuery: NSMetadataQuery?
    private var burstTimer: Timer?
    private var burstDeadline: Date?
    private var launchObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var dragEventMonitor: Any?
    private var localDragEventMonitor: Any?

    /// Armed at the start of a capture session so we only ingest *new* pasteboard data.
    private var lastGeneralChangeCount = -1
    private var lastDragChangeCount = -1
    private var didCaptureFromThumbnailWindow = false

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func start() {
        stop()
        startedAt = Date()
        directories = Self.resolveWatchDirectories(includingTemporaryStaging: true)
        seedKnownFiles()
        startFSEvents()
        startMetadataQuery()
        observeScreenshotUI()
        armPasteboardBaselines()
    }

    public func stop() {
        stopBurst()
        stopDragMonitors()
        stopFSEvents()
        stopMetadataQuery()
        isCapturingSession = false
        if let launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
            self.launchObserver = nil
        }
        if let activateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activateObserver)
            self.activateObserver = nil
        }
        if let terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver)
            self.terminateObserver = nil
        }
    }

    /// Wake after ⌘⇧3/4/5 or when the floating thumbnail UI appears.
    public func pingAggressiveCapture(duration: TimeInterval = 14) {
        isCapturingSession = true
        didCaptureFromThumbnailWindow = false
        armPasteboardBaselines()
        startBurst(duration: duration)
        startDragMonitors()
        scanForNewScreenshots(preferTemporaryStaging: true)
        captureLivePasteboards()
        captureFloatingThumbnailIfPossible()
    }

    // MARK: - FSEvents

    private func startFSEvents() {
        stopFSEvents()
        let paths = directories.map(\.path) as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, numEvents, eventPaths, eventFlags, _ in
                guard let info else { return }
                let watcher = Unmanaged<ScreenshotWatcher>.fromOpaque(info).takeUnretainedValue()
                let count = Int(numEvents)
                let flagsPtr = UnsafePointer<FSEventStreamEventFlags>(eventFlags)
                let pathArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray

                var urgentPaths: [String] = []
                for i in 0..<count {
                    let flags = flagsPtr[i]
                    let created = (flags & UInt32(kFSEventStreamEventFlagItemCreated)) != 0
                    let renamed = (flags & UInt32(kFSEventStreamEventFlagItemRenamed)) != 0
                    if created || renamed, let path = pathArray[i] as? String {
                        urgentPaths.append(path)
                    }
                }

                Task { @MainActor in
                    for path in urgentPaths {
                        watcher.handleUrgentPath(path)
                    }
                    watcher.scanForNewScreenshots(preferTemporaryStaging: watcher.isCapturingSession)
                    if watcher.isCapturingSession {
                        watcher.captureLivePasteboards()
                    }
                }
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
            )
        ) else { return }

        eventStream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    private func stopFSEvents() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }

    private func handleUrgentPath(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if url.hasDirectoryPath || path.contains("NSIRD_screencaptureui") {
            scanTemporaryStaging(force: true)
            return
        }
        guard Self.looksLikeScreenshot(url) || path.contains("NSIRD_screencaptureui") else { return }
        if known.contains(path) { return }
        known.insert(path)
        ingestWhenReady(url, attemptsLeft: 40, lastSize: -1, urgent: true)
    }

    // MARK: - Spotlight

    private func startMetadataQuery() {
        stopMetadataQuery()
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K == YES", "kMDItemIsScreenCapture")
        query.searchScopes = Self.resolveScreenshotDirectories().map(\.path)
        query.notificationBatchingInterval = 0.3

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataUpdated(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataUpdated(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        metadataQuery = query
        query.start()
    }

    private func stopMetadataQuery() {
        if let query = metadataQuery {
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
            query.stop()
        }
        metadataQuery = nil
    }

    @objc private func metadataUpdated(_ note: Notification) {
        if note.name == .NSMetadataQueryDidFinishGathering {
            seedKnownFromMetadata()
            return
        }
        scanForNewScreenshots(preferTemporaryStaging: isCapturingSession)
    }

    private func seedKnownFromMetadata() {
        guard let query = metadataQuery else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: kMDItemPath as String) as? String
            else { continue }
            known.insert(path)
        }
    }

    // MARK: - Screenshot UI

    private func observeScreenshotUI() {
        let center = NSWorkspace.shared.notificationCenter

        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let bundle = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            guard Self.isScreenshotBundle(bundle) else { return }
            Task { @MainActor in
                self?.pingAggressiveCapture()
            }
        }

        activateObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let bundle = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            guard Self.isScreenshotBundle(bundle) else { return }
            Task { @MainActor in
                self?.pingAggressiveCapture()
            }
        }

        terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let bundle = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            guard Self.isScreenshotBundle(bundle) else { return }
            Task { @MainActor in
                self?.scanForNewScreenshots(preferTemporaryStaging: true)
                self?.captureLivePasteboards()
                // Keep a short tail — drag may finish right as UI quits.
                self?.pingAggressiveCapture(duration: 2.5)
            }
        }
    }

    private func startBurst(duration: TimeInterval) {
        burstDeadline = Date().addingTimeInterval(duration)
        if burstTimer != nil { return }

        // Fast enough to catch a quick drag into Cursor before the drag pasteboard clears.
        burstTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.scanForNewScreenshots(preferTemporaryStaging: true)
                self.captureLivePasteboards()
                self.captureFloatingThumbnailIfPossible()
                if let deadline = self.burstDeadline, Date() >= deadline {
                    self.stopBurst()
                    self.isCapturingSession = false
                    self.stopDragMonitors()
                }
            }
        }
        if let burstTimer {
            RunLoop.main.add(burstTimer, forMode: .common)
        }
    }

    private func stopBurst() {
        burstTimer?.invalidate()
        burstTimer = nil
        burstDeadline = nil
    }

    /// While the thumbnail is up, any mouse-drag is likely the user pulling the screenshot away.
    /// Sample the drag pasteboard immediately — waiting for the 50ms burst tick can miss a fast drop.
    private func startDragMonitors() {
        guard dragEventMonitor == nil else { return }
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isCapturingSession else { return }
                self.captureLivePasteboards()
                self.captureFloatingThumbnailIfPossible()
            }
        }
        dragEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { event in
            handler(event)
        }
        localDragEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { event in
            handler(event)
            return event
        }
    }

    private func stopDragMonitors() {
        if let dragEventMonitor {
            NSEvent.removeMonitor(dragEventMonitor)
            self.dragEventMonitor = nil
        }
        if let localDragEventMonitor {
            NSEvent.removeMonitor(localDragEventMonitor)
            self.localDragEventMonitor = nil
        }
    }

    // MARK: - Pasteboard (general + drag)

    private func armPasteboardBaselines() {
        lastGeneralChangeCount = NSPasteboard.general.changeCount
        lastDragChangeCount = NSPasteboard(name: .drag).changeCount
    }

    private func captureLivePasteboards() {
        let general = NSPasteboard.general
        if general.changeCount != lastGeneralChangeCount {
            lastGeneralChangeCount = general.changeCount
            if let png = Self.imagePNG(from: general) {
                commitCapture(png)
            }
        }

        // Dragging the floating thumbnail populates the drag pasteboard — often the only
        // place the pixels exist when the user drops into another app instead of Desktop.
        let drag = NSPasteboard(name: .drag)
        if drag.changeCount != lastDragChangeCount {
            lastDragChangeCount = drag.changeCount
            if let png = Self.imagePNG(from: drag) {
                commitCapture(png)
            }
        }
    }

    private static func imagePNG(from board: NSPasteboard) -> Data? {
        if let png = board.data(forType: .png), !png.isEmpty {
            return png
        }
        if let tiff = board.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]),
           !png.isEmpty {
            return png
        }
        if let images = board.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            for image in images {
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]),
                      !png.isEmpty else { continue }
                return png
            }
        }
        // File URL promises (may fail for TCC-locked TemporaryItems — try anyway).
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = board.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
            for url in urls {
                guard looksLikeScreenshot(url) || url.path.contains("NSIRD_screencaptureui") else { continue }
                if let data = try? Data(contentsOf: url, options: [.uncached]),
                   let png = pngData(from: data, url: url) {
                    return png
                }
            }
        }
        return nil
    }

    // MARK: - Floating thumbnail window

    /// Best-effort grab of the ⌘⇧4 preview bubble. Only runs when Screen Recording is already
    /// granted — calling `CGWindowListCreateImage` without it spams
    /// "Unable to obtain a task name port right for pid … WindowServer".
    private func captureFloatingThumbnailIfPossible() {
        guard isCapturingSession, !didCaptureFromThumbnailWindow else { return }
        // Do not prompt here; pasteboard/temp paths cover the common case without TCC noise.
        guard CGPreflightScreenCaptureAccess() else { return }

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return }

        for info in list {
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard pid != 0,
                  let app = NSRunningApplication(processIdentifier: pid),
                  Self.isScreenshotBundle(app.bundleIdentifier)
            else { continue }

            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  // Skip the full-screen dimming/selection overlay; keep the small preview chip.
                  bounds.width >= 48, bounds.height >= 48,
                  bounds.width <= 900, bounds.height <= 700
            else { continue }

            let rawID = info[kCGWindowNumber as String] as? Int ?? 0
            guard rawID > 0 else { continue }
            let windowID = CGWindowID(rawID)

            guard let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            ), cgImage.width > 16, cgImage.height > 16 else { continue }

            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let png = rep.representation(using: .png, properties: [:]), !png.isEmpty else { continue }
            didCaptureFromThumbnailWindow = true
            commitCapture(png)
            return
        }
    }

    // MARK: - Scan / ingest

    private func seedKnownFiles() {
        known = []
        for directory in directories {
            seedKnown(in: directory, recursive: directory.path.contains("TemporaryItems"))
        }
    }

    private func seedKnown(in directory: URL, recursive: Bool) {
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        if recursive {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: options
            ) else { return }
            for case let file as URL in enumerator where Self.looksLikeScreenshot(file) {
                known.insert(file.path)
            }
        } else {
            let files = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: options
            )) ?? []
            for file in files where Self.looksLikeScreenshot(file) {
                known.insert(file.path)
            }
        }
    }

    private func scanForNewScreenshots(preferTemporaryStaging: Bool) {
        let latest = Self.resolveWatchDirectories(includingTemporaryStaging: true)
        if Set(latest.map(\.path)) != Set(directories.map(\.path)) {
            directories = latest
            stopFSEvents()
            startFSEvents()
        }

        if preferTemporaryStaging {
            scanTemporaryStaging(force: true)
        }

        for directory in directories where !directory.path.contains("TemporaryItems") {
            scanDirectory(directory, recursive: false)
        }
    }

    private func scanTemporaryStaging(force: Bool) {
        guard force || isCapturingSession else { return }
        let tempItems = Self.temporaryItemsDirectory()
        guard fileManager.fileExists(atPath: tempItems.path) else { return }

        let children = (try? fileManager.contentsOfDirectory(
            at: tempItems,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for child in children {
            let name = child.lastPathComponent
            if name.hasPrefix("NSIRD_screencaptureui") || name.contains("screencapture") {
                scanDirectory(child, recursive: true)
            } else if Self.looksLikeScreenshot(child) {
                considerFile(child, urgent: true)
            }
        }
    }

    private func scanDirectory(_ directory: URL, recursive: Bool) {
        guard fileManager.fileExists(atPath: directory.path) else { return }

        if recursive {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .creationDateKey,
                    .fileSizeKey,
                    .isRegularFileKey
                ],
                options: [.skipsHiddenFiles]
            ) else { return }
            for case let file as URL in enumerator {
                considerFile(file, urgent: directory.path.contains("NSIRD_screencaptureui"))
            }
            return
        }

        let files = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .creationDateKey,
                .fileSizeKey,
                .isRegularFileKey
            ],
            options: [.skipsHiddenFiles]
        )) ?? []
        for file in files {
            considerFile(file, urgent: false)
        }
    }

    private func considerFile(_ file: URL, urgent: Bool) {
        guard Self.looksLikeScreenshot(file) else { return }
        let path = file.path
        if known.contains(path) { return }

        let values = try? file.resourceValues(forKeys: [
            .creationDateKey,
            .contentModificationDateKey,
            .isRegularFileKey
        ])
        guard values?.isRegularFile != false else { return }

        let created = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
        if !urgent || !isCapturingSession {
            guard created >= startedAt.addingTimeInterval(-5) else {
                known.insert(path)
                return
            }
        } else if created < startedAt.addingTimeInterval(-120) {
            known.insert(path)
            return
        }

        known.insert(path)
        ingestWhenReady(file, attemptsLeft: urgent ? 40 : 25, lastSize: -1, urgent: urgent)
    }

    private func ingestWhenReady(_ url: URL, attemptsLeft: Int, lastSize: Int, urgent: Bool) {
        guard attemptsLeft > 0 else { return }

        // `.uncached` forces a real memory copy — temp staging files disappear on drag-away.
        if let data = try? Data(contentsOf: url, options: [.uncached]), !data.isEmpty,
           let png = Self.pngData(from: data, url: url) {
            let size = data.count
            if !urgent, size != lastSize, lastSize != -1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                    self?.ingestWhenReady(url, attemptsLeft: attemptsLeft - 1, lastSize: size, urgent: urgent)
                }
                return
            }
            if urgent || size == lastSize || lastSize == -1 {
                if !urgent && lastSize == -1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                        self?.ingestWhenReady(url, attemptsLeft: attemptsLeft - 1, lastSize: size, urgent: urgent)
                    }
                    return
                }
                commitCapture(png)
                return
            }
        }

        let delay = urgent ? 0.04 : 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.ingestWhenReady(url, attemptsLeft: attemptsLeft - 1, lastSize: lastSize, urgent: urgent)
        }
    }

    private func commitCapture(_ png: Data) {
        // Own the bytes before fingerprint/callback — callers may pass mmap'd temp data.
        let owned = Data(png)
        let fingerprint = ClipboardSnapshot.fingerprint(forImageData: owned)
        guard !knownIngestedFingerprints.contains(fingerprint) else { return }
        knownIngestedFingerprints.insert(fingerprint)
        if knownIngestedFingerprints.count > 300 {
            knownIngestedFingerprints = Set(knownIngestedFingerprints.suffix(150))
        }
        onCapture?(owned)
    }

    // MARK: - Paths

    /// Folder where macOS eventually saves screenshots (System Settings → Screenshot).
    /// Not hardcoded to Desktop — respects a custom `location` for any user.
    public static func resolveScreenshotDirectories() -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL) {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            let key = resolved.path
            guard !seen.contains(key) else { return }
            guard FileManager.default.fileExists(atPath: key) else { return }
            seen.insert(key)
            urls.append(resolved)
        }

        if let custom = screencaptureLocation(), !custom.isEmpty {
            append(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath))
        } else {
            append(fileManagerHomeDesktop())
            let home = FileManager.default.homeDirectoryForCurrentUser
            let iCloudDesktop = home
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Desktop", isDirectory: true)
            append(iCloudDesktop)
        }
        return urls
    }

    /// Temp staging first, then the user's configured save folder.
    private static func resolveWatchDirectories(includingTemporaryStaging: Bool) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL) {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            let key = resolved.path
            guard !seen.contains(key) else { return }
            guard FileManager.default.fileExists(atPath: key) else { return }
            seen.insert(key)
            urls.append(resolved)
        }

        if includingTemporaryStaging {
            // Prefer temp — drag-away captures often never reach the save folder.
            append(temporaryItemsDirectory())
        }
        for directory in resolveScreenshotDirectories() {
            append(directory)
        }
        return urls
    }

    /// Real user-session TemporaryItems (where screencaptureui stages NSIRD folders),
    /// not the app-container tmp when sandboxed.
    private static func temporaryItemsDirectory() -> URL {
        darwinUserTemporaryDirectory().appendingPathComponent("TemporaryItems", isDirectory: true)
    }

    private static func darwinUserTemporaryDirectory() -> URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        if length > 0 {
            let path = String(cString: buffer)
            if !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        if let env = ProcessInfo.processInfo.environment["TMPDIR"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
    }

    private static func fileManagerHomeDesktop() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    private static func screencaptureLocation() -> String? {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !location.isEmpty {
            return location
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.screencapture", "location"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty == false) ? value : nil
        } catch {
            return nil
        }
    }

    nonisolated private static func isScreenshotBundle(_ bundle: String?) -> Bool {
        guard let bundle else { return false }
        return bundle == "com.apple.screencaptureui"
            || bundle == "com.apple.screenshot.system"
            || bundle.hasPrefix("com.apple.screencapture")
    }

    private static func looksLikeScreenshot(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(ext) else { return false }

        let name = url.lastPathComponent
        let needles = [
            "Screenshot",
            "Screen Shot",
            "Screen Recording",
            "Знімок екрана",
            "Знімок",
            "Captura de pantalla",
            "Capture d’écran",
            "Capture d'écran",
            "Bildschirmfoto",
            "Schermata",
            "スクリーンショット"
        ]
        if needles.contains(where: { name.localizedCaseInsensitiveContains($0) }) {
            return true
        }

        if url.path.contains("NSIRD_screencaptureui") {
            return true
        }

        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "name"),
           !custom.isEmpty,
           name.hasPrefix(custom) {
            return true
        }

        return false
    }

    private static func pngData(from data: Data, url: URL) -> Data? {
        if url.pathExtension.lowercased() == "png",
           data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return data
        }
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
