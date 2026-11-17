import SwiftUI

/// A short note at the bottom of Settings after an undo or redo, with the button that reverses it.
public struct SettingsToast: Equatable, Identifiable, Sendable {
    public let id = UUID()
    public let message: String
    public let actionTitle: String
    /// True when the button undoes; false when it redoes.
    public let isUndo: Bool

    public init(message: String, actionTitle: String, isUndo: Bool = false) {
        self.message = message
        self.actionTitle = actionTitle
        self.isUndo = isUndo
    }
}

public struct SettingsToastView: View {
    private let toast: SettingsToast
    private let action: () -> Void

    public init(_ toast: SettingsToast, action: @escaping () -> Void) {
        self.toast = toast
        self.action = action
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(toast.message).font(.system(size: 12))
            Button(toast.actionTitle, action: action)
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}
