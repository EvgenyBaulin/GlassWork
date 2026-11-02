import GlassWorkCore
import SwiftUI

struct StatusMenu: View {
    let heartbeat: HeartbeatWriter
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GlassWork").font(.headline)
            if let boot = SystemClock.bootTime() {
                Text("Uptime \(CompactDuration.format(Date().timeIntervalSince(boot)))")
                    .monospacedDigit()
            }
            if let error = heartbeat.lastError {
                Text(error).foregroundStyle(.red).font(.caption)
            }
            Divider()
            Button("Settings…") {
                NSApp.activate()
                openSettings()
            }
            .keyboardShortcut(",")
            Button("Quit GlassWork") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 240, alignment: .leading)
    }
}
