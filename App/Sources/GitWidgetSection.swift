import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// Which repositories the Git widget lists, and what makes one of them "to do".
struct GitWidgetSection: View {
    let store: SettingsStore
    @State private var isNotRepository = false

    private var settings: GitWidgetSettings {
        store.settings.widgets.git
    }

    var body: some View {
        Section(loc("Git widget")) {
            Picker(loc("Repositories"), selection: binding(\.source)) {
                Text(loc("All repositories")).tag(GitWidgetSource.all)
                Text(loc("Same as the Git module")).tag(GitWidgetSource.shared)
                Text(loc("A chosen repository")).tag(GitWidgetSource.own)
            }
            if settings.source == .own {
                LabeledContent {
                    Button(settings.ownRepository == nil ? loc("Choose Folder…") : loc("Change Folder…")) {
                        chooseRepository()
                    }
                } label: {
                    Text(loc("Repository"))
                    if let path = settings.ownRepository {
                        Text(path).lineLimit(1).truncationMode(.middle)
                    }
                }
                if isNotRepository {
                    Text(loc("This folder is not a Git repository."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Picker(loc("Counts as to do"), selection: binding(\.countsAs)) {
                Text(loc("Uncommitted changes")).tag(GitToDo.uncommitted)
                Text(loc("Unpushed commits")).tag(GitToDo.unpushed)
                Text(loc("All changes")).tag(GitToDo.both)
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<GitWidgetSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in store.update { $0.widgets.git[keyPath: keyPath] = value } }
        )
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = loc("Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let folder = url.standardizedFileURL.path
        isNotRepository = !FileManager.default.fileExists(atPath: folder + "/.git")
        guard !isNotRepository else { return }
        store.update { $0.widgets.git.repositoryPath = folder }
    }
}
