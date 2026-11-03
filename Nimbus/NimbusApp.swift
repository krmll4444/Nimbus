import AppKit
import SwiftUI

@main
struct NimbusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var clipboard = ClipboardController()
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(controller: clipboard, settings: settings)
        } label: {
            MenuBarLabel()
        }

        Settings {
            SettingsView(settings: settings)
                .onAppear { AppDockPolicy.settingsDidOpen() }
                .onDisappear { AppDockPolicy.settingsDidClose() }
        }
    }
}

/// Template NN mark — system tints it from the menu bar appearance
/// (follows wallpaper brightness behind the bar, not only Light/Dark preference).
private struct MenuBarLabel: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if let image = Self.templateImage {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .accessibilityLabel("Nimbus")
            } else {
                Text("NN")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .accessibilityLabel("Nimbus")
            }
        }
        // Keep this mounted so first-launch / Dock reopen can use openSettings (not showSettingsWindow:).
        .onReceive(NotificationCenter.default.publisher(for: .nimbusOpenSettings)) { _ in
            openSettings()
        }
    }

    private static let templateImage: NSImage? = {
        guard let image = NSImage(named: "MenuBarIcon") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}
