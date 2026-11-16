import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// The name label above a Dock item, in a window of its own: the Dock's window is sized to its icons and has no
/// room for it. It never takes clicks.
@MainActor
final class DockTooltip {
    private var panel: NSPanel?
    private var shown: String?

    /// Between the tile and the label.
    private static let gap = 2.0

    func update(_ hover: DockHover, in window: NSWindow?, position: DockPosition) {
        guard let text = hover.text, let window, window.isVisible else {
            if hover.text == nil, shown == hover.id {
                hide()
            }
            return
        }
        shown = hover.id
        let panel = panel ?? makePanel()
        let hosting = NSHostingView(rootView: DockTooltipLabel(text: text))
        let size = hosting.fittingSize
        panel.contentView = hosting
        // SwiftUI's global frame is the window's content, top-left origin.
        let tile = CGRect(
            x: window.frame.minX + hover.frame.minX,
            y: window.frame.maxY - hover.frame.maxY,
            width: hover.frame.width,
            height: hover.frame.height
        )
        var origin = switch position {
        case .bottom: CGPoint(x: tile.midX - size.width / 2, y: tile.maxY + Self.gap)
        case .left: CGPoint(x: tile.maxX + Self.gap, y: tile.midY - size.height / 2)
        case .right: CGPoint(x: tile.minX - size.width - Self.gap, y: tile.midY - size.height / 2)
        }
        if let screen = window.screen?.frame {
            origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFront(nil)
    }

    func hide() {
        shown = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(NSWindow.Level.dock.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        self.panel = panel
        return panel
    }
}

/// Dark on a dark desktop, light on a light one, as in the design.
private struct DockTooltipLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: .rect(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.12)))
            .padding(6)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            .fixedSize()
    }
}
