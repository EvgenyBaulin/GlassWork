import GlassWorkCore
import SwiftUI

/// The opened island when no event is on screen: the user's mini widgets, or the list to choose them from.
struct IslandMiniWidgetsCard: View {
    let store: IslandStore
    let actions: IslandActions
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if store.isEditingWidgets {
                editList
            } else {
                grid
                Button(loc("+ Add widget")) { store.isEditingWidgets = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.blue)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(store.isEditingWidgets ? loc("Choose your widgets") : loc("Opened by you · your widgets"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button(store.isEditingWidgets ? loc("Done") : loc("Edit")) {
                store.isEditingWidgets.toggle()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Palette.blue)
        }
    }

    private var visible: [IslandMiniReading] {
        store.miniWidgets.shown.compactMap { store.miniReadings[$0] }
    }

    @ViewBuilder
    private var grid: some View {
        if visible.isEmpty {
            Text(loc("Nothing to show yet")).font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(visible, id: \.widget) { tile($0) }
            }
        }
    }

    private func tile(_ reading: IslandMiniReading) -> some View {
        let widget = reading.widget
        return VStack(alignment: .leading, spacing: 3) {
            Text(widget.title.uppercased())
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(widget.tint).lineLimit(1)
            primary(reading).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(secondary(reading)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color(white: 0.085), in: .rect(cornerRadius: 12))
    }

    private func primary(_ reading: IslandMiniReading) -> Text {
        switch reading.widget {
        case .upNext: Text(reading.date.map(clock) ?? "")
        case .weather: Text("\(reading.value) · \(reading.condition?.title ?? "—")")
        default: Text(reading.value)
        }
    }

    private func secondary(_ reading: IslandMiniReading) -> String {
        if reading.widget == .weather, let high = reading.high, let low = reading.low {
            return "\(loc("H")) \(high) · \(loc("L")) \(low)"
        }
        return reading.detail
    }

    private func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }

    private var editList: some View {
        VStack(spacing: 6) {
            ForEach(IslandMiniWidget.allCases) { widget in
                let chosen = store.miniWidgets.contains(widget)
                HStack(spacing: 10) {
                    Button { toggle(widget) } label: {
                        Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(chosen ? widget.tint : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(widget.title)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                    Text(widget.title).font(.system(size: 13))
                    Spacer()
                    if chosen {
                        moveButton("chevron.up", widget, -1)
                        moveButton("chevron.down", widget, 1)
                    }
                }
                .padding(.horizontal, 11).frame(minHeight: 34)
                .background(Color(white: 0.075), in: .rect(cornerRadius: 11))
            }
        }
    }

    private func moveButton(_ symbol: String, _ widget: IslandMiniWidget, _ step: Int) -> some View {
        Button {
            var set = store.miniWidgets
            set.move(widget, by: step)
            commit(set)
        } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(step < 0 ? loc("Move up") : loc("Move down"))
    }

    private func toggle(_ widget: IslandMiniWidget) {
        var set = store.miniWidgets
        set.toggle(widget)
        commit(set)
    }

    private func commit(_ set: IslandMiniSet) {
        store.miniWidgets = set
        actions.setMiniWidgets(set)
    }
}

extension IslandMiniWidget {
    var title: String {
        switch self {
        case .upNext: loc("Up next")
        case .weather: loc("Weather")
        case .rates: loc("Rates")
        case .cpu: loc("CPU")
        case .memory: loc("Memory")
        case .battery: loc("Battery")
        }
    }

    var tint: Color {
        switch self {
        case .upNext: Palette.red
        case .weather: Palette.cyan
        case .rates: Palette.green
        case .cpu: Palette.orange
        case .memory: Palette.purple
        case .battery: Palette.yellow
        }
    }
}
