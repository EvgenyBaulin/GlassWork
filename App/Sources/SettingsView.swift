import GlassWorkCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Menu Bar", systemImage: "menubar.rectangle") {
                placeholder
            }
            Tab("Widgets", systemImage: "square.grid.2x2") {
                placeholder
            }
            Tab("Dock", systemImage: "dock.rectangle") {
                placeholder
            }
            Tab("General", systemImage: "gearshape") {
                Form {
                    LabeledContent("Shared data", value: AppGroup.containerURL.path(percentEncoded: false))
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 560, height: 380)
    }

    private var placeholder: some View {
        ContentUnavailableView("Coming soon", systemImage: "hammer")
    }
}
