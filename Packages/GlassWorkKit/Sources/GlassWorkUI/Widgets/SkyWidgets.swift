import GlassWorkCore
import SwiftUI

/// The place the sun-based widgets look at, from Weather. Without one they say so instead of guessing a city.
struct SunPlace {
    let name: String
    let latitude: Double
    let longitude: Double

    init?(_ snapshot: WidgetSnapshot) {
        guard let place = snapshot.place else { return nil }
        name = place.isCurrentLocation ? loc("Current location") : place.name
        latitude = place.latitude
        longitude = place.longitude
    }

    func sky(at date: Date) -> SkyState {
        SkyState(date: date, latitude: latitude, longitude: longitude)
    }
}

/// What a sun-based widget shows until Weather has a city.
struct NoCityMessage: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "mappin.slash").font(.system(size: 22)).foregroundStyle(.secondary)
            Text(loc("Add a city in Weather"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ChartSeries {
    /// Daylight length per day, on the shared interactive chart.
    static func daylight(_ days: [DaylightDay]) -> ChartSeries {
        var history = History<Double>(capacity: max(days.count, 1))
        for day in days {
            history.append(day.seconds, at: day.date)
        }
        return ChartSeries(
            id: "daylight",
            title: loc("Daylight"),
            color: Palette.yellow,
            points: history.points
        ) { CompactDuration.format($0) }
    }
}

private func timeText(_ date: Date?) -> String {
    date?.formatted(date: .omitted, time: .shortened) ?? "—"
}

/// Half-circle path of the sun with a dot at its position.
struct SunArc: View {
    let progress: Double
    let isMoon: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let radius = min(width / 2, geometry.size.height) - 8
            let center = CGPoint(x: width / 2, y: geometry.size.height - 4)
            let angle = Double.pi * (1 - min(max(progress, 0), 1))
            ZStack {
                Path { path in
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(180),
                        endAngle: .degrees(0),
                        clockwise: false
                    )
                }
                .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                Path { path in
                    path.move(to: CGPoint(x: center.x - radius - 10, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + radius + 10, y: center.y))
                }
                .stroke(.white.opacity(0.35), lineWidth: 1)
                Image(systemName: isMoon ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isMoon ? Color.white : Palette.yellow)
                    .position(x: center.x + radius * cos(angle), y: center.y - radius * sin(angle))
            }
        }
    }
}

/// Sun and moon over a city, on a sky that follows the hour.
struct SkyClockWidget: View {
    let context: TimeContext
    let place: SunPlace

    private var now: Date {
        context.now
    }

    private var sky: SkyState {
        place.sky(at: now)
    }

    private var colors: [Color] {
        switch sky.phase {
        case .night: [Color(red: 0.04, green: 0.05, blue: 0.16), Color(red: 0.12, green: 0.10, blue: 0.30)]
        case .dawn: [Color(red: 0.30, green: 0.25, blue: 0.55), Color(red: 0.98, green: 0.62, blue: 0.40)]
        case .day: [Color(red: 0.16, green: 0.45, blue: 0.85), Color(red: 0.45, green: 0.75, blue: 0.95)]
        case .dusk: [Color(red: 0.25, green: 0.20, blue: 0.50), Color(red: 0.95, green: 0.45, blue: 0.35)]
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            skyPanel
            if context.size == .extraLarge {
                otherCities
            }
        }
    }

    private var skyPanel: some View {
        let state = sky
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(place.name).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(now.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.8)
            }
            Text(now.formatted(date: .omitted, time: .shortened))
                .font(.system(size: context.size == .small ? 34 : 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
            SunArc(progress: state.dayProgress ?? state.nightProgress ?? 0.5, isMoon: state.dayProgress == nil)
                .frame(maxHeight: context.size == .small ? 60 : 100)
            if context.size != .small {
                detail(state)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom),
            in: .rect(cornerRadius: 18)
        )
    }

    @ViewBuilder
    private func detail(_ state: SkyState) -> some View {
        if let next = state.next {
            let wait = CompactDuration.format(next.date.timeIntervalSince(now))
            Text(next.isSunrise ? loc("Sunrise in \(wait)") : loc("Sunset in \(wait)"))
                .font(.system(size: 13, weight: .semibold))
        }
        HStack {
            Label(timeText(state.sun.sunrise), systemImage: "sunrise")
            Spacer()
            Label(timeText(state.sun.sunset), systemImage: "sunset")
        }
        .font(.system(size: 12))
        if context.size != .medium {
            Divider().overlay(.white.opacity(0.3))
            skyRow(loc("Sunrise"), timeText(state.sun.sunrise))
            skyRow(loc("Sunset"), timeText(state.sun.sunset))
            skyRow(loc("Daylight"), state.sun.daylight.map(CompactDuration.format) ?? "—")
            skyRow(loc("Moon"), Format.percent(Astronomy.moonIllumination(at: now)))
        }
    }

