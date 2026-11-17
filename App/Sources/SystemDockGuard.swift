import AppKit
import GlassWorkCore
import SwiftUI

/// Gives the system Dock back when GlassWork ends in a way the normal quit path does not cover.
///
/// Covered: a normal quit (`prepareToQuit`), `exit()` through `atexit`, and SIGTERM (a logout, `kill`). Not
/// covered: a crash or SIGKILL. No code runs then, and there is no helper process to notice, so the system Dock
/// stays hidden until GlassWork starts again and `recoverAtLaunch()` puts it back.
@MainActor
enum SystemDockGuard {
    private static var termination: DispatchSourceSignal?
    private static var isInstalled = false
    private static var toast: NSPanel?

    /// Safe to call again. Called when the Dock takes the system Dock over.
    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        // `restore()` does nothing once the settings are back, so running it twice is harmless.
        atexit { SystemDock.restore() }
        // A raw handler cannot call CFPreferences or start a process. A dispatch source runs on the main queue.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            SystemDock.restore()
            NSApplication.shared.terminate(nil)
        }
        source.resume()
        termination = source
    }

    /// Runs once at launch, before the Dock is applied. True when the system Dock was put back.
    static func recoverAtLaunch() -> Bool {
        switch DockRecovery.decide(markerExists: SystemDock.hasMarker, hasSavedSettings: SystemDock.hasSavedSettings) {
        case .nothing:
            return false
        case .clearMarker:
            SystemDock.clearMarker()
            return false
        case .restore:
            SystemDock.restore()
            return true
        }
    }

    /// A small label at the top of the screen that goes by itself.
    static func showRestoredToast() {
        let hosting = NSHostingView(rootView: Text(loc("The system Dock was restored after an unexpected quit"))
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule))
        let size = hosting.fittingSize
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        if let screen = NSScreen.screens.first {
            let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 16)
            panel.setFrame(CGRect(origin: origin, size: size), display: true)
        }
        panel.orderFrontRegardless()
        toast = panel
        Task {
            try? await Task.sleep(for: .seconds(6))
            panel.orderOut(nil)
            if toast === panel {
                toast = nil
            }
        }
    }
}
