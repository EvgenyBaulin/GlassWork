import GlassWorkCore
import SwiftUI

extension WeatherCondition {
    var title: String {
        switch self {
        case .clear: loc("Clear")
        case .partlyCloudy: loc("Partly cloudy")
        case .cloudy: loc("Cloudy")
        case .fog: loc("Fog")
        case .drizzle: loc("Drizzle")
        case .rain: loc("Rain")
        case .freezingRain: loc("Freezing rain")
        case .snow: loc("Snow")
        case .showers: loc("Showers")
        case .snowShowers: loc("Snow showers")
        case .thunderstorm: loc("Thunderstorm")
        case .unknown: "—"
        }
    }

    /// Fixed colors for a glyph, as in the design: sun warm, rain cool, cloud neutral.
    var tint: Color {
        switch self {
        case .clear, .partlyCloudy: Palette.yellow
        case .drizzle, .rain, .showers, .freezingRain, .thunderstorm: Palette.cyan
        default: .secondary
        }
    }
}

extension UVLevel {
    var title: String {
        switch self {
        case .low: loc("Low")
        case .moderate: loc("Moderate")
        case .high: loc("High")
        case .veryHigh: loc("Very high")
        case .extreme: loc("Extreme")
        }
    }
}

extension Format {
    static func windSpeed(_ metresPerSecond: Double) -> String {
        Measurement(value: metresPerSecond, unit: UnitSpeed.metersPerSecond).formatted(
            .measurement(width: .abbreviated, usage: .wind, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
    }
}

/// Today and the week ahead for one place, or the list of places.
struct WeatherPanel: View {
    let store: WeatherStore
    @State private var isEditing = false
    @State private var selectedID: WeatherPlace.ID?
    @Environment(\.panelActions) private var actions

    private var shown: WeatherReport? {
        selectedID.flatMap { id in store.reports.first { $0.place.id == id } } ?? store.primaryReport
    }

    var body: some View {
        PanelFrame(
            module: .weather,
            subtitle: subtitle,
            footerTitle: isEditing ? loc("Done") : loc("Locations"),
            footerAction: { isEditing.toggle() }
        ) {
            if isEditing {
                WeatherLocations(store: store) { place in
                    selectedID = place.id
                    isEditing = false
                }
            } else if store.places.isEmpty {
                firstRun
            } else {
                forecast
            }
        }
    }

    private var subtitle: String {
        guard !isEditing, let shown else { return "Open-Meteo" }
        let time = shown.fetchedAt.formatted(date: .omitted, time: .shortened)
        return store.isStale ? loc("Last update \(time)") : loc("Updated \(time)")
    }

    /// Nothing happens until the user chooses, so macOS is not asked for the position on its own.
    private var firstRun: some View {
        PanelEmptyState(
            symbol: "location",
            title: loc("Use your current location?"),
            message: loc("Your location is used only to ask Open-Meteo for the forecast.")
        ) {
            Button(loc("Allow Location")) {
                actions.updateSettings { $0.weather.useCurrentLocation = true }
            }
            .buttonStyle(.borderedProminent)
            Button(loc("Use a city instead")) { isEditing = true }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.blue)
                .font(.system(size: 12))
        }
    }

    @ViewBuilder
    private var forecast: some View {
        banner
        if let shown {
            WeatherForecast(report: shown, isStale: store.isStale)
        } else if store.status == .loading || store.status == .idle {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 40)
        }
    }

    @ViewBuilder
    private var banner: some View {
        let last = shown?.fetchedAt.formatted(date: .omitted, time: .shortened)
        if store.locationStatus == .denied {
            PanelBanner(
                symbol: "location.slash",
                title: loc("Location is off"),
                message: loc("Allow GlassWork in System Settings, or add a city.")
            )
        }
        switch store.status {
        case .offline:
            PanelBanner(
                symbol: "icloud.slash",
                title: loc("You’re offline"),
                message: last.map { loc("Showing data from \($0)") } ?? loc("No saved forecast yet"),
                actionTitle: loc("Retry"),
                action: retry
            )
        case .failed:
            PanelBanner(
                symbol: "exclamationmark.triangle",
                title: loc("Forecast unavailable"),
                message: last.map { loc("Showing data from \($0)") } ?? loc("Open-Meteo did not answer"),
                actionTitle: loc("Try again"),
                action: retry
            )
        default:
            EmptyView()
        }
    }

    private func retry() {
        Task { await store.retry() }
    }
}

/// Everything shown for one report. Times read in the place's own zone.
struct WeatherForecast: View {
    let report: WeatherReport
    var isStale = false
    @State private var hoveredDay: Date?

    init(report: WeatherReport, isStale: Bool = false, hoveredDay: Date? = nil) {
        self.report = report
        self.isStale = isStale
        _hoveredDay = State(initialValue: hoveredDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary
            if !isStale {
                details
            }
            hours
            if !isStale {
                days
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(placeName).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Text(conditionLine).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: report.current.condition.symbol(isDay: report.current.isDay))
                .font(.system(size: 26))
                .foregroundStyle(report.current.condition.tint)
            BigFigure(text: Format.degrees(report.current.temperature))
        }
        .opacity(isStale ? 0.6 : 1)
    }

    private var placeName: String {
        report.place.isCurrentLocation ? loc("Current location") : report.place.name
    }

    private var conditionLine: String {
        guard let today = report.days.first else { return report.current.condition.title }
        let high = Format.degrees(today.high)
        let low = Format.degrees(today.low)
        return "\(report.current.condition.title) · \(loc("H \(high)  L \(low)"))"
    }

