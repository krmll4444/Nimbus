import AppKit

extension Notification.Name {
    /// Request opening the Settings scene via SwiftUI `openSettings` (not `showSettingsWindow:`).
    static let nimbusOpenSettings = Notification.Name("nimbus.openSettings")
    /// Dock click / reopen — restore a miniaturized history panel if any.
    static let nimbusDeminiaturizeHistory = Notification.Name("nimbus.deminiaturizeHistory")
}

/// Menu-bar app stays out of the Dock (`LSUIElement` / `.accessory`),
/// except while Settings is open or the history panel is minimized to the Dock.
enum AppDockPolicy {
    private static var observing = false
    private static var historyIsMiniaturized = false

    static func prepareAtLaunch() {
        NSApp.setActivationPolicy(.accessory)
        startObservingIfNeeded()
    }

    static func settingsDidOpen() {
        becomeRegular()
    }

    static func settingsDidClose() {
        DispatchQueue.main.async { syncDockVisibility() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { syncDockVisibility() }
    }

    static func historyMiniaturizedDidChange(_ miniaturized: Bool) {
        historyIsMiniaturized = miniaturized
        if miniaturized {
            becomeRegular()
        } else {
            syncDockVisibility()
        }
    }

    /// Call when showing/hiding the history panel (not when minimized).
    static func preferAccessoryUnlessSettingsOpen() {
        syncDockVisibility()
    }

    static func requestOpenSettings() {
        NotificationCenter.default.post(name: .nimbusOpenSettings, object: nil)
    }

    private static func becomeRegular() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func startObservingIfNeeded() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        let handler: (Notification) -> Void = { _ in
            DispatchQueue.main.async { syncDockVisibility() }
        }
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: nil, using: handler)
        center.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: nil, using: handler)
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: nil, using: handler)
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil, using: handler)
    }

    private static func syncDockVisibility() {
        if historyIsMiniaturized || hasVisibleSettingsWindow() {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
        } else if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private static func hasVisibleSettingsWindow() -> Bool {
        NSApp.windows.contains { isSettingsWindow($0) }
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible else { return false }
        if window is NSPanel { return false }
        let className = String(describing: type(of: window))
        if className.localizedCaseInsensitiveContains("StatusBar")
            || className.localizedCaseInsensitiveContains("MenuBar")
            || className.localizedCaseInsensitiveContains("Popup") {
            return false
        }
        let title = window.title.lowercased()
        if title.contains("settings")
            || title.contains("preferences")
            || title.contains("налаштування") {
            return true
        }
        return window.styleMask.contains(.titled)
            && window.styleMask.contains(.closable)
            && window.level == .normal
            && !window.isFloatingPanel
    }

}

