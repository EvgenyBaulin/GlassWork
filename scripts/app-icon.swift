// Draws the app icon: four glass tiles on a blue squircle.
// Usage: xcrun swift scripts/app-icon.swift <output.png>   (1024×1024; `make app-icon` makes every size)
import AppKit
import CoreGraphics

let size: CGFloat = 1024
// macOS icon grid: the body is 824 pt wide, centred, with room for the shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: app-icon.swift <output.png>\n".utf8))
    exit(1)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Drop shadow under the body.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
context.addPath(squircle)
context.setFillColor(color(0x1B3A8C))
context.fillPath()
context.restoreGState()

// Body: deep blue to indigo, top to bottom.
context.saveGState()
context.addPath(squircle)
context.clip()
let background = CGGradient(
    colorsSpace: space,
    colors: [color(0x3F8CFF), color(0x2A4FD6), color(0x3B1F9E)] as CFArray,
    locations: [0, 0.55, 1]
)!
context.drawLinearGradient(
    background,
    start: CGPoint(x: body.midX, y: body.maxY),
    end: CGPoint(x: body.midX, y: body.minY),
    options: []
)
/// A soft light from the top left, as on glass.
let glow = CGGradient(
    colorsSpace: space,
    colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray,
    locations: [0, 1]
)!
context.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: body.minX + 180, y: body.maxY - 140),
    startRadius: 0,
    endCenter: CGPoint(x: body.minX + 180, y: body.maxY - 140),
    endRadius: 620,
    options: []
)
context.restoreGState()

// Four tiles: menu bar, widgets, Dock and the hub, one of them lit.
let tile: CGFloat = 250
let gap: CGFloat = 56
let origin = CGPoint(x: body.midX - tile - gap / 2, y: body.midY - tile - gap / 2)
let fills: [(x: Int, y: Int, alpha: CGFloat)] = [(0, 1, 0.96), (1, 1, 0.5), (0, 0, 0.5), (1, 0, 0.5)]
for item in fills {
    let rect = CGRect(
        x: origin.x + CGFloat(item.x) * (tile + gap),
        y: origin.y + CGFloat(item.y) * (tile + gap),
        width: tile,
        height: tile
    )
    let path = CGPath(roundedRect: rect, cornerWidth: 64, cornerHeight: 64, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0x0A1240, 0.35))
    context.addPath(path)
    context.setFillColor(color(0xFFFFFF, item.alpha))
    context.fillPath()
    context.restoreGState()
    // A thin bright edge keeps the faint tiles readable.
    context.addPath(path)
    context.setStrokeColor(color(0xFFFFFF, 0.55))
    context.setLineWidth(4)
    context.strokePath()
}

guard let image = context.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
