import GlassWorkCore
import SwiftUI

struct TimersPanel: View {
    let monitor: SystemMonitor
    @State private var minutes = 10.0
    @State private var typed = ""
    @Environment(\.panelActions) private var actions

    private var presets: [Int] {
        TimerPresets.parse(actions.moduleOptions(.timers)[ItemOption.timerPresets])
    }

    var body: some View {
        let store = monitor.everyday
        PanelFrame(module: .timers, subtitle: loc("\(store.data.timers.count) running")) {
            ForEach(store.data.finishedTimers) { timer in
                FinishedTimerRow(timer: timer) { store.dismissFinishedTimer(timer.id) }
            }
            ForEach(store.data.timers) { timer in row(timer, store: store) }
            if store.data.timers.isEmpty, store.data.finishedTimers.isEmpty {
                Text(loc("No timers running")).foregroundStyle(.secondary).font(.system(size: 12))
            }
            Divider()
            pomodoro(store)
            Divider()
            PanelSection(title: loc("Start a timer")) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 6) {
                    ForEach(presets, id: \.self) { value in
                        Button(loc("\(value) min")) {
                            store.startTimer(title: loc("\(value) min"), duration: TimeInterval(value * 60))
                        }
                        .controlSize(.small)
                    }
                }
                Stepper(value: $minutes, in: 1 ... 600) {
                    Text(loc("Custom: \(Int(minutes)) min")).font(.system(size: 12))
                }
                TextField(loc("Or type 25, 1:30 or 1h 5m"), text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { startCustom(store) }
                Button(loc("Start")) { startCustom(store) }
                    .disabled(!typed.isEmpty && TimerDuration.parse(typed) == nil)
            }
        }
    }

    private func startCustom(_ store: EverydayStore) {
        if typed.isEmpty {
            store.startTimer(title: loc("\(Int(minutes)) min"), duration: minutes * 60)
        } else if let seconds = TimerDuration.parse(typed) {
            store.startTimer(title: seconds.clockText, duration: seconds)
            typed = ""
        }
    }

    private func pomodoro(_ store: EverydayStore) -> some View {
        let session = store.data.pomodoro ?? PomodoroSession()
        let state = session.state(at: Date())
        return PanelSection(title: loc("Pomodoro")) {
            HStack {
                Text(state.map { loc("\($0.round) of \(session.roundsPerSet)") } ?? loc("Not started"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(session.isRunning ? loc("Stop") : loc("Start")) { store.togglePomodoro() }
            }
        }
    }

    private func row(_ timer: CountdownTimer, store: EverydayStore) -> some View {
        let left = timer.remaining(at: Date())
        return HStack(spacing: 10) {
            RingGauge(value: left / max(timer.duration, 1), tint: Palette.orange, lineWidth: 3)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(left.clockText).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(timer.title).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.update { data in
                    if let index = data.timers.firstIndex(where: { $0.id == timer.id }) {
                        data.timers[index].togglePause(at: Date())
                    }
                }
            } label: {
                Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.plain)
            Button {
                store.update { $0.timers.removeAll { $0.id == timer.id } }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

/// A timer that ran out. It stays until it is dismissed.
struct FinishedTimerRow: View {
    let timer: FinishedTimer
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Palette.green)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(loc("Done")).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("\(timer.title) · \(timer.finishedAt.timeText)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(loc("Dismiss"), action: dismiss).controlSize(.small)
        }
    }
}

struct NotesPanel: View {
    let monitor: SystemMonitor
    @Environment(\.panelActions) private var actions

    var body: some View {
        let store = monitor.everyday
        let options = actions.moduleOptions(.notes)
        let isMono = options.choice(ItemOption.notesFont, default: NotesFont.system) == .mono
        PanelFrame(module: .notes, subtitle: "") {
            TextEditor(text: Binding(
                get: { store.data.note },
                set: { value in store.update { $0.note = value } }
            ))
            .font(.system(size: 13, design: isMono ? .monospaced : .default))
            .scrollContentBackground(.hidden)
            .frame(height: options.choice(ItemOption.panelSize, default: PanelSize.medium).noteHeight)
        }
    }
}

/// How far a city is from local time.
enum WorldClockOffset {
    /// `+3 h`, `−8 h`, `+5:30 h`; nothing to say when it is the same time.
    static func text(_ seconds: Int) -> String {
        guard seconds != 0 else { return loc("Same time") }
        let minutes = abs(seconds) / 60
        let clock = minutes % 60 == 0 ? "\(minutes / 60)" : "\(minutes / 60):" + String(format: "%02d", minutes % 60)
        return loc("\(seconds < 0 ? "−" : "+")\(clock) h")
    }
}

struct WorldClocksPanel: View {
    let monitor: SystemMonitor
    /// Fixed by tests; the panel reads the clock itself.
    var fixedNow: Date?
    @State private var query = ""

    private var matches: [String] {
        guard query.count > 1 else { return [] }
        return TimeZone.knownTimeZoneIdentifiers
            .filter { $0.localizedCaseInsensitiveContains(query.replacing(" ", with: "_")) }
            .prefix(6)
            .map(\.self)
    }

    var body: some View {
        let store = monitor.everyday
        PanelFrame(module: .worldClocks, subtitle: "") {
            ForEach(store.data.cities) { city in row(city, store: store) }
            Divider()
            TextField(loc("Add a city"), text: $query).textFieldStyle(.roundedBorder)
            ForEach(matches, id: \.self) { zone in
                Button(zone.replacing("_", with: " ")) {
                    let name = zone.split(separator: "/").last.map(String.init) ?? zone
                    let city = WorldCity(name: name.replacing("_", with: " "), timeZone: zone)
                    store.update { $0.cities.append(city) }
                    query = ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
            }
        }
    }

    private func row(_ city: WorldCity, store: EverydayStore) -> some View {
        let zone = city.localOrZone
        let now = fixedNow ?? Date()
        var style = Date.FormatStyle(date: .omitted, time: .shortened).regional
        style.timeZone = zone
        var calendar = Calendar.current
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: now)
        return HStack {
            Image(systemName: (7 ..< 20).contains(hour) ? "sun.max" : "moon")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(city.name).font(.system(size: 13))
            Text(WorldClockOffset.text(city.offset(at: now)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(now.formatted(style)).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
            VStack(spacing: 0) {
                Button {
                    store.update { $0.moveCity(city.id, by: -1) }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(store.data.cities.first?.id == city.id)
                .help(loc("Move up"))
                Button {
                    store.update { $0.moveCity(city.id, by: 1) }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(store.data.cities.last?.id == city.id)
                .help(loc("Move down"))
            }
            .buttonStyle(.plain)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            Button {
                store.update { $0.cities.removeAll { $0.id == city.id } }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

struct DatePanel: View {
    let monitor: SystemMonitor
    /// Set by tests, which need the same month on every run.
    var moment: Date?
    /// Set by tests in place of what the Calendar app has.
    var eventDays: Set<Int>?
    @Environment(\.panelActions) private var actions
    @State private var loadedDays: Set<Int> = []

    var body: some View {
        let now = moment ?? Date()
        PanelFrame(
            module: .date,
            subtitle: loc("Week \(DateItemText(options: actions.moduleOptions(.date)).week(of: now))")
        ) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 18, weight: .semibold))
            MonthGrid(month: now, eventDays: eventDays ?? loadedDays, showsWeeks: true)
        }
        .task { loadedDays = monitor.agenda.eventDays(in: now) }
    }
}

private struct MonthGridCell: Identifiable {
    enum Content { case week(Int), day(Int?) }

    let id: Int
    let content: Content
}

/// One month with today marked. Panels can add ISO week numbers and a dot under days that have events.
struct MonthGrid: View {
    let month: Date
    var eventDays: Set<Int> = []
    var showsWeeks = false

    private static let weekWidth: CGFloat = 20

    private var columns: [GridItem] {
        let days = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return showsWeeks ? [GridItem(.fixed(Self.weekWidth), spacing: 2)] + days : days
    }

    var body: some View {
        let today = Calendar.current.component(.day, from: month)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(cells) { item in
                switch item.content {
                case let .week(number):
                    Text("\(number)")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: Self.weekWidth, height: 24)
                case let .day(day):
                    cell(day, isToday: day == today)
                }
            }
        }
    }

    /// Week numbers and days in one flat list, so the grid sees plain cells with stable ids.
    private var cells: [MonthGridCell] {
        var items: [MonthGridCell.Content] = []
        for row in MonthRows.rows(for: month) {
            if showsWeeks {
                items.append(.week(row.week))
            }
            items += row.days.map { .day($0) }
        }
        return items.enumerated().map { MonthGridCell(id: $0.offset, content: $0.element) }
    }

    private func cell(_ day: Int?, isToday: Bool) -> some View {
        Text(day.map(String.init) ?? "")
            .font(.system(size: 12, weight: isToday ? .bold : .regular))
            .monospacedDigit()
            .frame(width: 24, height: 24)
            .background(isToday ? Palette.red : .clear, in: Circle())
            .overlay(alignment: .bottom) {
                if let day, eventDays.contains(day) {
                    Circle()
                        .fill(isToday ? Color.white : Palette.red)
                        .frame(width: 3, height: 3)
                        .padding(.bottom, 2)
                }
            }
    }
}

struct SunMoonPanel: View {
    let monitor: SystemMonitor
    /// Set by tests, which need the same sky on every run.
    var moment: Date?
    @Environment(\.panelActions) private var actions

    var body: some View {
        let now = moment ?? Date()
        let place = monitor.sunPlace
        PanelFrame(module: .sunMoon, subtitle: place.map(title) ?? "") {
            if let place {
                sun(place, now: now)
            } else {
                PanelMessage(
                    symbol: "mappin.slash",
                    title: loc("No city yet"),
                    detail: loc("Add a city in Weather to see sunrise and sunset.")
                )
                Button(loc("Weather Settings…")) { actions.openSettings(.weather) }
                    .frame(maxWidth: .infinity)
            }
            Divider()
            HStack {
                Image(systemName: Astronomy.moonPhase(at: now).symbol).font(.system(size: 26))
                Text(loc("Moon \(Format.percent(Astronomy.moonIllumination(at: now)))"))
                    .font(.system(size: 13))
            }
        }
    }

    private func title(_ place: WeatherPlace) -> String {
        place.isCurrentLocation ? loc("Current location") : place.name
    }

    @ViewBuilder
    private func sun(_ place: WeatherPlace, now: Date) -> some View {
        let times = Astronomy.sunTimes(on: now, latitude: place.latitude, longitude: place.longitude)
        InfoRow(title: loc("Sunrise"), value: text(times.sunrise))
        InfoRow(title: loc("Sunset"), value: text(times.sunset))
        if let daylight = times.daylight {
            InfoRow(title: loc("Daylight"), value: CompactDuration.format(daylight))
        }
    }

    private func text(_ date: Date?) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened).regional
        style.timeZone = monitor.sunZone
        return date?.formatted(style) ?? "—"
    }
}

struct ColoursPanel: View {
    let monitor: SystemMonitor
    @Environment(\.panelActions) private var actions

    private var options: [String: String] {
        actions.moduleOptions(.colours)
    }

    private var format: ColourFormat {
        options.choice(ItemOption.colourFormat, default: ColourFormat.hex)
    }

    var body: some View {
        let store = monitor.everyday
        PanelFrame(module: .colours, subtitle: "") {
            Button(loc("Pick a colour")) { pick(store) }
            ColourFormatPicker(format: format) { value in
                actions.updateSettings { settings in
                    settings.update(.colours) { $0.options[ItemOption.colourFormat] = value.rawValue }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 6) {
                ForEach(store.data.colors, id: \.self) { hex in
                    Button {
                        copy(hex)
                    } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 4).fill(Color(hex: hex)).frame(width: 18, height: 18)
                            Text(hex).font(.system(size: 12, design: .monospaced))
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pick(_ store: EverydayStore) {
        ColourPicking.pick(store: store, options: options)
    }

    private func copy(_ hex: String) {
        ColourPicking.copy(hex, store: monitor.everyday, options: options)
    }
}

/// What a click on a colour copies. The choice is the same one as in Settings.
struct ColourFormatPicker: View {
    let format: ColourFormat
    let select: (ColourFormat) -> Void

    var body: some View {
        Picker(loc("Copy as"), selection: Binding(get: { format }, set: select)) {
            Text("HEX").tag(ColourFormat.hex)
            Text("RGB").tag(ColourFormat.rgb)
            Text("HSL").tag(ColourFormat.hsl)
            Text("SwiftUI").tag(ColourFormat.swiftUI)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
    }
}

struct DeviceBatteriesPanel: View {
    let monitor: SystemMonitor

    var body: some View {
        PanelFrame(module: .deviceBatteries, subtitle: "") {
            DeviceBatteryList(devices: monitor.deviceBatteries, hasRead: monitor.hasReadDevices)
        }
    }
}

/// Accessory batteries, or what is happening instead: the first read still running, or no devices.
struct DeviceBatteryList: View {
    let devices: [DeviceBattery]
    let hasRead: Bool

    var body: some View {
        if !hasRead {
            Text(loc("Looking for devices…"))
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
        } else if devices.isEmpty {
            Text(loc("No devices with a battery connected"))
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
        }
        ForEach(devices) { device in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.name).font(.system(size: 13))
                    Spacer()
                    if device.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.green)
                            .help(loc("Charging"))
                    }
                    Text(Format.percent(device.charge)).monospacedDigit().font(.system(size: 13))
                }
                ThinBar(value: device.charge, tint: device.charge < 0.2 ? Palette.red : Palette.green)
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            red: Double(value >> 16 & 0xFF) / 255,
            green: Double(value >> 8 & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension NSColor {
    /// "#RRGGBB" in sRGB.
    var hexString: String? {
        guard let color = usingColorSpace(.sRGB) else { return nil }
        let parts = [color.redComponent, color.greenComponent, color.blueComponent]
            .map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", parts[0], parts[1], parts[2])
    }
}
