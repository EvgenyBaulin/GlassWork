import GlassWorkCore
import SwiftUI

/// The frame of the Counter, Breathe and Screen Time cards: the module's icon and name over the content.
struct DockCardFrame<Content: View>: View {
    let module: ModuleID
    @ViewBuilder let content: Content

    static var width: Double {
        340
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ModuleIcon(module, size: 24)
                Text(module.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(module.tint)
                Spacer()
            }
            content
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
    }
}

/// A soft circle that grows with the breath: `fullness` 0 is empty lungs, 1 is full.
struct BreathingOrb: View {
    let fullness: Double
    let size: CGFloat

    private var scale: Double {
        0.4 + 0.6 * min(max(fullness, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle().strokeBorder(Palette.teal.opacity(0.35), lineWidth: max(size / 40, 1))
            Circle()
                .fill(RadialGradient(
                    colors: [Palette.teal.opacity(0.85), Palette.cyan.opacity(0.45)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                ))
                .scaleEffect(scale)
        }
        .frame(width: size, height: size)
    }
}

/// The circle on the Dock tile. It swells slowly while the Dock shows it, and holds still under Reduce Motion.
struct BreathingTileOrb: View {
    let size: CGFloat
    let animates: Bool

    var body: some View {
        if animates {
            // A frame rate far below the display's: the tile is small and always on screen.
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                BreathingOrb(fullness: BreathingSession.idleFullness(at: context.date), size: size)
            }
        } else {
            BreathingOrb(fullness: 0.6, size: size)
        }
    }
}
