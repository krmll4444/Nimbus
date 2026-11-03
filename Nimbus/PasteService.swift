import AppKit
import ApplicationServices

enum PasteService {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Path of the running app bundle (for “+” in Accessibility when the list is empty).
    static var runningAppURL: URL {
        Bundle.main.bundleURL
    }

    /// Registers Nimbus with TCC (so it can appear in the Accessibility list), shows the
    /// system prompt when macOS allows it, then opens System Settings → Accessibility.
    static func requestAccess() {
        // Accessory / LSUIElement apps often never show the AX dialog unless briefly `.regular`.
        let restoreAccessory = NSApp.activationPolicy() == .accessory
        if restoreAccessory {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        // Opening Settings alone does NOT add the app — TCC registration above does.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            openAccessibilitySettings()
            if restoreAccessory {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    AppDockPolicy.preferAccessoryUnlessSettingsOpen()
                }
            }
        }
    }

    static func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        ]

        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([runningAppURL])
    }

    /// Hides our UI, then synthesizes ⌘V into the previously frontmost app.
    static func pasteCommandV() {
        guard isTrusted else {
            requestAccess()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let source = CGEventSource(stateID: .hidSystemState)

            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
