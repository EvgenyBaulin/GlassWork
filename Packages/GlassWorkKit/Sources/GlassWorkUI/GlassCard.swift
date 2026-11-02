import SwiftUI

/// Rounded Liquid Glass container used by menu bar panels and desktop widgets.
public struct GlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let content: Content

    public init(cornerRadius: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}
