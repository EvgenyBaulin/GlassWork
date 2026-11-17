import Foundation

/// The app's own language, kept where macOS looks for it: `AppleLanguages` in the app's defaults.
/// It takes effect the next time the app starts.
public enum LanguageOverride {
    private static let key = "AppleLanguages"

    /// What the app's own domain holds. `standard.array(forKey:)` would also see the system list,
    /// which would make every Mac look like it had an override.
    public static func stored(
        defaults: UserDefaults = .standard,
        domain: String = Bundle.main.bundleIdentifier ?? ""
    ) -> AppLanguage {
        let languages = defaults.persistentDomain(forName: domain)?[key] as? [String]
        let code = languages?.first.map { String($0.prefix(2)) }
        return AppLanguage(languageCode: code)
    }

    public static func apply(
        _ language: AppLanguage,
        defaults: UserDefaults = .standard,
        domain: String = Bundle.main.bundleIdentifier ?? ""
    ) {
        guard stored(defaults: defaults, domain: domain) != language else { return }
        if let code = language.languageCode {
            defaults.set([code], forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
