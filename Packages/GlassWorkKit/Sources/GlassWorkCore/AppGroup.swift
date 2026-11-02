import Foundation

/// Location of the data shared between the app and its widget extension.
public enum AppGroup {
    /// Info.plist key that holds the App Group identifier (set from build settings).
    public static let infoKey = "GWAppGroupID"

    /// The App Group identifier of the running bundle, if any.
    public static var identifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
              !value.isEmpty, !value.hasPrefix("$(")
        else { return nil }
        return value
    }

    /// Shared container. Falls back to Application Support for unsigned builds and tests.
    public static var containerURL: URL {
        if let identifier,
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        {
            return url
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "GlassWork", directoryHint: .isDirectory)
    }
}
