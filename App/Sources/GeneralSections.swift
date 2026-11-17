import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// The language macOS started the app with, read before the override is written.
enum LaunchLanguage {
    static let value = LanguageOverride.stored()
}

extension AppModel {
    /// Hands the language, clock and week choices to the formatters, and the language to macOS.
    func applyRegional() {
        _ = LaunchLanguage.value
        RegionalFormat.apply(store.settings.regional)
        LanguageOverride.apply(store.settings.regional.language)
    }
}

/// The General page's language and time choices.
struct GeneralRegionalSection: View {
    let store: SettingsStore
    var body: some View {
        RegionalSection(
            settings: Binding(
                get: { store.settings.regional },
                set: { value in store.update { $0.regional = value } }
            ),
            runningLanguage: LaunchLanguage.value
        )
    }
}

/// The General page's view of the background rebuild. It reads files and never runs the script.
struct GeneralUpdatesSection: View {
    @State private var status = Self.read()

    var body: some View {
        AutoUpdateSection(
            status: status,
            hasLog: FileManager.default.fileExists(atPath: AutoUpdate.logURL().path(percentEncoded: false)),
            viewLog: {
                NSWorkspace.shared.open(AutoUpdate.logURL())
            }
        )
        .onAppear { status = Self.read() }
    }

    private static func read() -> AutoUpdateStatus {
        let manager = FileManager.default
        let installed = manager.fileExists(atPath: AutoUpdate.agentURL().path(percentEncoded: false))
        let stamp = try? manager.attributesOfItem(atPath: AutoUpdate.stampURL().path(percentEncoded: false))
        return AutoUpdate.status(isInstalled: installed, lastBuild: stamp?[.modificationDate] as? Date)
    }
}
