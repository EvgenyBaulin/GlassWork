import GlassWorkCore
import GlassWorkUI
import ServiceManagement
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

/// Four steps with Skip: welcome, what to enable, permissions, done.
struct WelcomeView: View {
    let store: SettingsStore
    let finish: () -> Void
    @State private var step = 0
    @State private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            content
            Spacer()
            HStack {
                Button(loc("Skip")) { complete() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button(step == 3 ? loc("Done") : loc("Continue")) { advance() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520, height: 380)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            Text(loc("Welcome to GlassWork")).font(.largeTitle.weight(.semibold))
            Text(loc("Live figures in your menu bar, with everything else one click away in the Hub."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        case 1:
            Text(loc("What to enable")).font(.title.weight(.semibold))
            Text(loc("Overview, CPU and Memory start in the menu bar. Everything else waits in the Hub."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        case 2:
            Text(loc("Permissions")).font(.title.weight(.semibold))
            Text(loc("Nothing is needed now. Each module asks for access only when you turn it on."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        default:
            Text(loc("All set")).font(.title.weight(.semibold))
            Toggle(loc("Launch at login"), isOn: $launchAtLogin).toggleStyle(.checkbox)
        }
    }

    private func advance() {
        if step == 3 {
            complete()
        } else {
            step += 1
        }
    }

    private func complete() {
        if launchAtLogin {
            try? SMAppService.mainApp.register()
        }
        store.update { $0.welcomeCompleted = true }
        finish()
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
        case .other: loc("Settings")
        }
    }
}
