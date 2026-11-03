import AppKit
import Combine
import ServiceManagement
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case ukrainian
    case spanish
    case polish
    case czech
    case slovak
    case hungarian
    case german
    case french

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .ukrainian: return "Українська"
        case .spanish: return "Español"
        case .polish: return "Polski"
        case .czech: return "Čeština"
        case .slovak: return "Slovenčina"
        case .hungarian: return "Magyar"
        case .german: return "Deutsch"
        case .french: return "Français"
        }
    }

    var code: String {
        switch self {
        case .system:
            return Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "en"
        case .english: return "en"
        case .ukrainian: return "uk"
        case .spanish: return "es"
        case .polish: return "pl"
        case .czech: return "cs"
        case .slovak: return "sk"
        case .hungarian: return "hu"
        case .german: return "de"
        case .french: return "fr"
        }
    }

    var resolvedCode: String { code }
}

enum HistoryHotkey: String, CaseIterable, Identifiable {
    case commandShiftV
    case commandShiftC
    case optionCommandV
    case controlCommandV

    var id: String { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .commandShiftV, .optionCommandV, .controlCommandV: return 9
        case .commandShiftC: return 8
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .commandShiftV: return [.command, .shift]
        case .commandShiftC: return [.command, .shift]
        case .optionCommandV: return [.option, .command]
        case .controlCommandV: return [.control, .command]
        }
    }

    var display: String {
        switch self {
        case .commandShiftV: return "⌘⇧V"
        case .commandShiftC: return "⌘⇧C"
        case .optionCommandV: return "⌥⌘V"
        case .controlCommandV: return "⌃⌘V"
        }
    }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case link
    case image
    case pinned

    var id: String { rawValue }
}

enum ScreenshotPreviewStyle: String, CaseIterable, Identifiable {
    case thumbnail
    case fullWidth

    var id: String { rawValue }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var historyHotkey: HistoryHotkey {
        didSet { defaults.set(historyHotkey.rawValue, forKey: Keys.historyHotkey) }
    }

    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Keys.maxItems) }
    }

    @Published var captureScreenshots: Bool {
        didSet { defaults.set(captureScreenshots, forKey: Keys.captureScreenshots) }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin(launchAtLogin) }
    }

    @Published var pauseCapture: Bool {
        didSet { defaults.set(pauseCapture, forKey: Keys.pauseCapture) }
    }

    @Published var enableOCR: Bool {
        didSet { defaults.set(enableOCR, forKey: Keys.enableOCR) }
    }

    @Published var preferPlainTextPaste: Bool {
        didSet { defaults.set(preferPlainTextPaste, forKey: Keys.preferPlainTextPaste) }
    }

    @Published var screenshotPreviewStyle: ScreenshotPreviewStyle {
        didSet { defaults.set(screenshotPreviewStyle.rawValue, forKey: Keys.screenshotPreviewStyle) }
    }

    @Published var ignoredAppBundleIDs: [String] {
        didSet { defaults.set(ignoredAppBundleIDs, forKey: Keys.ignoredApps) }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let language = "settings.language"
        static let historyHotkey = "settings.historyHotkey"
        static let maxItems = "settings.maxItems"
        static let captureScreenshots = "settings.captureScreenshots"
        static let launchAtLogin = "settings.launchAtLogin"
        static let pauseCapture = "settings.pauseCapture"
        static let enableOCR = "settings.enableOCR"
        static let preferPlainTextPaste = "settings.preferPlainTextPaste"
        static let screenshotPreviewStyle = "settings.screenshotPreviewStyle"
        static let ignoredApps = "settings.ignoredApps"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        historyHotkey = HistoryHotkey(rawValue: defaults.string(forKey: Keys.historyHotkey) ?? "") ?? .commandShiftV
        maxItems = (defaults.object(forKey: Keys.maxItems) as? Int) ?? 100
        captureScreenshots = defaults.object(forKey: Keys.captureScreenshots) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        pauseCapture = defaults.object(forKey: Keys.pauseCapture) as? Bool ?? false
        enableOCR = defaults.object(forKey: Keys.enableOCR) as? Bool ?? true
        preferPlainTextPaste = defaults.object(forKey: Keys.preferPlainTextPaste) as? Bool ?? false
        screenshotPreviewStyle = ScreenshotPreviewStyle(
            rawValue: defaults.string(forKey: Keys.screenshotPreviewStyle) ?? ""
        ) ?? .thumbnail
        ignoredAppBundleIDs = defaults.stringArray(forKey: Keys.ignoredApps) ?? IgnoredApps.defaults
        hasCompletedOnboarding = defaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool ?? false
    }

    func t(_ key: L10n.Key) -> String {
        L10n.string(key, language: language)
    }

    func isIgnored(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return ignoredAppBundleIDs.contains(bundleID)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.launchAtLogin)
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {}
    }
}

