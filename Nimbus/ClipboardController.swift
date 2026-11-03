import AppKit
import Combine
import NimbusCore
import SwiftUI

@MainActor
final class ClipboardController: ObservableObject {
    let store: ClipboardStore
    private let monitor: ClipboardMonitor
    private let screenshots: ScreenshotWatcher
    private let settings: AppSettings
    private var panel: HistoryPanelController?
    private var hotkey: HotkeyMonitor?
    private var screenshotShortcuts: ScreenshotShortcutMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var ocrTasks: [UUID: Task<Void, Never>] = [:]
    /// IDs currently shown in the history panel (respects search/filters).
    var visibleItemIDs: [UUID] = []

    init(settings: AppSettings? = nil) {
        let settings = settings ?? AppSettings.shared
        let store = ClipboardStore()
        let monitor = ClipboardMonitor()
        let screenshots = ScreenshotWatcher()
        self.store = store
        self.monitor = monitor
        self.screenshots = screenshots
        self.settings = settings

        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        monitor.shouldCapture = { [weak self] in
            !(self?.settings.pauseCapture ?? false)
        }
        monitor.isAppIgnored = { [weak self] bundleID in
            self?.settings.isIgnored(bundleID: bundleID) ?? false
        }
        monitor.onChange = { [weak self] snapshot in
            self?.store.ingest(snapshot)
        }
        store.onInternalPasteboardWrite = { [weak self] in
            self?.monitor.ignoreCurrentPasteboard()
        }
        store.onImageIngested = { [weak self] item, data in
            self?.runOCRIfNeeded(for: item, data: data)
        }
        screenshots.onCapture = { [weak self] data in
            guard let self else { return }
            guard self.settings.captureScreenshots, !self.settings.pauseCapture else { return }
            self.store.ingest(ClipboardSnapshot(payload: .image(data)))
        }

        monitor.start()
        if settings.captureScreenshots {
            screenshots.start()
            installScreenshotShortcuts()
        }
        installHotkey(settings.historyHotkey)

        settings.$historyHotkey
            .dropFirst()
            .sink { [weak self] hotkey in self?.installHotkey(hotkey) }
            .store(in: &cancellables)

        settings.$captureScreenshots
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.screenshots.start()
                    self.installScreenshotShortcuts()
                } else {
                    self.screenshots.stop()
                    self.screenshotShortcuts?.stop()
                    self.screenshotShortcuts = nil
                }
            }
            .store(in: &cancellables)

        settings.$maxItems
            .sink { [weak self] limit in self?.store.maxItemsLimit = limit }
            .store(in: &cancellables)

        settings.$pauseCapture
            .dropFirst()
            .sink { [weak self] paused in
                guard let self else { return }
                if paused {
                    self.screenshots.stop()
                } else if self.settings.captureScreenshots {
                    self.screenshots.start()
                }
            }
            .store(in: &cancellables)
    }

    func toggleHistoryPanel() {
        if panel == nil { panel = HistoryPanelController(controller: self) }
        panel?.toggle()
    }

    func showHistoryPanel() {
        if panel == nil { panel = HistoryPanelController(controller: self) }
        panel?.show()
    }

    func hideHistoryPanel() {
        panel?.hide()
    }

    func copy(_ item: ClipboardItem) {
        store.copyToPasteboard(item, plainText: false)
        hideHistoryPanel()
    }

    func paste(_ item: ClipboardItem, plainText: Bool? = nil) {
        let plain = plainText ?? settings.preferPlainTextPaste
        store.copyToPasteboard(item, plainText: plain)
        hideHistoryPanel()
        PasteService.pasteCommandV()
    }

    func pasteByIndex(_ index: Int) {
        let ids = visibleItemIDs.isEmpty ? store.items.map(\.id) : visibleItemIDs
        guard index >= 0, index < ids.count else { return }
        guard let item = store.items.first(where: { $0.id == ids[index] }) else { return }
        paste(item)
    }

    func togglePin(_ item: ClipboardItem) {
        store.togglePin(item)
    }

    @discardableResult
    func updateText(_ item: ClipboardItem, text: String) -> Bool {
        store.updateText(for: item.id, text: text)
    }

    func delete(_ item: ClipboardItem) {
        ocrTasks[item.id]?.cancel()
        ocrTasks[item.id] = nil
        store.delete(item)
    }

    func clearAll() {
        store.clearAll(keepingPinned: true)
    }

    func togglePause() {
        settings.pauseCapture.toggle()
    }

    private func runOCRIfNeeded(for item: ClipboardItem, data: Data) {
        guard settings.enableOCR, item.type == .image else { return }
        ocrTasks[item.id]?.cancel()
        let id = item.id
        ocrTasks[id] = Task { [weak self] in
            let text = await OCRService.recognizeText(in: data)
            guard let text, !Task.isCancelled else { return }
            await MainActor.run {
                self?.store.updateOCRText(for: id, text: text)
                self?.ocrTasks[id] = nil
            }
        }
    }

    private func installHotkey(_ preset: HistoryHotkey) {
        hotkey?.stop()
        hotkey = HotkeyMonitor(keyCode: preset.keyCode, modifiers: preset.modifiers) { [weak self] in
            self?.toggleHistoryPanel()
        }
        hotkey?.start()
    }

    private func installScreenshotShortcuts() {
        screenshotShortcuts?.stop()
        screenshotShortcuts = ScreenshotShortcutMonitor { [weak self] in
            self?.screenshots.pingAggressiveCapture()
        }
        screenshotShortcuts?.start()
    }
}
