import GlassWorkCore
import SwiftUI

/// The red badge in a tile's top corner.
struct DockBadgeView: View {
    let text: String
    let size: CGFloat

    var body: some View {
        let height = max(size * 0.38, 14)
        Text(text)
            .font(.system(size: height * 0.62, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, height * 0.3)
            .frame(minWidth: height, minHeight: height)
            .background(.red.gradient, in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            .accessibilityLabel(text)
    }
}

/// A ring that swells and fades around an icon that wants attention. Still, under Reduce Motion.
struct AttentionPulse: ViewModifier {
    let isActive: Bool
    let size: CGFloat
    /// A fixed phase from 0 to 1 in place of the motion, for snapshots.
    var pose: Double?
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    func body(content: Content) -> some View {
        if isActive {
            let size = size
            let still = reducesMotion && pose == nil
            content.keyframeAnimator(initialValue: pose ?? 0, repeating: pose == nil && !reducesMotion) { view, phase in
                view.overlay { Self.ring(phase: still ? 0.5 : phase, size: size) }
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1, duration: 0.7)
                    CubicKeyframe(0, duration: 0.7)
                }
            }
        } else {
            content
        }
    }

    private nonisolated static func ring(phase: Double, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size / 4.5)
            .strokeBorder(.white.opacity(0.9 - 0.5 * phase), lineWidth: 2)
            .frame(width: size, height: size)
            .scaleEffect(1 + 0.18 * phase)
    }
}

/// A tile's badge, attention pulse and dimming when its app is hidden. Nothing for a tile with a plain state, so it
/// draws exactly as before.
struct DockTileDecoration: ViewModifier {
    let state: DockTileState
    let size: CGFloat
    var pulse: Double?

    func body(content: Content) -> some View {
        content
            .opacity(state.isHidden ? 0.45 : 1)
            .modifier(AttentionPulse(isActive: state.needsAttention, size: size, pose: pulse))
            .overlay(alignment: .topTrailing) {
                if let badge = state.badge {
                    DockBadgeView(text: badge, size: size)
                        .offset(x: size * 0.14, y: -size * 0.14)
                }
            }
    }
}
