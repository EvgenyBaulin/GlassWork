import AppKit
import GlassWorkCore

/// Keeps the badges, attention requests and hidden apps of the Dock's tiles up to date.
///
/// Badges come from the system Dock through Accessibility, so they appear only once that is granted, and are
/// read every 5 seconds while GlassWork's Dock is on screen. Hidden apps need no polling: the workspace says
/// when one hides or shows.
@MainActor
final class DockTileWatcher {
    private let state: DockLiveState
    private let isVisible: () -> Bool
    private var task: Task<Void, Never>?
    private var attention = DockAttention()

    private static let interval = Duration.seconds(5)

    init(state: DockLiveState, isVisible: @escaping () -> Bool) {
        self.state = state
        self.isVisible = isVisible
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        attention = DockAttention()
        set(badges: [:], attention: [])
        if !state.hidden.isEmpty {
            state.hidden = []
        }
    }

    /// Paths of the Dock's apps that are running and hidden.
    func refreshHidden() {
        let hiddenPaths = Set(NSWorkspace.shared.runningApplications.filter(\.isHidden).compactMap {
            $0.bundleURL?.path(percentEncoded: false)
        })
        let hidden = Set(state.settings.apps.map(\.path)).intersection(hiddenPaths)
        if hidden != state.hidden {
            state.hidden = hidden
        }
    }

    private func poll() async {
        // Trust is asked each time, so a grant made while the Dock is up takes effect at the next reading.
        guard isVisible(), Accessibility.isTrusted else {
            if !state.badges.isEmpty || !state.attention.isEmpty {
                attention = DockAttention()
                set(badges: [:], attention: [])
            }
            return
        }
        let items = await Task.detached { DockBadgeReader.read() }.value
        let wanted = Set(state.settings.apps.map(\.path))
        let labels = DockBadges.labels(from: items).filter { wanted.contains($0.key) }
        let front = NSWorkspace.shared.frontmostApplication?.bundleURL?.path(percentEncoded: false)
        attention.update(labels: labels, front: front)
        set(badges: labels, attention: attention.asking)
    }

    /// Only when something changed, so a reading that finds the same badges does not redraw the Dock.
    private func set(badges: [String: String], attention: Set<String>) {
        if state.badges != badges {
            state.badges = badges
        }
        if state.attention != attention {
            state.attention = attention
        }
    }
}
