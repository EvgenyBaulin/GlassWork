import AppKit
import GlassWorkCore
import SwiftUI

struct GitPanel: View {
    let reading: GitReading?
    let selected: String?
    let manual: [String]
    var now = Date()
    @Environment(\.panelActions) private var actions
    @State private var hovered: String?

    private static let privacySettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
    )

    private var repositories: [GitRepository] {
        reading?.repositories ?? []
    }

    private var readable: [GitRepository] {
        repositories.filter { $0.problem == nil }
    }

    private var inMenuBar: String? {
        reading?.selected(path: selected)?.path
    }

    var body: some View {
        PanelFrame(
            module: .git,
            subtitle: repositories.isEmpty ? "" : subtitle,
            footerTitle: reading == .notInstalled ? nil : loc("Add Folder…"),
            footerAction: addFolder
        ) {
            switch reading {
            case nil:
                PanelMessage(symbol: "arrow.triangle.branch", title: loc("Looking for repositories…"))
            case .notInstalled:
                PanelMessage(
                    symbol: "arrow.triangle.branch",
                    title: loc("git not found"),
                    detail: loc("Install the Command Line Tools, then reopen this panel.")
                )
            case .repositories where repositories.isEmpty:
                PanelMessage(
                    symbol: "folder",
                    title: loc("No repositories found"),
                    detail: loc("GlassWork looks in ~/Developer. Add other folders below.")
                )
            case .repositories:
                list
            }
        }
    }

    private var subtitle: String {
        repositories.count == 1 ? loc("1 repository") : loc("\(repositories.count) repositories")
    }

    @ViewBuilder
    private var list: some View {
        ForEach(repositories.filter { $0.problem != nil }) { repository in
            problem(repository)
        }
        ForEach(readable.prefix(10)) { repository in
            row(repository)
        }
        if readable.count > 10 {
            Text(loc("and \(readable.count - 10) more")).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        ReadOnlyNote(
            text: loc("Read-only: GlassWork never commits, fetches or pushes. Ahead and behind use your last fetch.")
        )
    }

    private func row(_ repository: GitRepository) -> some View {
        let isHovered = hovered == repository.path
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(repository.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if repository.path == inMenuBar {
                        Circle().fill(Palette.blue).frame(width: 6, height: 6)
                        Text(loc("In menu bar")).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Label {
                    Text(repository.status?.head ?? "—").font(.system(size: 11, design: .monospaced))
                } icon: {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                }
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .truncationMode(.middle)
                Text(caption(repository)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                badges(repository.status)
                if isHovered {
                    rowActions(repository)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(.white.opacity(isHovered ? 0.07 : 0), in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onHover { hovered = $0 ? repository.path : nil }
        .onTapGesture { actions.setOption(.git, DeveloperOptions.Key.repository, repository.path) }
    }

    private func caption(_ repository: GitRepository) -> String {
        if let behind = repository.status?.behind, behind > 0 {
            return loc("Behind by \(behind) since your last fetch")
        }
        guard let date = repository.lastCommit else { return loc("No commits yet") }
        return loc("Last commit \(DeveloperText.relative(date, to: now))")
    }

    @ViewBuilder
    private func badges(_ status: GitStatus?) -> some View {
        if let status {
            if status.isClean, status.ahead == 0, status.behind == 0 {
                Text(loc("Up to date")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green)
            } else {
                HStack(spacing: 4) {
                    if status.conflicted > 0 {
                        badge("⚠ \(status.conflicted)")
                    }
                    if status.changed > 0 {
                        badge("±\(status.changed)")
                    }
                    if status.ahead > 0 {
                        badge("↑\(status.ahead)")
                    }
                    if status.behind > 0 {
                        badge("↓\(status.behind)")
                    }
                }
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.white.opacity(0.12), in: Capsule())
    }

    private func rowActions(_ repository: GitRepository) -> some View {
        HStack(spacing: 4) {
            RowIconButton(symbol: "terminal", help: loc("Open in Terminal")) {
                openInTerminal(repository.path)
            }
            RowIconButton(symbol: "folder", help: loc("Reveal in Finder")) {
                actions.openURL(URL(filePath: repository.path))
            }
        }
    }

    private func problem(_ repository: GitRepository) -> some View {
        VStack(spacing: 8) {
            switch repository.problem {
            case .needsPermission:
                PanelMessage(
                    symbol: "lock",
                    title: loc("\(repository.name) needs access"),
                    detail: loc("macOS protects this folder. Allow GlassWork in System Settings to read it."),
                    tint: Palette.orange
                )
                problemButtons(repository) {
                    Button(loc("Open Privacy Settings…")) { Self.privacySettings.map(actions.openURL) }
                }
            case .missing:
                PanelMessage(
                    symbol: "exclamationmark.triangle",
                    title: loc("\(repository.name) is no longer a repository"),
                    detail: loc("\(repository.path) has no .git folder. It was moved or deleted."),
                    tint: Palette.red
                )
                problemButtons(repository) {
                    Button(loc("Locate…")) { locate(repository) }
                }
            default:
                PanelMessage(
                    symbol: "exclamationmark.triangle",
                    title: loc("Can't read \(repository.name)"),
                    tint: Palette.orange
                )
                problemButtons(repository) { EmptyView() }
            }
        }
    }

    private func problemButtons(_ repository: GitRepository, @ViewBuilder extra: () -> some View) -> some View {
        HStack {
            if repository.isManual {
                Button(loc("Remove from List")) { setManual(manual.filter { $0 != repository.path }) }
            }
            extra()
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }

    private func openInTerminal(_ path: String) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            return
        }
        NSWorkspace.shared.open(
            [URL(filePath: path)],
            withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func addFolder() {
        chooseFolder { path in
            if !manual.contains(path) {
                setManual(manual + [path])
            }
        }
    }

    private func locate(_ repository: GitRepository) {
        chooseFolder { path in
            setManual(manual.map { $0 == repository.path ? path : $0 })
        }
    }

    private func chooseFolder(_ onChoose: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        NSApp.activate()
        panel.begin { response in
            if response == .OK, let url = panel.url {
                onChoose(GitDiscovery.plainPath(url))
            }
        }
    }

    private func setManual(_ paths: [String]) {
        actions.setOption(.git, DeveloperOptions.Key.repositories, DeveloperOptions.encode(paths))
    }
}
