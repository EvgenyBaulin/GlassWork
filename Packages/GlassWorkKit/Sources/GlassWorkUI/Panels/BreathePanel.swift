import GlassWorkCore
import SwiftUI

extension BreathingPhase {
    var title: String {
        switch self {
        case .inhale: loc("Breathe in")
        case .hold: loc("Hold")
        case .exhale: loc("Breathe out")
        }
    }
}

/// The circle and what it says. `moment` is nil while no session runs.
struct BreathingStage: View {
    let moment: BreathingCycle.Moment?
    let remaining: TimeInterval
    let isFinished: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                BreathingOrb(fullness: moment?.fullness ?? 0.5, size: 150)
                if let moment {
                    Text("\(moment.secondsLeft)")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
            Text(headline).font(.system(size: 15, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var headline: String {
        guard let moment else { return isFinished ? loc("Well done") : loc("Ready when you are") }
        return moment.phase.title
    }

    private var detail: String {
        moment == nil ? loc("In 4 s, hold 4 s, out 6 s") : loc("\(WidgetDuration.short(remaining)) left")
    }
}

/// The Breathe card: a guided cycle of a chosen length.
struct BreathePanel: View {
    @Environment(\.panelActions) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?
    @State private var isFinished = false
    @State private var timeout: Task<Void, Never>?

    private var session: BreathingSession {
        BreathingSession(options: actions.moduleOptions(.breathe))
    }

    var body: some View {
        let session = session
        DockCardFrame(module: .breathe) {
            stage(session)
            Picker(loc("Length"), selection: Binding(
                get: { session.minutes },
                set: { minutes in actions.updateSettings { setMinutes(minutes, in: &$0) } }
            )) {
                ForEach(BreathingSession.choices, id: \.self) { Text(loc("\($0) min")).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(startedAt != nil)
            Button(startedAt == nil ? loc("Start") : loc("Stop")) {
                if startedAt == nil {
                    start(session)
                } else {
                    stop()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.teal)
            .frame(maxWidth: .infinity)
        }
        // The timeline stops with the card, so nothing animates once it is closed.
        .onDisappear { stop() }
    }

    @ViewBuilder
    private func stage(_ session: BreathingSession) -> some View {
        if let startedAt {
            // Under Reduce Motion the circle changes once a second instead of every frame.
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30)) {
                let elapsed = $0.date.timeIntervalSince(startedAt)
                BreathingStage(
                    moment: session.moment(at: elapsed),
                    remaining: session.remaining(at: elapsed),
                    isFinished: false
                )
            }
        } else {
            BreathingStage(moment: nil, remaining: session.duration, isFinished: isFinished)
        }
    }

    private func setMinutes(_ minutes: Int, in settings: inout AppSettings) {
        settings.update(.breathe) { $0.options[BreathingSession.minutesKey] = minutes == BreathingSession.defaultMinutes
            ? nil
            : String(minutes)
        }
    }

    private func start(_ session: BreathingSession) {
        isFinished = false
        startedAt = Date()
        timeout = Task {
            try? await Task.sleep(for: .seconds(session.duration))
            guard !Task.isCancelled else { return }
            stop(finished: true)
        }
    }

    private func stop(finished: Bool = false) {
        timeout?.cancel()
        timeout = nil
        startedAt = nil
        isFinished = finished
    }
}