    private func skyRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).opacity(0.8)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 12))
    }

    private var otherCities: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc("Other cities")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if context.cities.isEmpty {
                NoCitiesHint()
            }
            ForEach(context.cities.prefix(5)) { city in
                VStack(alignment: .leading, spacing: 4) {
                    PlaceRow(place: city, now: now, timeSize: 16)
                    DayStrip(time: city.time(at: now))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A 24-hour bar: dark at night, light by day, with a marker for the current hour.
struct DayStrip: View {
    let time: ClockTime

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 0.12, green: 0.14, blue: 0.32))
                Capsule()
                    .fill(Palette.yellow.opacity(0.85))
                    .frame(width: width / 2)
                    .offset(x: width / 4)
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .offset(x: width * time.dayShare - 4)
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
    }
}

/// A 24-hour dial: midnight at the bottom, noon at the top, daylight as a bright arc.
struct DayDial<Content: View>: View {
    let sun: SunTimes
    let now: Date
    @ViewBuilder let content: Content

    private func share(_ date: Date?) -> Double? {
        date.map { ClockTime(date: $0, timeZone: .current).dayShare }
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let line = max(side * 0.09, 6)
            let radius = (side - line) / 2
            let current = ClockTime(date: now, timeZone: .current).dayShare
            let angle = (current * 360 + 90) * .pi / 180
            ZStack {
                Circle().stroke(Color(red: 0.16, green: 0.18, blue: 0.40), lineWidth: line)
                daylightArcs(line: line)
                Circle()
                    .fill(.white)
                    .frame(width: line * 0.9, height: line * 0.9)
                    .shadow(radius: 2)
                    .offset(x: radius * cos(angle), y: radius * sin(angle))
                content
            }
            .frame(width: side - line, height: side - line)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func daylightArcs(line: CGFloat) -> some View {
        if let rise = share(sun.sunrise), let set = share(sun.sunset) {
            if rise < set {
                arc(rise, set, line)
            } else {
                arc(rise, 1, line)
                arc(0, set, line)
            }
        }
    }

    private func arc(_ start: Double, _ end: Double, _ line: CGFloat) -> some View {
        Circle()
            .trim(from: start, to: end)
            .stroke(Palette.yellow, style: StrokeStyle(lineWidth: line, lineCap: .butt))
            .rotationEffect(.degrees(90))
    }
}

/// How the day is split between light and dark, now and across the year.
struct DayAndNightWidget: View {
    let context: TimeContext
    let place: SunPlace

    private var now: Date {
        context.now
    }

    private var sun: SunTimes {
        Astronomy.sunTimes(on: now, latitude: place.latitude, longitude: place.longitude)
    }

    var body: some View {
        switch context.size {
        case .small:
            dial
        case .medium:
            HStack(spacing: 16) {
                dial
                facts
            }
        case .large:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    dial.frame(maxHeight: 170)
                    facts
                }
                chart(days: 14, step: 1, title: loc("Next 14 days"))
            }
        case .extraLarge:
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 12) {
                    dial
                    facts
                }
                VStack(alignment: .leading, spacing: 10) {
                    chart(days: 366, step: 3, title: loc("This year"))
                    solstices
                }
            }
        }
    }

    private var dial: some View {
        DayDial(sun: sun, now: now) {
            VStack(spacing: 0) {
                Text(now.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                if context.size == .small {
                    Text(place.name).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(place.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.yellow)
            Text(sun.daylight.map(CompactDuration.format) ?? "—")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            InfoRow(title: loc("Sunrise"), value: timeText(sun.sunrise))
            InfoRow(title: loc("Sunset"), value: timeText(sun.sunset))
        }
    }

    private func series(days: Int, step: Int) -> [DaylightDay] {
        Astronomy.daylight(
            from: now,
            days: days,
            step: step,
            latitude: place.latitude,
            longitude: place.longitude
        )
    }

    private func chart(days: Int, step: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            InteractiveChart(
                series: [.daylight(series(days: days, step: step))],
                height: 100,
                tooltipDate: Date.FormatStyle(date: .abbreviated, time: .omitted)
            )
        }
    }

    @ViewBuilder
    private var solstices: some View {
        let year = series(days: 366, step: 1)
        if let longest = year.max(by: { $0.seconds < $1.seconds }),
           let shortest = year.min(by: { $0.seconds < $1.seconds })
        {
            InfoRow(
                title: loc("Longest day"),
                value: "\(longest.date.formatted(.dateTime.day().month(.abbreviated))) · "
                    + CompactDuration.format(longest.seconds)
            )
            InfoRow(
                title: loc("Shortest day"),
                value: "\(shortest.date.formatted(.dateTime.day().month(.abbreviated))) · "
                    + CompactDuration.format(shortest.seconds)
            )
        }
    }
}
