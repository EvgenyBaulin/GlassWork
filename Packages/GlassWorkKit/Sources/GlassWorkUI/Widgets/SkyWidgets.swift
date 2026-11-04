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

func sunTimeText(_ date: Date?) -> String {
    date?.formatted(date: .omitted, time: .shortened) ?? "—"
}

/// Path of the sun over the horizon, a faint one under it, and a mark at its position.
struct SunArc: View {
    let progress: Double
    let isMoon: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let radiusX = width / 2 - 10
            let lift = height * 0.8 - 8
            let center = CGPoint(x: width / 2, y: height * 0.8)
            let angle = Double.pi * (1 - min(max(progress, 0), 1))
            ZStack {
                arc(center: center, radiusX: radiusX, radiusY: lift)
                    .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2.5, 3]))
                arc(center: center, radiusX: radiusX, radiusY: -height * 0.16)
                    .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2.5, 3]))
                Path { path in
                    path.move(to: CGPoint(x: center.x - radiusX, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + radiusX, y: center.y))
                }
                .stroke(.white.opacity(0.5), lineWidth: 1)
                Image(systemName: isMoon ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isMoon ? Color.white : Palette.yellow)
                    .position(x: center.x + radiusX * cos(angle), y: center.y - lift * sin(angle))
            }
        }
    }

    /// Half an ellipse from left to right, as a polyline: a dash pattern on it stays even.
    private func arc(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat) -> Path {
        Path { path in
            for step in 0 ... 48 {
                let angle = Double.pi * (1 - Double(step) / 48)
                let point = CGPoint(x: center.x + radiusX * cos(angle), y: center.y - radiusY * sin(angle))
                if step == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
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
        switch context.size {
        case .small:
            panel {
                VStack(alignment: .leading, spacing: 2) {
                    cityCaps
                    ClockFigure(place: .local, now: now, size: 28)
                    arc.frame(maxHeight: .infinity)
                    Text(nextEvent(sky)).font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        case .medium:
            panel {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        ClockFigure(place: .local, now: now, size: 34)
                        countdown(sky).font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                        Text(verbatim: "\(shortDate) · \(daylightText(sky))")
                            .font(.system(size: 10))
                            .opacity(0.8)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 4) {
                        arc.frame(maxHeight: .infinity)
                        sunTimes(sky).font(.system(size: 10))
                    }
                    .frame(width: 136)
                }
            }
        case .large:
            VStack(spacing: 10) {
                panel {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(place.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Spacer()
                            countdown(sky).font(.system(size: 11, weight: .medium))
                        }
                        ClockFigure(place: .local, now: now, size: 30)
                        arc.frame(maxHeight: .infinity)
                    }
                }
                .frame(height: 196)
                factRows(sky)
            }
        case .extraLarge:
            HStack(spacing: 14) {
                panel {
                    VStack(alignment: .leading, spacing: 4) {
                        cityCaps
                        ClockFigure(place: .local, now: now, size: 40)
                        countdown(sky).font(.system(size: 13, weight: .medium))
                        arc.frame(maxHeight: .infinity)
                        sunTimes(sky).font(.system(size: 11))
                        Label(moonText, systemImage: "moon").font(.system(size: 11)).lineLimit(1)
                    }
                }
                .frame(width: 340)
                otherCities
            }
        }
    }

    private func panel(@ViewBuilder content: () -> some View) -> some View {
        content()
            .foregroundStyle(.white)
            .padding(context.size == .small ? 10 : 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom),
                in: .rect(cornerRadius: 16)
            )
    }

    private var cityCaps: some View {
        Text(place.name.uppercased()).font(.system(size: 10, weight: .semibold)).opacity(0.85).lineLimit(1)
    }

    private var arc: some View {
        let state = sky
        return SunArc(progress: state.dayProgress ?? state.nightProgress ?? 0.5, isMoon: state.dayProgress == nil)
    }

    private var shortDate: String {
        now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func daylightText(_ state: SkyState) -> String {
        loc("Daylight \(state.sun.daylight.map(CompactDuration.format) ?? "—")")
    }

    private var moonText: String {
        loc("Moon \(Format.percent(Astronomy.moonIllumination(at: now)))")
    }

    /// "Sunset 4:38 PM", whichever comes next.
    private func nextEvent(_ state: SkyState) -> String {
        guard let next = state.next else { return daylightText(state) }
        return next.isSunrise ? loc("Sunrise \(sunTimeText(next.date))") : loc("Sunset \(sunTimeText(next.date))")
    }

    @ViewBuilder
    private func countdown(_ state: SkyState) -> some View {
        if let next = state.next {
            let wait = CompactDuration.format(next.date.timeIntervalSince(now))
            Text(next.isSunrise ? loc("Sunrise in \(wait)") : loc("Sunset in \(wait)")).lineLimit(1)
        }
    }

    private func sunTimes(_ state: SkyState) -> some View {
        HStack {
            Label(sunTimeText(state.sun.sunrise), systemImage: "sunrise").lineLimit(1)
            Spacer(minLength: 4)
            Label(sunTimeText(state.sun.sunset), systemImage: "sunset").lineLimit(1)
        }
    }

    private func factRows(_ state: SkyState) -> some View {
        let tomorrow = Astronomy.sunTimes(
            on: now.addingTimeInterval(86400),
            latitude: place.latitude,
            longitude: place.longitude
        )
        return VStack(alignment: .leading, spacing: 7) {
            factRow("sunrise", loc("Sunrise"), sunTimeText(state.sun.sunrise))
            factRow("sunset", loc("Sunset"), sunTimeText(state.sun.sunset))
            factRow("sun.max", loc("Daylight"), state.sun.daylight.map(CompactDuration.format) ?? "—")
            factRow("moon", loc("Moon"), Format.percent(Astronomy.moonIllumination(at: now)))
            Spacer(minLength: 0)
            Text(loc("Tomorrow: sunrise \(sunTimeText(tomorrow.sunrise)), sunset \(sunTimeText(tomorrow.sunset))"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private func factRow(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Palette.orange)
                .frame(width: 16)
                .widgetAccentable()
            Text(title).font(.system(size: 12))
            Spacer()
            Text(value).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var otherCities: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetSection(title: loc("Other cities"))
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
            Text(loc("Strip = 24 hours, marker = the time there now"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
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
                    .fill(Palette.orange.opacity(0.9))
                    .frame(width: width / 2)
                    .offset(x: width / 4)
                Rectangle()
                    .fill(.primary)
                    .frame(width: 2, height: 10)
                    .offset(x: width * time.dayShare - 1)
            }
            .frame(height: 5)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 10)
    }
}
