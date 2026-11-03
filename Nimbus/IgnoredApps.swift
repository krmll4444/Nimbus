import Foundation

enum IgnoredApps {
    /// Sensible defaults — password managers & similar.
    static let defaults: [String] = [
        "com.1password.1password",
        "com.1password.1password-launcher",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.lastpass.LastPass",
        "com.bitwarden.desktop",
        "com.dashlane.dashlanephonefinal",
        "com.apple.keychainaccess",
        "com.keepassxc.keepassxc"
    ]
}
