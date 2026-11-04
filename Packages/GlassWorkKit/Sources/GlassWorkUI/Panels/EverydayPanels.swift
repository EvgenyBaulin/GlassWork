import GlassWorkCore
import SwiftUI

struct TimersPanel: View {
    let monitor: SystemMonitor
    @State private var minutes = 10.0
    @Environment(\.panelActions) private var actions

    private var presets: [Int] {
        TimerPresets.parse(actions.moduleOptions(.timers)[ItemOption.timerPresets])
    }

    var body: some View {
        let store = monitor.everyday
        PanelFrame(module: .timers, subtitle: loc("\(store.data.timers.count) running")) {
            ForEach(store.data.timers) { timer in row(timer, store: store) }
            if store.data.timers.isEmpty {
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
                Button(loc("Start")) {
                    store.startTimer(title: loc("\(Int(minutes)) min"), duration: minutes * 60)
                }
            }
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

struct CountdownPanel: View {
    let monitor: SystemMonitor
    @State private var title = ""
    @State private var date = Date().addingTimeInterval(86400 * 7)

    var body: some View {
        let store = monitor.everyday
        let now = Date()
        PanelFrame(module: .countdown, subtitle: loc("\(store.data.dates.count) dates")) {
            ForEach(store.data.sortedDates(from: now)) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.system(size: 13, weight: .medium))
                        Text(item.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(loc("\(item.daysLeft(from: now)) days"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Button {
                        store.update { $0.dates.removeAll { $0.id == item.id } }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            Divider()
            TextField(loc("New date"), text: $title).textFieldStyle(.roundedBorder)
            DatePicker(loc("Date"), selection: $date, displayedComponents: .date)
            Button(loc("Add")) {
                guard !title.isEmpty else { return }
                store.update { $0.dates.append(ImportantDate(title: title, date: date)) }
                title = ""
            }
        }
    }
}

struct WorldClocksPanel: View {
    let monitor: SystemMonitor
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
        let zone = TimeZone(identifier: city.timeZone) ?? .current
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        var calendar = Calendar.current
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: Date())
        return HStack {
            Image(systemName: (7 ..< 20).contains(hour) ? "sun.max" : "moon")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(city.name).font(.system(size: 13))
            Spacer()
            Text(Date().formatted(style)).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
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
    @Environment(\.panelActions) private var actions

    var body: some View {
        let now = Date()
        PanelFrame(
            module: .date,
            subtitle: loc("Week \(DateItemText(options: actions.moduleOptions(.date)).week(of: now))")
        ) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 18, weight: .semibold))
            MonthGrid(month: now)
        }
    }
}

/// One month with today marked.
struct MonthGrid: View {
    let month: Date

    private var days: [Int?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + (1 ... count).map(Optional.some)
    }

    var body: some View {
        let today = Calendar.current.component(.day, from: month)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                Text(day.map(String.init) ?? "")
                    .font(.system(size: 12, weight: day == today ? .bold : .regular))
                    .monospacedDigit()
                    .frame(width: 24, height: 24)
                    .background(day == today ? Palette.red : .clear, in: Circle())
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
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
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

    var body: some View {
        let store = monitor.everyday
        PanelFrame(module: .colours, subtitle: "") {
            Button(loc("Pick a colour")) { pick(store) }
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
        NSColorSampler().show { color in
            guard let hex = color?.hexString else { return }
            MainActor.assumeIsolated {
                let limit = options.number(ItemOption.colourLimit, default: EverydayData.colorLimit)
                store.update { $0.addColor(hex, limit: limit) }
                copy(hex)
            }
        }
    }

    private func copy(_ hex: String) {
        NSPasteboard.general.clearContents()
        let text = options.choice(ItemOption.colourFormat, default: ColourFormat.hex).text(
            hex: hex,
            isUppercase: options.flag(ItemOption.colourUppercase, default: true),
            hasHash: options.flag(ItemOption.colourHash, default: true)
        )
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct DeviceBatteriesPanel: View {
    let monitor: SystemMonitor

    var body: some View {
        PanelFrame(module: .deviceBatteries, subtitle: "") {
            if monitor.deviceBatteries.isEmpty {
                Text(loc("No devices with a battery connected"))
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
            }
            ForEach(monitor.deviceBatteries) { device in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(device.name).font(.system(size: 13))
                        Spacer()
                        Text(Format.percent(device.charge)).monospacedDigit().font(.system(size: 13))
                    }
                    ThinBar(value: device.charge, tint: device.charge < 0.2 ? Palette.red : Palette.green)
                }
            }
        }
    }
}

struct EjectPanel: View {
    let monitor: SystemMonitor
    @Environment(\.panelActions) private var actions

    private var volumes: [DiskVolume] {
        monitor.volumes.filter(\.isEjectable)
    }

    var body: some View {
        PanelFrame(module: .eject, subtitle: loc("\(volumes.count) volumes")) {
            ForEach(volumes) { volume in
                HStack {
                    Image(systemName: "externaldrive").foregroundStyle(.secondary)
                    Text(volume.name).font(.system(size: 13))
                    Spacer()
                    Button(loc("Eject")) { eject(volume) }.controlSize(.small)
                }
            }
            if volumes.isEmpty {
                Text(loc("Nothing to eject")).foregroundStyle(.secondary).font(.system(size: 12))
            }
        }
    }

    private func eject(_ volume: DiskVolume) {
        try? NSWorkspace.shared.unmountAndEjectDevice(at: URL(filePath: volume.path))
        monitor.refresh()
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
