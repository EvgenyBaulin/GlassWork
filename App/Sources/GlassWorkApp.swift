import GlassWorkCore
import SwiftUI

@main
struct GlassWorkApp: App {
    @State private var heartbeat = HeartbeatWriter()

    var body: some Scene {
        MenuBarExtra("GlassWork", systemImage: "square.grid.2x2") {
            StatusMenu(heartbeat: heartbeat)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
