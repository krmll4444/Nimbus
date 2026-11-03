import AppKit
import Carbon.HIToolbox

/// Detects ⌘⇧3 / ⌘⇧4 / ⌘⇧5 without consuming them, then pings the watcher.
/// Prefers a global key monitor (Accessibility). Falls back to observing
/// `screencaptureui` which hosts the floating thumbnail.
final class ScreenshotShortcutMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func start() {
        stop()

        let handle: (NSEvent) -> Void = { [weak self] event in
            guard Self.isScreenshotChord(event) else { return }
            self?.handler()
        }

        // Does not swallow the event — system screenshot still works.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
        }
        // When Nimbus is focused (rare for a menu-bar app).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    deinit {
        stop()
    }

    private static func isScreenshotChord(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // ⌘⇧3 / ⌘⇧4 / ⌘⇧5 (with or without Control for clipboard variants)
        let cmdShift = mods.contains(.command) && mods.contains(.shift)
        guard cmdShift else { return false }
        // keyCodes: 3=20, 4=21, 5=23
        return event.keyCode == 20 || event.keyCode == 21 || event.keyCode == 23
    }
}
