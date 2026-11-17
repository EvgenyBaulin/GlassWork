import ApplicationServices
import GlassWorkCore
import SwiftUI

/// Explains what turning on the Dock does, before it hides the system one.
///
/// Says only what the app does: it restores the system Dock on quit, on SIGTERM and when turned off. A crash that
/// cannot be caught leaves it hidden until the app opens again, and the app then puts it back at once.
///
/// Then it waits for Accessibility, which badges and the window menu need, and offers a preset to start from. Both
/// steps are skipped when they have nothing to ask: Accessibility already granted, no presets passed in.
public struct DockFirstRunView: View {
    private let presets: [DockPreset]
    private let isTrusted: () -> Bool
    private let openAccessibilitySettings: () -> Void
    private let proceed: () -> Void
    private let applyPreset: (DockPreset) -> Void
    private let cancel: () -> Void
    @State private var step: DockFirstRunStep
    @State private var chosen: String?
    @State private var trusted: Bool

    /// - Parameters:
    ///   - presets: The presets to choose from. With none, there is no preset step.
    ///   - isTrusted: Whether Accessibility is granted. Asked once a second on the waiting step.
    ///   - proceed: Turns the Dock on.
    ///   - applyPreset: Runs after `proceed`, with the preset chosen, if one was.
    public init(
        presets: [DockPreset] = [],
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        openAccessibilitySettings: @escaping () -> Void = DockFirstRunView.openSystemSettings,
        startingAt step: DockFirstRunStep = .intro,
        proceed: @escaping () -> Void,
        applyPreset: @escaping (DockPreset) -> Void = { _ in },
        cancel: @escaping () -> Void
    ) {
        self.presets = presets
        self.isTrusted = isTrusted
        self.openAccessibilitySettings = openAccessibilitySettings
        self.proceed = proceed
        self.applyPreset = applyPreset
        self.cancel = cancel
        _step = State(initialValue: step)
        _trusted = State(initialValue: isTrusted())
    }

    public nonisolated static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private var points: [String] {
        [
            loc("Your current Dock apps are imported."),
            loc("Live widgets and app folders keep things tidy."),
            loc("Switch back any time: Settings → Dock."),
        ]
    }

    public var body: some View {
        Group {
            switch step {
            case .intro: intro
            case .accessibility: accessibility
            case .preset: presetChoice
            }
        }
        .padding(28)
        .frame(width: 560)
    }

    private func advance() {
        if let next = step.next(isTrusted: trusted, hasPresets: !presets.isEmpty) {
            step = next
        } else {
            finish()
        }
    }

    private func finish() {
        proceed()
        if let chosen, let preset = presets.first(where: { $0.id == chosen }) {
            applyPreset(preset)
        }
    }

    private var intro: some View {
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
                Button(loc("Continue"), action: advance)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var explanation: String {
        [
            loc("While GlassWork Dock is on, the macOS Dock is hidden."),
            loc("When you quit GlassWork or turn its Dock off, the macOS Dock comes back as it was."),
            loc("If GlassWork ever crashes, the macOS Dock stays hidden until you open GlassWork again."),
        ].joined(separator: " ")
    }
}

/// The waiting step and the preset step.
private extension DockFirstRunView {
    var accessibility: some View {
        VStack(spacing: 18) {
            Image(systemName: trusted ? "checkmark.shield" : "hand.raised")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background((trusted ? Palette.green : Palette.purple).gradient, in: .rect(cornerRadius: 15))
            VStack(spacing: 10) {
                Text(loc("Allow Accessibility for the full Dock"))
                    .font(.system(size: 20, weight: .semibold))
                Text(loc(
                    "Accessibility shows app badges, lists an app's windows and brings one forward. Without it the Dock works in limited mode: no badges and no window list."
                ))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if trusted {
                    Label(loc("Accessibility is on"), systemImage: "checkmark")
                        .foregroundStyle(Palette.green)
                } else {
                    ProgressView().controlSize(.small)
                    Text(loc("Waiting for permission…")).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
            HStack(spacing: 12) {
                Button(loc("Not now"), action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                if trusted {
                    Button(loc("Continue"), action: advance)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(loc("Continue in limited mode"), action: advance)
                    Button(loc("Open Accessibility Settings"), action: openAccessibilitySettings)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        // Granting it takes a trip to System Settings, so look again every second while this is showing.
        .task {
            while !Task.isCancelled, !trusted {
                try? await Task.sleep(for: .seconds(1))
                trusted = isTrusted()
            }
        }
    }

    var presetChoice: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text(loc("Start from a preset?"))
                    .font(.system(size: 20, weight: .semibold))
                Text(
                    loc(
                        "A preset adds widgets and folders. Your apps stay as they are. Change it any time in Settings → Dock."
                    )
                )
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 6) {
                presetRow(id: nil, title: loc("No Preset"))
                ForEach(presets) { preset in
                    presetRow(id: preset.id, title: preset.title)
                }
            }
            HStack(spacing: 12) {
                Button(loc("Not now"), action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(loc("Turn On Dock"), action: finish)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    func presetRow(id: String?, title: String) -> some View {
        Button {
            chosen = id
        } label: {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                if chosen == id {
                    Image(systemName: "checkmark").foregroundStyle(Palette.purple)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                chosen == id ? Palette.purple.opacity(0.18) : Color.primary.opacity(0.06),
                in: .rect(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }
}
