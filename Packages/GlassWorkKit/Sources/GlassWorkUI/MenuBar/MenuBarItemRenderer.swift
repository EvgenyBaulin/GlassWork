import AppKit
import GlassWorkCore
import SwiftUI

/// Renders a module into the bitmap shown by its status item.
///
/// Items refresh every two seconds all day, so this avoids SwiftUI and skips unchanged frames:
/// a SwiftUI view in the menu bar costs several percent of a core and most of the app's memory.
@MainActor
public final class MenuBarItemRenderer {
    private let module: ModuleID
    private let monitor: SystemMonitor
    public var style: DisplayStyle
    public var numbers: NumberStyle
    public var options: [String: String]
    private var bounds = CGRect.zero
    private var lastSignature: String?
    /// The fan glyph turns one step per refresh. A real animation would cost far more than it shows.
    private var spinAngle: CGFloat = 0

    private static let padding: CGFloat = 4
    private static let symbolWidth: CGFloat = 16
    private static let graphWidth: CGFloat = 34
    private static let labelWidth: CGFloat = 8

    public init(
        module: ModuleID,
        style: DisplayStyle,
        numbers: NumberStyle,
        options: [String: String] = [:],
        monitor: SystemMonitor
    ) {
        self.module = module
        self.style = style
        self.numbers = numbers
        self.options = options
        self.monitor = monitor
    }

    /// A new image, or nil when nothing visible changed since the last one.
    public func image(size: CGSize, force: Bool = false) -> NSImage? {
        let content = ItemContent.content(module, monitor: monitor, style: numbers, options: options)
        if content.spin > 0, style == .symbol || style == .figure || style == .graph {
            spinAngle = (spinAngle + 30 + 60 * content.spin).truncatingRemainder(dividingBy: 360)
        }
        let current = signature(content, size: size)
        guard force || current != lastSignature else { return nil }
        lastSignature = current
        bounds = CGRect(origin: .zero, size: size)
        let image = NSImage(size: size)
        image.lockFocus()
        draw(content)
        image.unlockFocus()
        // Template images follow the menu bar's light or dark look; alerts keep their color.
        image.isTemplate = content.alert == nil
        return image
    }

    private func signature(_ content: ItemContent, size: CGSize) -> String {
        var parts = [
            content.figure, content.secondLine ?? "", "\(style)", "\(size.width)", "\(content.alert != nil)",
            "\(spinAngle)",
        ]
        if style == .graph || style == .graphAndFigure, let metric = content.metric {
            parts.append("\(monitor.points(metric, in: .minute).last?.date.timeIntervalSince1970 ?? 0)")
        }
        return parts.joined(separator: "|")
    }

    private func draw(_ content: ItemContent) {
        let color = content.alert.map(NSColor.init) ?? NSColor.black
        var x = Self.padding
        switch style {
        case .symbol:
            drawSymbol(at: &x, color: color)
        case .figure:
            drawSymbol(at: &x, color: color)
            drawFigure(content, at: x, color: color)
        case .graph:
            drawSymbol(at: &x, color: color)
            drawGraph(content, at: x, color: color)
        case .graphAndFigure:
            drawGraph(content, at: x, color: color)
            drawFigure(content, at: x + Self.graphWidth + Self.padding, color: color)
        case .labelled:
            drawLabel(at: &x, color: color)
            drawFigure(content, at: x, color: color)
        }
    }

    private func drawSymbol(at x: inout CGFloat, color: NSColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            .applying(.init(paletteColors: [color]))
        if let image = NSImage(systemSymbolName: module.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        {
            let size = image.size
            let origin = CGPoint(
                x: x + (Self.symbolWidth - size.width) / 2,
                y: (bounds.height - size.height) / 2
            )
            let frame = CGRect(origin: origin, size: size)
            NSGraphicsContext.saveGraphicsState()
            let turn = NSAffineTransform()
            turn.translateX(by: frame.midX, yBy: frame.midY)
            turn.rotate(byDegrees: -spinAngle)
            turn.translateX(by: -frame.midX, yBy: -frame.midY)
            turn.concat()
            image.draw(in: frame)
            NSGraphicsContext.restoreGraphicsState()
        }
        x += Self.symbolWidth + Self.padding
    }

    private func drawFigure(_ content: ItemContent, at x: CGFloat, color: NSColor) {
        let size: CGFloat = content.secondLine == nil ? 12 : 9
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium),
            .foregroundColor: color,
        ]
        let first = NSAttributedString(string: content.figure, attributes: attributes)
        if let second = content.secondLine {
            let lower = NSAttributedString(string: second, attributes: attributes)
            let height = first.size().height
            lower.draw(at: CGPoint(x: x, y: bounds.midY - height + 1))
            first.draw(at: CGPoint(x: x, y: bounds.midY - 1))
        } else {
            first.draw(at: CGPoint(x: x, y: (bounds.height - first.size().height) / 2))
        }
    }

    private func drawGraph(_ content: ItemContent, at x: CGFloat, color: NSColor) {
        guard let metric = content.metric else { return }
        let values = monitor.points(metric, in: .minute).suffix(30).map(\.value)
        guard values.count > 1 else { return }
        let upper = content.domain?.upperBound ?? max(values.max() ?? 1, 0.000_1)
        let lower = content.domain?.lowerBound ?? 0
        let height: CGFloat = 16
        let bottom = (bounds.height - height) / 2
        let step = Self.graphWidth / CGFloat(values.count - 1)
        let line = NSBezierPath()
        for (index, value) in values.enumerated() {
            let share = min(max((value - lower) / max(upper - lower, 0.000_1), 0), 1)
            let point = CGPoint(x: x + CGFloat(index) * step, y: bottom + height * share)
            if index == 0 {
                line.move(to: point)
            } else {
                line.line(to: point)
            }
        }
        let area = line.copy() as? NSBezierPath
        area?.line(to: CGPoint(x: x + Self.graphWidth, y: bottom))
        area?.line(to: CGPoint(x: x, y: bottom))
        area?.close()
        color.withAlphaComponent(0.3).setFill()
        area?.fill()
        color.setStroke()
        line.lineWidth = 1
        line.stroke()
    }

    private func drawLabel(at x: inout CGFloat, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 6.5, weight: .bold),
            .foregroundColor: color,
        ]
        let letters = module.shortLabel.map { NSAttributedString(string: String($0), attributes: attributes) }
        let lineHeight: CGFloat = 7
        var y = (bounds.height + lineHeight * CGFloat(letters.count)) / 2 - lineHeight - 1
        for letter in letters {
            letter.draw(at: CGPoint(x: x + (Self.labelWidth - letter.size().width) / 2, y: y))
            y -= lineHeight
        }
        x += Self.labelWidth + Self.padding
    }
}