enum L10n {
    enum Key: String {
        case showHistory, settings, quit, itemsSaved, clearHistory, clear, clearAll
        case clearAllTitle, clearAllMessage
        case searchHistory, clipboardEmpty, clipboardEmptyHint
        case general, language, hotkey, historyLimit, captureScreenshots, launchAtLogin, followSystem
        case pauseCapture, resumeCapture, privacy, enableOCR, preferPlainText
        case paste, pastePlain, copy, pin, unpin, delete, edit, save, cancel
        case filterAll, filterText, filterLinks, filterImages, filterPinned
        case accessibilityNeeded, capturePaused
        case screenshotPreview, previewThumbnail, previewFullWidth
        case editItem, deleteConfirm
        case about, version, back
        case permissions, accessibility, clipboardAccess, clipboardAccessStatus, clipboardAccessHint
        case accessibilityHint, accessibilityGranted, statusOn, statusOff
        case accessibilityMissingTitle, accessibilityMissingBody, revealInFinder
        case privacyPolicy, termsOfUse, securityPolicy, openSourceLicense, privacyLocalHint
        case showWelcomeAgain
        case onboardingTitle, onboardingSubtitle, onboardingContinue
        case onboardingClipboardTitle, onboardingClipboardBody
        case onboardingAccessibilityTitle, onboardingAccessibilityBody
        case onboardingLocalTitle, onboardingLocalBody
    }

    private static let en: [Key: String] = [
        .showHistory: "Show History",
        .settings: "Settings…",
        .quit: "Quit Nimbus",
        .itemsSaved: "items saved",
        .clearHistory: "Clear History",
        .clear: "Clear",
        .clearAll: "Clear All",
        .clearAllTitle: "Clear history?",
        .clearAllMessage: "Unpinned items will be removed from history and local storage. Pinned items stay.",
        .searchHistory: "Search history",
        .clipboardEmpty: "Clipboard is empty",
        .clipboardEmptyHint: "Copy text, links or screenshots — Nimbus keeps them.",
        .general: "General",
        .language: "Language",
        .hotkey: "History hotkey",
        .historyLimit: "History limit",
        .captureScreenshots: "Capture screenshots from disk",
        .launchAtLogin: "Launch at login",
        .followSystem: "System",
        .pauseCapture: "Pause capture",
        .resumeCapture: "Resume capture",
        .privacy: "Privacy",
        .enableOCR: "OCR text in screenshots",
        .preferPlainText: "Prefer plain text paste",
        .paste: "Paste",
        .pastePlain: "Paste as Plain Text",
        .copy: "Copy",
        .pin: "Pin",
        .unpin: "Unpin",
        .delete: "Delete",
        .edit: "Edit",
        .save: "Save",
        .cancel: "Cancel",
        .editItem: "Edit text",
        .deleteConfirm: "Delete from history",
        .filterAll: "All",
        .filterText: "Text",
        .filterLinks: "Links",
        .filterImages: "Images",
        .filterPinned: "Pinned",
        .accessibilityNeeded: "Allow Accessibility for Paste",
        .capturePaused: "Capture paused",
        .screenshotPreview: "Screenshot preview",
        .previewThumbnail: "Small thumbnail",
        .previewFullWidth: "Full card width",
        .about: "About",
        .version: "Version",
        .back: "Back",
        .permissions: "Permissions",
        .accessibility: "Accessibility",
        .clipboardAccess: "Clipboard",
        .clipboardAccessStatus: "Used for history",
        .clipboardAccessHint: "Nimbus reads items you copy and stores them locally on this Mac.",
        .accessibilityHint: "Needed only for Paste into other apps (⌘V). Copy and history work without it.",
        .accessibilityGranted: "Accessibility is allowed",
        .accessibilityMissingTitle: "Add Nimbus in Accessibility",
        .accessibilityMissingBody: "If Nimbus is not in the list, click + in System Settings, choose the Nimbus app (Reveal in Finder helps), then turn the toggle on.",
        .revealInFinder: "Reveal Nimbus in Finder",
        .statusOn: "On",
        .statusOff: "Off",
        .privacyPolicy: "Privacy Policy",
        .termsOfUse: "Terms of Use",
        .securityPolicy: "Security Policy",
        .openSourceLicense: "Open Source License (MIT)",
        .privacyLocalHint: "History stays on this Mac. Pause capture anytime for sensitive work.",
        .showWelcomeAgain: "Show welcome again…",
        .onboardingTitle: "Welcome to Nimbus",
        .onboardingSubtitle: "A local clipboard history for text, links, and screenshots.",
        .onboardingContinue: "Continue",
        .onboardingClipboardTitle: "Clipboard history",
        .onboardingClipboardBody: "When you copy something, Nimbus keeps a local copy so you can find it later.",
        .onboardingAccessibilityTitle: "Accessibility (optional)",
        .onboardingAccessibilityBody: "Allow Accessibility if you want one-click Paste into other apps. You can skip this and still use history.",
        .onboardingLocalTitle: "Private by design",
        .onboardingLocalBody: "No account and no cloud sync in this build. Read the Privacy Policy for details."
    ]

