import GlassWorkCore
import SwiftUI

/// The Counter card: the number, plus and minus, reset, and a title that can be edited.
struct CounterPanel: View {
    @Environment(\.panelActions) private var actions
    @State private var title: String?

    private var state: CounterState {
        CounterState(options: actions.moduleOptions(.counter))
    }

    var body: some View {
        let state = state
        DockCardFrame(module: .counter) {
            TextField(loc("Title"), text: Binding(get: { title ?? state.title }, set: { title = $0 }))
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitTitle)
            HStack(spacing: 14) {
                stepper("minus", help: loc("Subtract one")) { $0.decrement() }
                Text(state.value, format: .number.grouping(.never))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                stepper("plus", help: loc("Add one")) { $0.increment() }
            }
            HStack {
                Toggle(loc("Count on click"), isOn: Binding(
                    get: { state.countsOnClick },
                    set: { value in change { $0.countsOnClick = value } }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
                Button(loc("Reset")) { change { $0.reset() } }
                    .disabled(state.value == 0)
            }
            .font(.system(size: 12))
        }
        .onDisappear(perform: commitTitle)
    }

    private func stepper(_ symbol: String, help: String, _ action: @escaping (inout CounterState) -> Void)
        -> some View
    {
        Button {
            change(action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Palette.orange.opacity(0.18), in: .circle)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func change(_ edit: @escaping (inout CounterState) -> Void) {
        actions.updateSettings { $0.updateCounter(edit) }
    }

    private func commitTitle() {
        guard let new = title else { return }
        title = nil
        guard new != state.title else { return }
        change { $0.title = new }
    }
}
