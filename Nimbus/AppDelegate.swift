import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDockPolicy.prepareAtLaunch()

        // First launch: ask SwiftUI to open Settings (SettingsLink / openSettings — no showSettingsWindow:).
        if !AppSettings.shared.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                AppDockPolicy.requestOpenSettings()
            }
        }
    }

    /// Dock click: restore miniaturized history, or open Settings if nothing else is up.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let miniaturizedHistory = NSApp.windows.contains { window in
            window is NSPanel && window.isMiniaturized
        }
        if miniaturizedHistory {
            NotificationCenter.default.post(name: .nimbusDeminiaturizeHistory, object: nil)
            return true
        }
        if !flag {
            AppDockPolicy.requestOpenSettings()
        }
        return true
    }
}
