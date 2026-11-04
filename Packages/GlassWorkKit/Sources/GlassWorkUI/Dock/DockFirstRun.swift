import GlassWorkCore
import SwiftUI

/// Explains what turning on the Dock does, before it hides the system one.
///
/// Says only what the app does: it restores the system Dock on quit and when turned off. There is no watchdog, so
/// after a crash the system Dock stays hidden until the app opens again.
public struct DockFirstRunView: View {
    private let proceed: () -> Void
    private let cancel: () -> Void

    public init(proceed: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.proceed = proceed
        self.cancel = cancel
    }

    private var points: [String] {
        [
            loc("Your current Dock apps are imported."),
            loc("Live widgets and app folders keep things tidy."),
            loc("Switch back any time: Settings → Dock."),
        ]
    }

    public var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Palette.purple.gradient, in: .rect(cornerRadius: 15))
            VStack(spacing: 10) {
                Text(loc("Replace the Dock with GlassWork Dock?"))
                    .font(.system(size: 20, weight: .semibold))
                Text(explanation)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(points, id: \.self) { point in
                    Label {
                        Text(point).font(.system(size: 13))
                    } icon: {
                        Image(systemName: "checkmark").foregroundStyle(Palette.green)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            HStack(spacing: 12) {
                Spacer()
                Button(loc("Not now"), action: cancel).keyboardShortcut(.cancelAction)
                Button(loc("Continue"), action: proceed)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 560)
    }

    private var explanation: String {
        [
            loc("While GlassWork Dock is on, the macOS Dock is hidden."),
            loc("When you quit GlassWork or turn its Dock off, the macOS Dock comes back as it was."),
            loc("If GlassWork ever crashes, the macOS Dock stays hidden until you open GlassWork again."),
        ].joined(separator: " ")
    }
}
