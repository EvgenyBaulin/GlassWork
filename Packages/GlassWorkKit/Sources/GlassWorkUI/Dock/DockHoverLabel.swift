import GlassWorkCore
import SwiftUI

/// The item under the pointer, for the name label the app shows above it, as the system Dock does.
public struct DockHover: Equatable, Sendable {
    public let id: String
    /// Nil once the pointer has left this item.
    public let text: String?
    /// The tile in the Dock window, top-left origin.
    public let frame: CGRect
}

/// Reports hovering and, while hovered, every move of the tile: magnification shifts it under a still pointer.
struct DockHoverLabel: ViewModifier {
    let id: String
    let text: String
    let report: (DockHover) -> Void
    @State private var frame = CGRect.zero
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { new in
                frame = new
                if isHovered {
                    report(DockHover(id: id, text: text, frame: new))
                }
            }
            .onHover { hovering in
                isHovered = hovering
                report(DockHover(id: id, text: hovering ? text : nil, frame: frame))
            }
    }
}

enum DockLabelText {
    static func of(_ item: DockItem, stackTitle: String) -> String {
        switch item {
        case let .app(app): app.name
        case let .folder(folder): loc("\(folder.name) · \(folder.apps.count) apps")
        case let .widget(module): loc("\(module.title) — \(module.dockClickTitle), hold for card")
        case .stack: stackTitle
        }
    }
}
