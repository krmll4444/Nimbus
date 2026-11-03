import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var showOnboarding = false
    @State private var accessibilityTrusted = PasteService.isTrusted
    @State private var legalDocument: LegalDocuments?

    var body: some View {
        Group {
            if let legalDocument {
                LegalDocumentView(document: legalDocument, settings: settings) {
                    self.legalDocument = nil
                }
            } else {
                settingsForm
            }
        }
        .frame(width: 480, height: 580)
        .onAppear {
            accessibilityTrusted = PasteService.isTrusted
            if !settings.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = PasteService.isTrusted
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(settings: settings) {
                showOnboarding = false
            }
        }
    }

    private var settingsForm: some View {
        Form {
            Section {
                PermissionStatusRow(
                    title: settings.t(.clipboardAccess),
                    status: settings.t(.clipboardAccessStatus),
                    statusColor: .secondary,
                    hint: settings.t(.clipboardAccessHint)
                )

                PermissionStatusRow(
                    title: settings.t(.accessibility),
                    status: accessibilityTrusted ? settings.t(.statusOn) : settings.t(.statusOff),
                    statusColor: accessibilityTrusted ? .secondary : .orange,
                    hint: settings.t(.accessibilityHint)
                )

                if !accessibilityTrusted {
                    Button {
                        PasteService.requestAccess()
                        accessibilityTrusted = PasteService.isTrusted
                    } label: {
                        Label(settings.t(.accessibilityNeeded), systemImage: "hand.raised.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        PasteService.revealAppInFinder()
                    } label: {
                        Label(settings.t(.revealInFinder), systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                SettingsActionRow(title: settings.t(.showWelcomeAgain), systemImage: "sparkles") {
                    showOnboarding = true
                }
            } header: {
                Text(settings.t(.permissions))
            } footer: {
                if !accessibilityTrusted {
                    Text(settings.t(.accessibilityMissingBody))
                }
            }

            Section(settings.t(.general)) {
                Picker(settings.t(.language), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language == .system ? settings.t(.followSystem) : language.title)
                            .tag(language)
                    }
                }

                Picker(settings.t(.hotkey), selection: $settings.historyHotkey) {
                    ForEach(HistoryHotkey.allCases) { hotkey in
                        Text(hotkey.display).tag(hotkey)
                    }
                }

                Picker(settings.t(.historyLimit), selection: $settings.maxItems) {
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text("200").tag(200)
                    Text("500").tag(500)
                }

                Toggle(settings.t(.captureScreenshots), isOn: $settings.captureScreenshots)
                Picker(settings.t(.screenshotPreview), selection: $settings.screenshotPreviewStyle) {
                    Text(settings.t(.previewThumbnail)).tag(ScreenshotPreviewStyle.thumbnail)
                    Text(settings.t(.previewFullWidth)).tag(ScreenshotPreviewStyle.fullWidth)
                }
                Toggle(settings.t(.enableOCR), isOn: $settings.enableOCR)
                Toggle(settings.t(.preferPlainText), isOn: $settings.preferPlainTextPaste)
                Toggle(settings.t(.launchAtLogin), isOn: $settings.launchAtLogin)
            }

            Section {
                Toggle(settings.t(.pauseCapture), isOn: $settings.pauseCapture)
            } header: {
                Text(settings.t(.privacy))
            } footer: {
                Text(settings.t(.privacyLocalHint))
            }

            Section(settings.t(.about)) {
                LabeledContent(settings.t(.version), value: AppVersion.displayString)

                SettingsActionRow(title: settings.t(.privacyPolicy)) {
                    legalDocument = .privacy
                }
                SettingsActionRow(title: settings.t(.termsOfUse)) {
                    legalDocument = .terms
                }
                SettingsActionRow(title: settings.t(.securityPolicy)) {
                    legalDocument = .security
                }
                SettingsActionRow(title: settings.t(.openSourceLicense)) {
                    legalDocument = .license
                }
            }
        }
        .formStyle(.grouped)
        .padding(4)
    }
}

/// Title + status + hint in a single Form row (no divider between title and hint).
private struct PermissionStatusRow: View {
    let title: String
    let status: String
    let statusColor: Color
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 8)
                Text(status)
                    .foregroundStyle(statusColor)
            }
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

/// Full-width in-app action row.
private struct SettingsActionRow: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.06 : 0))
        )
        .onHover { hovering = $0 }
    }
}

enum AppVersion {
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var displayString: String {
        "\(marketing) (\(build))"
    }
}
