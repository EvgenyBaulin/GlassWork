import Foundation
import GlassWorkCore

/// Whether an app has a New Window item, without making the Dock's menu wait for it.
///
/// Finding the item reads the app's menus through Accessibility, which a slow app answers slowly. The answer is
/// kept for 30 seconds and looked up off the main thread; until it is in, the menu goes without the item, and the
/// next time it opens the item is there.
@MainActor
final class DockNewWindowProbe {
    private var cache = DockAnswerCache<Int32>()
    private var pending: Set<Int32> = []

    func canOpen(pid: Int32) -> Bool {
        if let known = cache.value(for: pid, now: Date()) {
            return known
        }
        guard pending.insert(pid).inserted else { return false }
        Task { [weak self] in
            let found = await Task.detached { DockAppWindows.hasNewWindow(pid: pid) }.value
            self?.pending.remove(pid)
            self?.cache.store(found, for: pid, now: Date())
        }
        return false
    }
}
