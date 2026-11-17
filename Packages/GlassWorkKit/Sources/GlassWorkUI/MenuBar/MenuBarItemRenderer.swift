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
    /// The look of the bar, needed by items that are not template images.
    public var appearance: NSAppearance?
    public var options: [String: String]
    private var bounds = CGRect.zero
    private var lastSignature: String?
    /// The fan glyph turns one step per refresh. A real animation would cost far more than it shows.
    /// The symbol looks the same every 90°, so steps stay well below that.
    private var spinAngle: CGFloat = 0

    private static let padding: CGFloat = 4
    private static let symbolWidth: CGFloat = 16
    private static let graphWidth: CGFloat = 34
    private static let graphHeight: CGFloat = 16
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
        guard size.width > 0 else { return nil }
        let content = ItemContent.content(module, monitor: monitor, style: numbers, options: options)
        return image(content: content, size: size, force: force)
    }

    func image(content: ItemContent, size: CGSize, force: Bool = false) -> NSImage? {
        guard size.width > 0 else { return nil }
        if content.spin > 0, style == .symbol || style == .figure || style == .graph {
            spinAngle = (spinAngle + 20 + 40 * content.spin).truncatingRemainder(dividingBy: 360)
        }
        let current = signature(content, size: size)
        guard force || current != lastSignature else { return nil }
        lastSignature = current
        bounds = CGRect(origin: .zero, size: size)
        let image = NSImage(size: size)
        image.lockFocus()
        (appearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance { draw(content) }
        image.unlockFocus()
        // Template images follow the menu bar's light or dark look; alerts and accents keep their color.
        image.isTemplate = isTemplate(content)
        return image
    }

    /// Current value, the range seen since the first reading kept and one line of context.
    public func tooltip() -> String {
        let content = ItemContent.content(module, monitor: monitor, style: .precise)
        var extremes: ItemTooltip.Extremes?
        if let metric = content.metric {
            // The coarse day tier reaches furthest back; the fine minute tier keeps the true peaks of now.
            let points = monitor.points(metric, in: .day) + monitor.points(metric, in: .minute)
            extremes = ItemTooltip.Extremes(points.map(\.value), since: points.map(\.date).min())
        }
        return ItemTooltip.text(
            title: module.title,
            figure: content.figure,
            extremes: extremes,
            format: content.format,
            secondLine: content.secondLine,
            detail: content.detail
        )
    }

    private func signature(_ content: ItemContent, size: CGSize) -> String {
        var parts = [content.figure, content.secondLine ?? "", "\(style)", "\(size.width)", "\(content.alert != nil)"]
        parts.append("\(spinAngle)")
        parts += [content.prefix ?? "", content.symbol ?? "", content.label ?? "", content.accent?.text ?? ""]
        parts += ["\(content.isDimmed)", "\(content.accent?.color != nil)", appearance?.name.rawValue ?? ""]
        parts.append("\(content.symbolLevel ?? -1)")
        if case let .battery(level, state) = content.glyph {
            parts.append("\(Int((level * 100).rounded()))\(state)")
        }
        parts.append("\(content.artwork?.count ?? 0)")
        parts.append(content.swatch.flatMap { NSColor($0).hexString } ?? "")
        if style == .graph || style == .graphAndFigure {
            if let glyph = content.glyph {
                parts.append("\(glyph)")
            } else if let values = content.graphValues(monitor) {
                parts.append("\(Self.graphLevels(values, domain: content.domain))")
            }
        }
        return parts.joined(separator: "|")
    }

    /// A graph in device pixels. A slow metric moves less than a pixel between reads, so a change nobody could
    /// see does not have to cost a new image for the status item.
    static func graphLevels(_ values: [Double], domain: ClosedRange<Double>?) -> [Int] {
        let pixels = graphHeight * 2
        return values.map { Int((graphShare($0, of: values, domain: domain) * pixels).rounded()) }
    }

    /// Where a value sits on the graph, from 0 to 1.
    private static func graphShare(_ value: Double, of values: [Double], domain: ClosedRange<Double>?) -> Double {
        let upper = domain?.upperBound ?? max(values.max() ?? 1, 0.000_1)
        let lower = domain?.lowerBound ?? 0
        return min(max((value - lower) / max(upper - lower, 0.000_1), 0), 1)
    }

    private func draw(_ content: ItemContent) {
        let color = baseColor(content)
        var x = Self.padding
        switch style {
        case .symbol:
            drawSymbol(content, at: &x, color: color)
        case .figure:
            if showsArtwork(content) {
                drawArtwork(content, at: &x)
            } else if content.showsSymbol {
                drawSymbol(content, at: &x, color: color)
            }
            drawFigure(content, at: x, color: color)
        case .graph:
            // A battery is its own graph, so it is drawn once, wide.
            if case .battery = content.glyph {} else {
                drawSymbol(content, at: &x, color: color)
            }
            drawGraph(content, at: x, color: color)
        case .graphAndFigure:
            drawGraph(content, at: x, color: color)
            drawFigure(content, at: x + Self.graphWidth + Self.padding, color: color)
        case .labelled:
            drawLabel(content, at: &x, color: color)
            drawFigure(content, at: x, color: color)
        }
    }

    /// A template image is tinted by the bar, so black means "the bar's color". An image with a colored
    /// accent is drawn as it is and has to use the bar's text color itself.
    private func baseColor(_ content: ItemContent) -> NSColor {
        let isTemplate = content.accent?.color == nil && content.swatch == nil && !showsArtwork(content)
        let color = content.alert.map(NSColor.init) ?? (isTemplate ? .black : .labelColor)
        return content.isDimmed ? color.withAlphaComponent(0.5) : color
    }

    private func isTemplate(_ content: ItemContent) -> Bool {
        content.alert == nil && content.accent?.color == nil && content.swatch == nil && !showsArtwork(content)
    }

    private func showsArtwork(_ content: ItemContent) -> Bool {
        style == .figure && content.artwork != nil
    }

    private func drawArtwork(_ content: ItemContent, at x: inout CGFloat) {
        let side: CGFloat = 16
        let frame = CGRect(x: x, y: (bounds.height - side) / 2, width: side, height: side)
        if let data = content.artwork, let image = NSImage(data: data) {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3).addClip()
            image.draw(in: frame)
            NSGraphicsContext.restoreGraphicsState()
        }
        x += Self.symbolWidth + Self.padding
    }

    private func drawSymbol(_ content: ItemContent, at x: inout CGFloat, color: NSColor) {
        if case let .battery(level, state) = content.glyph {
            let frame = CGRect(x: x, y: bounds.midY - 5, width: Self.symbolWidth, height: 10)
            drawBattery(level: level, state: state, in: frame, color: color)
            x += Self.symbolWidth + Self.padding
            return
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            .applying(.init(paletteColors: [content.swatch.map(NSColor.init) ?? color]))
        let name = content.symbol ?? module.symbol
        let symbol = content.symbolLevel.map {
            NSImage(systemSymbolName: name, variableValue: $0, accessibilityDescription: nil)
        } ?? NSImage(systemSymbolName: name, accessibilityDescription: nil)
        if let image = symbol?.withSymbolConfiguration(configuration) {
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
        let first = NSAttributedString(string: content.text(for: style), attributes: attributes)
        if let second = content.secondLine {
            let lower = NSAttributedString(string: second, attributes: attributes)
            let height = first.size().height
            lower.draw(at: CGPoint(x: x, y: bounds.midY - height + 1))
            first.draw(at: CGPoint(x: x, y: bounds.midY - 1))
        } else if let width = content.figureWidth {
            let height = first.size().height
            let frame = CGRect(x: x, y: (bounds.height - height) / 2, width: width, height: height)
            first.draw(with: frame, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        } else {
            first.draw(at: CGPoint(x: x, y: (bounds.height - first.size().height) / 2))
            drawAccent(content, at: x + first.size().width + Self.padding, attributes: attributes)
        }
    }

    private func drawAccent(_ content: ItemContent, at x: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        guard let accent = content.accent else { return }
        var colored = attributes
        if let color = accent.color {
            colored[.foregroundColor] = NSColor(color)
        }
        let text = NSAttributedString(string: accent.text, attributes: colored)
        text.draw(at: CGPoint(x: x, y: (bounds.height - text.size().height) / 2))
    }

    private func drawGraph(_ content: ItemContent, at x: CGFloat, color: NSColor) {
        if let glyph = content.glyph {
            drawGlyph(glyph, content, at: x, color: color)
            return
        }
        guard let values = content.graphValues(monitor), values.count > 1 else { return }
        let color = content.accent?.color.map(NSColor.init) ?? color
        let height = Self.graphHeight
        let bottom = (bounds.height - height) / 2
        let step = Self.graphWidth / CGFloat(values.count - 1)
        let line = NSBezierPath()
        for (index, value) in values.enumerated() {
            let share = Self.graphShare(value, of: values, domain: content.domain)
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

    private func drawGlyph(_ glyph: ItemGlyph, _ content: ItemContent, at x: CGFloat, color: NSColor) {
        switch glyph {
        case let .ring(value):
            drawRing(value, at: x, color: color)
        case let .dots(filled, faint):
            drawDots(filled: filled, faint: faint, at: x, color: color)
        case .symbol:
            if style == .graphAndFigure {
                var position = x
                drawSymbol(content, at: &position, color: color)
            }
        case let .bars(levels):
            drawBars(levels, at: x, color: color)
        case let .progress(value):
            drawProgress(value, at: x, color: color)
        case let .battery(level, state):
            let frame = CGRect(x: x, y: bounds.midY - 6, width: 28, height: 12)
            drawBattery(level: level, state: state, in: frame, color: color)
        }
    }

    private func drawProgress(_ value: Double, at x: CGFloat, color: NSColor) {
        let height: CGFloat = 4
        let track = CGRect(x: x, y: bounds.midY - height / 2, width: Self.graphWidth, height: height)
        color.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: track, xRadius: height / 2, yRadius: height / 2).fill()
        let filled = Self.graphWidth * CGFloat(ItemProgress.clamp(value))
        guard filled > 0 else { return }
        color.setFill()
        NSBezierPath(
            roundedRect: CGRect(x: x, y: track.minY, width: max(filled, height), height: height),
            xRadius: height / 2,
            yRadius: height / 2
        ).fill()
    }

    /// A battery outline with a fill from the left that grows with the charge. The bolt and the plug are cut
    /// out around themselves so they read over the fill and over the empty part alike.
    private func drawBattery(level: Double, state: BatteryPowerState, in frame: CGRect, color: NSColor) {
        let cap: CGFloat = 1.5
        let body = CGRect(
            x: frame.minX + 0.5,
            y: frame.minY + 0.5,
            width: frame.width - cap - 1,
            height: frame.height - 1
        )
        let outline = NSBezierPath(roundedRect: body, xRadius: 2.5, yRadius: 2.5)
        outline.lineWidth = 1
        color.withAlphaComponent(0.55).setStroke()
        outline.stroke()
        let nub = CGRect(x: body.maxX + 0.5, y: frame.midY - 2, width: cap, height: 4)
        color.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: nub, xRadius: 0.75, yRadius: 0.75).fill()
        let inner = body.insetBy(dx: 1.5, dy: 1.5)
        let share = CGFloat(min(max(level, 0), 1))
        if share > 0 {
            let width = max(inner.width * share, 1.5)
            let filled = CGRect(x: inner.minX, y: inner.minY, width: width, height: inner.height)
            color.setFill()
            NSBezierPath(roundedRect: filled, xRadius: 1, yRadius: 1).fill()
        }
        let name = switch state {
        case .discharging: nil as String?
        case .charging: "bolt.fill"
        case .pluggedIn: "powerplug.fill"
        }
        guard let name, let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: frame.height * 0.62, weight: .semibold)
            .applying(.init(paletteColors: [color]))
        guard let symbol = image.withSymbolConfiguration(configuration) else { return }
        let mark = CGRect(
            x: body.midX - symbol.size.width / 2,
            y: frame.midY - symbol.size.height / 2,
            width: symbol.size.width,
            height: symbol.size.height
        )
        symbol.draw(in: mark.insetBy(dx: -1, dy: -1), from: .zero, operation: .destinationOut, fraction: 1)
        symbol.draw(in: mark, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func drawBars(_ levels: [Double], at x: CGFloat, color: NSColor) {
        color.setFill()
        for (index, level) in levels.enumerated() {
            let height = 3 + 11 * CGFloat(min(max(level, 0), 1))
            let frame = CGRect(x: x + CGFloat(index) * 5, y: bounds.midY - 7, width: 3, height: height)
            NSBezierPath(roundedRect: frame, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    private func drawRing(_ value: Double, at x: CGFloat, color: NSColor) {
        let radius: CGFloat = 6
        let center = CGPoint(x: x + radius + 1, y: bounds.midY)
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 2.5
        color.withAlphaComponent(0.25).setStroke()
        track.stroke()
        let arc = NSBezierPath()
        let end = 90 - 360 * CGFloat(min(max(value, 0), 1))
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: end, clockwise: true)
        arc.lineWidth = 2.5
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    private func drawDots(filled: Int, faint: Int, at x: CGFloat, color: NSColor) {
        let size: CGFloat = 5
        for index in 0 ..< min(filled + faint, 5) {
            let origin = CGPoint(x: x + CGFloat(index) * (size + 2), y: bounds.midY - size / 2)
            (index < filled ? color : color.withAlphaComponent(0.3)).setFill()
            NSBezierPath(ovalIn: CGRect(origin: origin, size: CGSize(width: size, height: size))).fill()
        }
    }

    private func drawLabel(_ content: ItemContent, at x: inout CGFloat, color: NSColor) {
        let text = content.label ?? module.shortLabel
        // Four letters only fit the bar when set smaller.
        let isLong = text.count > 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: isLong ? 5 : 6.5, weight: .bold),
            .foregroundColor: color,
        ]
        let letters = text.map { NSAttributedString(string: String($0), attributes: attributes) }
        let lineHeight: CGFloat = isLong ? 5.5 : 7
        var y = (bounds.height + lineHeight * CGFloat(letters.count)) / 2 - lineHeight - 1
        for letter in letters {
            letter.draw(at: CGPoint(x: x + (Self.labelWidth - letter.size().width) / 2, y: y))
            y -= lineHeight
        }
        x += Self.labelWidth + Self.padding
    }
}