    private static let uk: [Key: String] = [
        .showHistory: "Показати історію",
        .settings: "Налаштування…",
        .quit: "Вийти з Nimbus",
        .itemsSaved: "збережено",
        .clearHistory: "Очистити історію",
        .clear: "Очистити",
        .clearAll: "Clear All",
        .clearAllTitle: "Очистити історію?",
        .clearAllMessage: "Незакріплені елементи зникнуть з історії та локального сховища. Закріплені залишаться.",
        .searchHistory: "Пошук в історії",
        .clipboardEmpty: "Буфер порожній",
        .clipboardEmptyHint: "Копіюй текст, лінки або скріни — Nimbus їх збереже.",
        .general: "Загальні",
        .language: "Мова",
        .hotkey: "Шорткат історії",
        .historyLimit: "Ліміт історії",
        .captureScreenshots: "Зберігати скріншоти з диска",
        .launchAtLogin: "Запускати разом із macOS",
        .followSystem: "Як у системі",
        .pauseCapture: "Пауза захоплення",
        .resumeCapture: "Відновити захоплення",
        .privacy: "Приватність",
        .enableOCR: "OCR тексту зі скрінів",
        .preferPlainText: "Вставляти як звичайний текст",
        .paste: "Вставити",
        .pastePlain: "Вставити як текст",
        .copy: "Копіювати",
        .pin: "Закріпити",
        .unpin: "Відкріпити",
        .delete: "Видалити",
        .edit: "Редагувати",
        .save: "Зберегти",
        .cancel: "Скасувати",
        .editItem: "Редагувати текст",
        .deleteConfirm: "Видалити з історії",
        .filterAll: "Усе",
        .filterText: "Текст",
        .filterLinks: "Лінки",
        .filterImages: "Скріни",
        .filterPinned: "Закріплені",
        .accessibilityNeeded: "Дозволь Accessibility для Paste",
        .capturePaused: "Захоплення на паузі",
        .screenshotPreview: "Прев’ю скріншота",
        .previewThumbnail: "Маленький thumbnail",
        .previewFullWidth: "На всю ширину картки",
        .about: "Про застосунок",
        .version: "Версія",
        .back: "Назад",
        .permissions: "Дозволи",
        .accessibility: "Accessibility",
        .clipboardAccess: "Буфер обміну",
        .clipboardAccessStatus: "Для історії",
        .clipboardAccessHint: "Nimbus читає те, що ти копіюєш, і зберігає локально на цьому Mac.",
        .accessibilityHint: "Потрібен лише для Paste в інші програми (⌘V). Історія й Copy працюють без нього.",
        .accessibilityGranted: "Accessibility дозволено",
        .accessibilityMissingTitle: "Додай Nimbus у Accessibility",
        .accessibilityMissingBody: "Якщо Nimbus немає в списку — натисни + у System Settings, вибери Nimbus (Reveal in Finder допоможе), увімкни тумблер.",
        .revealInFinder: "Показати Nimbus у Finder",
        .statusOn: "Увімкнено",
        .statusOff: "Вимкнено",
        .privacyPolicy: "Політика конфіденційності",
        .termsOfUse: "Умови використання",
        .securityPolicy: "Політика безпеки",
        .openSourceLicense: "Ліцензія (MIT)",
        .privacyLocalHint: "Історія лишається на цьому Mac. Для чутливих даних увімкни паузу захоплення.",
        .showWelcomeAgain: "Показати вітання знову…",
        .onboardingTitle: "Вітаємо в Nimbus",
        .onboardingSubtitle: "Локальна історія буфера: текст, лінки та скріншоти.",
        .onboardingContinue: "Продовжити",
        .onboardingClipboardTitle: "Історія буфера",
        .onboardingClipboardBody: "Коли ти щось копіюєш, Nimbus зберігає локальну копію, щоб знайти її пізніше.",
        .onboardingAccessibilityTitle: "Accessibility (необов’язково)",
        .onboardingAccessibilityBody: "Дозволь Accessibility, якщо хочеш Paste в інші програми в один клік. Можна пропустити — історія все одно працює.",
        .onboardingLocalTitle: "Приватність за замовчуванням",
        .onboardingLocalBody: "Без акаунта і без хмарної синхронізації в цій збірці. Деталі — у Політиці конфіденційності."
    ]

    static func string(_ key: Key, language: AppLanguage) -> String {
        let code = language.resolvedCode
        if code.hasPrefix("uk") { return uk[key] ?? en[key] ?? key.rawValue }
        return en[key] ?? key.rawValue
    }
}
