import AppKit
import GlassWorkCore
import SwiftUI

/// The user's commands: run one, or change it. A command marked "ask first" asks here, which is also the only
/// place it can run from: a widget has no way to put the question.
public struct CommandsSection: View {
    private let store: SettingsStore
    private let activity: ActivityStore
    @State private var selected: UUID?
    @State private var confirming: UserCommand?

    public init(store: SettingsStore, activity: ActivityStore) {
        self.init(store: store, activity: activity, selected: nil)
    }

    init(store: SettingsStore, activity: ActivityStore, selected: UUID?) {
        self.store = store
        self.activity = activity
        _selected = State(initialValue: selected)
    }

    private var commands: [UserCommand] {
        store.settings.widgets.commands
    }

    public var body: some View {
        Section(loc("Commands")) {
            ForEach(commands) { row($0) }
            HStack {
                Button(loc("Add"), action: add)
                Button(loc("Remove"), action: remove).disabled(selected == nil)
                Spacer()
            }
        }
        .confirmationDialog(
            confirming.map { loc("Run “\($0.name)”?") } ?? "",
            isPresented: Binding(get: { confirming != nil }, set: {
                if !$0 {
                    confirming = nil
                }
            }),
            presenting: confirming
        ) { command in
            Button(loc("Run")) { start(command) }
            Button(loc("Cancel"), role: .cancel) {}
        } message: { command in
            Text(verbatim: [command.command, command.directory].compactMap(\.self).joined(separator: "\n"))
        }
        if let index = commands.firstIndex(where: { $0.id == selected }) {
            CommandEditor(store: store, index: index)
        }
    }

    private func row(_ command: UserCommand) -> some View {
        HStack(spacing: 8) {
            Button {
                selected = selected == command.id ? nil : command.id
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(command.name.isEmpty ? loc("Untitled") : command.name)
                        .fontWeight(selected == command.id ? .semibold : .regular)
                    caption(command)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if activity.running.contains(command.id) {
                ProgressView().controlSize(.small)
            } else {
                Button(loc("Run")) { run(command) }
                    .disabled(command.command.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func caption(_ command: UserCommand) -> some View {
        if let result = activity.commandResults[command.id] {
            Text(loc("Exit \(Int(result.status)) · \(CompactDuration.format(result.duration))"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(result.status == 0 ? Palette.green : Palette.red)
        } else {
            Text(verbatim: command.command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func run(_ command: UserCommand) {
        if command.asksFirst {
            confirming = command
        } else {
            start(command)
        }
    }

    private func start(_ command: UserCommand) {
        Task { await activity.run(command) }
    }

    private func add() {
        let command = UserCommand(name: loc("New command"), command: "")
        store.update { $0.widgets.commands.append(command) }
        selected = command.id
    }

    private func remove() {
        store.update { settings in settings.widgets.commands.removeAll { $0.id == selected } }
        selected = nil
    }
}

/// The fields of one command.
private struct CommandEditor: View {
    let store: SettingsStore
    let index: Int

    private func binding<Value>(_ path: WritableKeyPath<UserCommand, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings.widgets.commands[index][keyPath: path] },
            set: { value in store.update { $0.widgets.commands[index][keyPath: path] = value } }
        )
    }

    private var directory: Binding<String> {
        Binding(
            get: { store.settings.widgets.commands[index].directory ?? "" },
            set: { value in store.update { $0.widgets.commands[index].directory = value.isEmpty ? nil : value } }
        )
    }

    var body: some View {
        Section {
            TextField(loc("Name"), text: binding(\.name))
            TextField(loc("Command"), text: binding(\.command))
                .font(.system(size: 12, design: .monospaced))
            LabeledContent(loc("Working directory")) {
                HStack {
                    TextField("", text: directory)
                        .labelsHidden()
                        .font(.system(size: 12, design: .monospaced))
                    Button(loc("Choose…"), action: chooseFolder)
                }
            }
            Picker(loc("Timeout"), selection: binding(\.timeout)) {
                ForEach([60, 300, 900, 1800], id: \.self) { seconds in
                    Text(loc("\(seconds / 60) min")).tag(TimeInterval(seconds))
                }
            }
            Toggle(loc("Ask before running"), isOn: binding(\.asksFirst))
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        directory.wrappedValue = GitDiscovery.plainPath(url)
    }
}
