import AppKit
import SwiftUI

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private weak var controller: ClipboardController?
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var deminiaturizeObserver: NSObjectProtocol?

    init(controller: ClipboardController) {
        self.controller = controller
        super.init()
        deminiaturizeObserver = NotificationCenter.default.addObserver(
            forName: .nimbusDeminiaturizeHistory,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.restoreFromDockIfNeeded()
            }
        }
    }

    deinit {
        if let deminiaturizeObserver {
            NotificationCenter.default.removeObserver(deminiaturizeObserver)
        }
    }

    func toggle() {
        if panel?.isMiniaturized == true {
            restoreFromDockIfNeeded()
        } else if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let controller else { return }
        if panel == nil {
            panel = makePanel(controller: controller)
        }
        if panel?.isMiniaturized == true {
            panel?.deminiaturize(nil)
            AppDockPolicy.historyMiniaturizedDidChange(false)
        }
        // Visible floating panel should not keep a Dock icon (unless Settings is open).
        AppDockPolicy.preferAccessoryUnlessSettingsOpen()
        positionNearMouseOrCenter()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        if panel?.isMiniaturized == true {
            panel?.deminiaturize(nil)
            AppDockPolicy.historyMiniaturizedDidChange(false)
        }
        panel?.orderOut(nil)
        removeKeyMonitor()
        AppDockPolicy.preferAccessoryUnlessSettingsOpen()
    }

    private func restoreFromDockIfNeeded() {
        guard let panel, panel.isMiniaturized else { return }
        panel.deminiaturize(nil)
        AppDockPolicy.historyMiniaturizedDidChange(false)
        show()
    }

    private func makePanel(controller: ClipboardController) -> NSPanel {
        let root = HistoryPanel(controller: controller)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 580)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.title = "Nimbus"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Avoid `.transient` (blocks Dock miniaturize).
        // Do not combine `.canJoinAllSpaces` with `.moveToActiveSpace` — AppKit throws.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.miniwindowTitle = "Nimbus"
        panel.delegate = self
        // Use asset-catalog AppIcon (with margins), not full-bleed NimbusMark.
        panel.miniwindowImage = NSImage(named: "AppIcon")
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = false
        panel.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        return panel
    }

    // MARK: - NSWindowDelegate

    func windowDidMiniaturize(_ notification: Notification) {
        AppDockPolicy.historyMiniaturizedDidChange(true)
        removeKeyMonitor()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        AppDockPolicy.historyMiniaturizedDidChange(false)
        installKeyMonitor()
        AppDockPolicy.preferAccessoryUnlessSettingsOpen()
    }

    func windowWillClose(_ notification: Notification) {
        if panel?.isMiniaturized == true {
            AppDockPolicy.historyMiniaturizedDidChange(false)
        }
        AppDockPolicy.preferAccessoryUnlessSettingsOpen()
    }

    private func positionNearMouseOrCenter() {
        guard let panel, !panel.isMiniaturized else { return }
        if let screen = NSScreen.main {
            let mouse = NSEvent.mouseLocation
            var origin = NSPoint(x: mouse.x - panel.frame.width / 2, y: mouse.y - panel.frame.height - 12)
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 12), visible.maxX - panel.frame.width - 12)
            origin.y = min(max(origin.y, visible.minY + 12), visible.maxY - panel.frame.height - 12)
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }
            let digitKeys: [UInt16: Int] = [
                18: 0, 19: 1, 20: 2, 21: 3, 23: 4,
                22: 5, 26: 6, 28: 7, 25: 8
            ]
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods.isEmpty, let index = digitKeys[event.keyCode] {
                self?.controller?.pasteByIndex(index)
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}