    private var details: some View {
        HStack(alignment: .top) {
            detail(loc("Feels"), Format.degrees(report.current.feelsLike))
            detail(loc("Wind"), Format.windSpeed(report.current.windSpeed))
            detail(loc("Humidity"), Format.percent(report.current.humidity / 100))
            let index = Int(report.current.uvIndex.rounded())
            detail(loc("UV"), "\(index) \(UVLevel(index: report.current.uvIndex).title)")
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hours: some View {
        HStack(spacing: 0) {
            ForEach(Array(report.hours.prefix(7).enumerated()), id: \.element.id) { index, hour in
                VStack(spacing: 6) {
                    Text(index == 0 && !isStale ? loc("Now") : hourLabel(hour.date))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Image(systemName: hour.condition.symbol(isDay: hour.isDay))
                        .font(.system(size: 15))
                        .foregroundStyle(hour.condition.tint)
                        .frame(height: 18)
                    Text(Format.degrees(hour.temperature)).font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 10))
        .opacity(isStale ? 0.6 : 1)
    }

    private func hourLabel(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted).hour(.defaultDigits(amPM: .omitted))
        style.timeZone = report.zone
        return date.formatted(style)
    }

    private var days: some View {
        PanelSection(title: loc("7-day forecast")) {
            VStack(spacing: 7) {
                ForEach(Array(report.days.enumerated()), id: \.element.id) { index, day in
                    dayRow(day, isToday: index == 0)
                        .zIndex(hoveredDay == day.date ? 1 : 0)
                }
            }
        }
    }

    private func dayRow(_ day: DayForecast, isToday: Bool) -> some View {
        HStack(spacing: 8) {
            Text(isToday ? loc("Today") : dayLabel(day.date))
                .font(.system(size: 12, weight: .medium))
                .frame(width: 46, alignment: .leading)
                .lineLimit(1)
            Image(systemName: day.condition.symbol(isDay: true))
                .font(.system(size: 13))
                .foregroundStyle(day.condition.tint)
                .frame(width: 20)
            Text(Format.degrees(day.low))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
            DayRangeBar(
                low: day.low,
                high: day.high,
                scale: report.temperatureRange ?? day.low ... max(day.high, day.low + 1),
                current: isToday ? report.current.temperature : nil,
                isDimmed: hoveredDay != nil && hoveredDay != day.date
            )
            Text(Format.degrees(day.high))
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, alignment: .trailing)
        }
        .contentShape(.rect)
        .onHover { isInside in
            hoveredDay = isInside ? day.date : hoveredDay == day.date ? nil : hoveredDay
        }
        .overlay(alignment: .topTrailing) {
            if hoveredDay == day.date {
                tooltip(day).offset(y: -58).allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: hoveredDay)
    }

    private func tooltip(_ day: DayForecast) -> some View {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = report.zone
        return ChartTooltip(
            date: day.date,
            rows: [
                .init(id: "high", title: loc("Highest"), value: Format.degrees(day.high), color: Palette.orange),
                .init(id: "low", title: loc("Lowest"), value: Format.degrees(day.low), color: Palette.cyan),
            ],
            dateStyle: style
        )
        .fixedSize()
    }

    private func dayLabel(_ date: Date) -> String {
        var style = Date.FormatStyle().weekday(.abbreviated)
        style.timeZone = report.zone
        return date.formatted(style)
    }
}

/// City search and the list of places. The first place shows in the menu bar.
struct WeatherLocations: View {
    let store: WeatherStore
    let onSelect: (WeatherPlace) -> Void
    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var searchFailed = false
    @Environment(\.panelActions) private var actions

    private static let rowHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(loc("Search for a city"), text: $query)
                .textFieldStyle(.roundedBorder)
                .task(id: query) { await search() }
            suggestions
            Toggle(loc("Use current location"), isOn: currentLocation)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)
            PanelSection(title: loc("Your locations")) {
                List {
                    ForEach(store.settings.places) { place in
                        row(place)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove(perform: move)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: min(CGFloat(store.settings.places.count) * Self.rowHeight, 220))
            }
            Text(loc("Drag to reorder · the first one shows in the menu bar"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var currentLocation: Binding<Bool> {
        Binding(
            get: { store.settings.useCurrentLocation },
            set: { value in actions.updateSettings { $0.weather.useCurrentLocation = value } }
        )
    }

    @ViewBuilder
    private var suggestions: some View {
        if searchFailed {
            Text(loc("Search is unavailable right now")).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        ForEach(results) { place in
            Button {
                add(place)
            } label: {
                HStack {
                    Text(place.name).font(.system(size: 12, weight: .semibold))
                    Text(place.country).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "plus")
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(store.settings.places.contains { $0.id == place.id })
        }
    }

    private func row(_ place: WeatherPlace) -> some View {
        let report = store.report(for: place)
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal").font(.system(size: 11)).foregroundStyle(.tertiary)
            Button {
                onSelect(place)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(place.country).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if let report {
                Image(systemName: report.current.condition.symbol(isDay: report.current.isDay))
                    .foregroundStyle(report.current.condition.tint)
                Text(Format.degrees(report.current.temperature))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            }
            Button {
                actions.updateSettings { $0.weather.places.removeAll { $0.id == place.id } }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(loc("Remove"))
        }
    }

    /// Waits for a pause in typing; a new keystroke cancels this through `task(id:)`.
    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        searchFailed = false
        guard text.count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            results = try await store.search(text)
        } catch {
            results = []
            searchFailed = !Task.isCancelled
        }
    }

    private func add(_ place: WeatherPlace) {
        actions.updateSettings { $0.weather.places.append(place) }
        query = ""
        results = []
    }

    private func move(from source: IndexSet, to destination: Int) {
        actions.updateSettings { $0.weather.places.move(fromOffsets: source, toOffset: destination) }
    }
}
