import AppKit
import NimbusCore
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var controller: ClipboardController
    @ObservedObject var settings: AppSettings

    var body: some View {
        Button {
            AppDockPolicy.preferAccessoryUnlessSettingsOpen()
            controller.showHistoryPanel()
        } label: {
            Label {
                Text(settings.t(.showHistory))
            } icon: {
                Image("NimbusMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
        }

        Divider()

        Text("\(controller.store.items.count) \(settings.t(.itemsSaved))")

        Button(settings.pauseCapture ? settings.t(.resumeCapture) : settings.t(.pauseCapture)) {
            controller.togglePause()
        }

        if !controller.store.items.filter({ !$0.isPinned }).isEmpty {
            Button(settings.t(.clearHistory), role: .destructive) {
                controller.clearAll()
            }
        }

        Divider()

        SettingsLink {
            Text(settings.t(.settings))
        }

        Button(settings.t(.quit)) {
            NSApplication.shared.terminate(nil)
        }
    }
}
