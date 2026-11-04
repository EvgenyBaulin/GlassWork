import GlassWorkCore
import SwiftUI

/// What panels can ask the app to do.
@MainActor
public struct PanelActions {
    public var openSettings: (ModuleID) -> Void
    public var detach: (ModuleID) -> Void
    public var openApp: (String) -> Void
    public var openURL: (URL) -> Void
    public var quitProcess: (ProcessUsage, Bool) -> Void
    public var openFanCurves: () -> Void

    public init(
        openSettings: @escaping (ModuleID) -> Void = { _ in },
        detach: @escaping (ModuleID) -> Void = { _ in },
        openApp: @escaping (String) -> Void = { _ in },
        openURL: @escaping (URL) -> Void = { _ in },
        quitProcess: @escaping (ProcessUsage, Bool) -> Void = { _, _ in },
        openFanCurves: @escaping () -> Void = {}
    ) {
        self.openSettings = openSettings
        self.detach = detach
        self.openApp = openApp
        self.openURL = openURL
        self.quitProcess = quitProcess
        self.openFanCurves = openFanCurves
    }
}

public extension EnvironmentValues {
    @Entry var panelActions: PanelActions = MainActor.assumeIsolated { PanelActions() }
}

/// Header, content and footer every module panel shares.
struct PanelFrame<Content: View>: View {
    let module: ModuleID
    let subtitle: String
    var footerTitle: String?
    var footerAction: (() -> Void)?
    @ViewBuilder let content: Content
    @Environment(\.panelActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ModuleIcon(module, size: 24)
            Text(module.title).font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Button {
                actions.detach(module)
            } label: {
                Image(systemName: "pin")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(loc("Keep open in a floating window"))
        }
    }

    private var footer: some View {
        HStack {
            if let footerTitle, let footerAction {
                Button(footerTitle, action: footerAction)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
            Spacer()
            Button(loc("Settings…")) { actions.openSettings(module) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
    }
}

/// Bold heading inside a panel, with an optional caption on the right.
struct PanelSection<Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                if let caption {
                    Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            content
        }
    }
}

/// Label on the left, value on the right.
struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

/// Very large figure that opens a panel.
struct BigFigure: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

/// 1 min / 1 h / 24 h switcher that drives a panel's charts.
struct RangePicker: View {
    @Binding var range: TieredHistory.Range

    var body: some View {
        Picker("", selection: $range) {
            Text(loc("1 min")).tag(TieredHistory.Range.minute)
            Text(loc("1 h")).tag(TieredHistory.Range.hour)
            Text(loc("24 h")).tag(TieredHistory.Range.day)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
    }
}

/// Top processes list. Right-click offers Quit and Force Quit with confirmation.
struct TopProcesses: View {
    enum Sort { case cpu, memory }

    let processes: [ProcessUsage]
    let sort: Sort
    let tint: Color
    var limit = 5
    @Environment(\.panelActions) private var actions
    @State private var pending: PendingQuit?

    private struct PendingQuit: Identifiable {
        let process: ProcessUsage
        let force: Bool
        var id: Int32 {
            process.pid
        }
    }

    /// Processes macOS needs to keep running, and GlassWork itself.
    private static let protected: Set<String> = ["kernel_task", "launchd", "WindowServer", "loginwindow", "GlassWork"]

    private var top: [ProcessUsage] {
        let sorted = processes.sorted {
            sort == .cpu ? $0.cpu > $1.cpu : $0.memory > $1.memory
        }
        return Array(sorted.prefix(limit))
    }

    private var peak: Double {
        max(top.map { sort == .cpu ? $0.cpu : Double($0.memory) }.max() ?? 1, 0.1)
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(top) { process in
                row(process).contextMenu { menu(process) }
            }
        }
        .confirmationDialog(
            pending.map { title($0) } ?? "",
            isPresented: Binding(get: { pending != nil }, set: {
                if !$0 {
                    pending = nil
                }
            }),
            presenting: pending
        ) { item in
            Button(item.force ? loc("Force Quit") : loc("Quit"), role: item.force ? .destructive : nil) {
                actions.quitProcess(item.process, item.force)
            }
            Button(loc("Cancel"), role: .cancel) {}
        }
    }

    private func title(_ item: PendingQuit) -> String {
        item.force ? loc("Force Quit “\(item.process.name)”?") : loc("Quit “\(item.process.name)”?")
    }

    private func row(_ process: ProcessUsage) -> some View {
        let value = sort == .cpu ? process.cpu : Double(process.memory)
        return HStack(spacing: 10) {
            Text(process.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            ThinBar(value: value / peak, tint: tint).frame(width: 80)
            Text(sort == .cpu ? String(format: "%.1f", process.cpu) : Format.bytes(value, style: .precise))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
        .font(.system(size: 12))
    }

    @ViewBuilder
    private func menu(_ process: ProcessUsage) -> some View {
        let isProtected = Self.protected.contains(process.name)
        Button(loc("Quit")) { pending = PendingQuit(process: process, force: false) }
            .disabled(isProtected)
        Button(loc("Force Quit")) { pending = PendingQuit(process: process, force: true) }
            .disabled(isProtected)
    }
}
