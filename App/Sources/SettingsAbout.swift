import GlassWorkCore
import GlassWorkUI
import SwiftUI

struct AboutPane: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("GlassWork").font(.largeTitle.weight(.semibold))
            Text(loc("Version \(version)")).foregroundStyle(.secondary)
            Link(
                "github.com/EvgenyBaulin/GlassWork",
                destination: URL(string: "https://github.com/EvgenyBaulin/GlassWork")!
            )
            Text(loc("MIT License")).foregroundStyle(.secondary)
        }
    }
}

@MainActor
extension SettingsChange {
    /// What the toast names after an undo or redo.
    var title: String {
        if let module {
            return module.title
        }
        return switch area {
        case .modules: loc("Module settings")
        case .numberStyle: loc("Number style")
        case .hiding: loc("Hiding")
        case .alerts: loc("Alerts")
        case .widgets: loc("Widgets")
        case .personalWidgets: loc("Personal widgets")
        case .dock: loc("Dock")
        case .weather: loc("Weather")
        case .rates: loc("Rates")
        case .clipboard: loc("Clipboard")
        case .fans: loc("Fans")
        case .windowTiles: loc("Window Tiles")
        case .hub: loc("Hub")
        case .island: loc("Island")
        case .diagnosticLog: loc("Diagnostic log")
        case .shortcuts: loc("Shortcuts")
        case .regional: loc("Language and time")
        case .other: loc("Settings")
        }
    }
}
