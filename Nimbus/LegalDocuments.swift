import AppKit
import Foundation

enum LegalDocuments: String, CaseIterable, Identifiable, Hashable {
    case privacy = "PRIVACY"
    case terms = "TERMS"
    case security = "SECURITY"
    case license = "LICENSE"

    var id: String { rawValue }
    var filename: String { "\(rawValue).md" }

    func title(using settings: AppSettings) -> String {
        switch self {
        case .privacy: return settings.t(.privacyPolicy)
        case .terms: return settings.t(.termsOfUse)
        case .security: return settings.t(.securityPolicy)
        case .license: return settings.t(.openSourceLicense)
        }
    }

    /// Bundled markdown/plain text for in-app Settings pages.
    static func loadText(_ document: LegalDocuments) -> String {
        let name = document.rawValue
        let urls: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "md"),
            Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Legal")
        ]

        for case let url? in urls {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }

        let fm = FileManager.default
        let candidates = [
            fm.currentDirectoryPath + "/Nimbus/Legal/\(document.filename)",
            fm.currentDirectoryPath + "/\(document.filename)",
            document == .license ? fm.currentDirectoryPath + "/LICENSE" : nil
        ].compactMap { $0 }

        for path in candidates {
            if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                return text
            }
        }

        return "Document unavailable."
    }
}
