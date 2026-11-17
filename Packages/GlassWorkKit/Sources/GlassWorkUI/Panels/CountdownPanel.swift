import GlassWorkCore
import SwiftUI

struct CountdownPanel: View {
    let monitor: SystemMonitor
    /// Fixed by tests; the panel reads the clock itself.
    var fixedNow: Date?
    @State private var title = ""
    @State private var date: Date
    @State private var repeats = DateRepeat.none
    @State private var editing: ImportantDate.ID?

    init(monitor: SystemMonitor, fixedNow: Date? = nil) {
        self.monitor = monitor
        self.fixedNow = fixedNow
        _date = State(initialValue: (fixedNow ?? Date()).addingTimeInterval(86400 * 7))
    }

    var body: some View {
        let store = monitor.everyday
        let now = fixedNow ?? Date()
        PanelFrame(module: .countdown, subtitle: loc("\(store.data.dates.count) dates")) {
            ForEach(store.data.sortedDates(from: now)) { item in
                if editing == item.id {
                    editor(item, store: store)
                } else {
                    row(item, now: now, store: store)
                }
            }
            Divider()
            TextField(loc("New date"), text: $title).textFieldStyle(.roundedBorder)
            DatePicker(loc("Date"), selection: $date, displayedComponents: .date)
            repeatPicker($repeats)
            Button(loc("Add")) {
                guard !title.isEmpty else { return }
                store.update { $0.dates.append(ImportantDate(title: title, date: date, repeats: repeats)) }
                title = ""
                repeats = .none
            }
        }
    }

    private func repeatPicker(_ selection: Binding<DateRepeat>) -> some View {
        Picker(loc("Repeat"), selection: selection) {
            Text(loc("None")).tag(DateRepeat.none)
            Text(loc("Yearly")).tag(DateRepeat.yearly)
            Text(loc("Monthly")).tag(DateRepeat.monthly)
        }
        .pickerStyle(.menu)
    }

    private func row(_ item: ImportantDate, now: Date, store: EverydayStore) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13, weight: .medium))
                Text(item.nextOccurrence(from: now).formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(loc("\(item.daysLeft(from: now)) days"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Button {
                editing = item.id
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(loc("Edit"))
            Button {
                store.update { $0.dates.removeAll { $0.id == item.id } }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func editor(_ item: ImportantDate, store: EverydayStore) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(loc("Title"), text: field(item, store, \.title)).textFieldStyle(.roundedBorder)
            DatePicker(loc("Date"), selection: field(item, store, \.date), displayedComponents: .date)
            repeatPicker(field(item, store, \.repeats))
            Button(loc("Done")) { editing = nil }
        }
    }

    private func field<Value>(
        _ item: ImportantDate,
        _ store: EverydayStore,
        _ path: WritableKeyPath<ImportantDate, Value>
    ) -> Binding<Value> {
        Binding(
            get: { store.data.dates.first { $0.id == item.id }?[keyPath: path] ?? item[keyPath: path] },
            set: { value in
                store.update { data in
                    if let index = data.dates.firstIndex(where: { $0.id == item.id }) {
                        data.dates[index][keyPath: path] = value
                    }
                }
            }
        )
    }
}
