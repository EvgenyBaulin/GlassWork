import GlassWorkCore
import SwiftUI

/// A 24-hour dial: midnight at the bottom, noon at the top, daylight as a bright arc.
struct DayDial<Content: View>: View {
    let sun: SunTimes
    let now: Date
    var showsHours = false
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    private var night: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.18, blue: 0.50)
            : Color(red: 0.78, green: 0.75, blue: 0.90)
    }

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
                Circle().stroke(night, lineWidth: line)
                daylightArcs(line: line)
                ticks(radius: radius - line, side: side)
                Circle()
                    .fill(.white)
                    .frame(width: line * 1.25, height: line * 1.25)
                    .overlay(Circle().strokeBorder(Palette.orange, lineWidth: line * 0.22))
                    .shadow(radius: 2)
                    .offset(x: radius * cos(angle), y: radius * sin(angle))
                content
            }
            .frame(width: side - line, height: side - line)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func ticks(radius: CGFloat, side: CGFloat) -> some View {
        ZStack {
            ForEach(0 ..< 24, id: \.self) { hour in
                Capsule()
                    .fill(.primary.opacity(hour % 6 == 0 ? 0.7 : 0.3))
                    .frame(width: hour % 6 == 0 ? 1.5 : 1, height: side * (hour % 6 == 0 ? 0.05 : 0.025))
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(hour) * 15))
            }
            if showsHours {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    let angle = (Double(hour) / 24 * 360 + 90) * .pi / 180
                    Text(verbatim: "\(hour)")
                        .font(.system(size: side * 0.05))
                        .foregroundStyle(.secondary)
                        .offset(x: (radius - side * 0.09) * cos(angle), y: (radius - side * 0.09) * sin(angle))
                }
            }
        }
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
            .stroke(Palette.orange, style: StrokeStyle(lineWidth: line, lineCap: .round))
            .rotationEffect(.degrees(90))
    }
}

/// How the day is split between light and dark, now and across the year.
struct DayAndNightWidget: View {
    let context: TimeContext

    private var place: SunPlace {
        SunPlace(context.snapshot)
    }

    private var now: Date {
        context.now
    }

    private var sun: SunTimes {
        Astronomy.sunTimes(on: now, latitude: place.latitude, longitude: place.longitude)
    }

    private var sky: SkyState {
        place.sky(at: now)
    }

    var body: some View {
        switch context.size {
        case .small:
            dial(timeSize: 20, caption: lightLeft)
        case .medium:
            HStack(spacing: 16) {
                dial(timeSize: 20, caption: lightLeft)
                facts
            }
        case .large:
            VStack(alignment: .leading, spacing: 10) {
                dial(timeSize: 26, caption: nextEvent)
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                WidgetSection(title: loc("Next days"))
                nextDays
                Spacer(minLength: 0)
            }
        case .extraLarge:
            HStack(spacing: 18) {
                DayDial(sun: sun, now: now, showsHours: true) {
                    centerText(timeSize: 42, captionSize: 14, caption: lightLeft)
                }
                Divider()
                year.frame(width: 340)
            }
        }
    }

    private func dial(timeSize: CGFloat, caption: String) -> some View {
        DayDial(sun: sun, now: now) {
            centerText(timeSize: timeSize, captionSize: 9, caption: caption)
        }
    }

    private func centerText(timeSize: CGFloat, captionSize: CGFloat, caption: String) -> some View {
        VStack(spacing: 1) {
            Text(ClockPlace.local.digits(at: now))
                .font(.system(size: timeSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
            Text(caption)
                .font(.system(size: captionSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, timeSize)
    }

    /// "51m of light" by day; at night the same place says when the sun comes back.
    private var lightLeft: String {
        guard let next = sky.next else { return place.name }
        let wait = CompactDuration.format(next.date.timeIntervalSince(now))
        return next.isSunrise ? loc("Sunrise in \(wait)") : loc("\(wait) of light")
    }

    private var nextEvent: String {
        guard let next = sky.next else { return place.name }
        let wait = CompactDuration.format(next.date.timeIntervalSince(now))
        return next.isSunrise ? loc("Sunrise in \(wait)") : loc("Sunset in \(wait)")
    }

    /// Against yesterday: "3m shorter than yesterday".
    private var change: String? {
        let yesterday = Astronomy.sunTimes(
            on: now.addingTimeInterval(-86400),
            latitude: place.latitude,
            longitude: place.longitude
        )
        guard let today = sun.daylight, let before = yesterday.daylight else { return nil }
        let delta = today - before
        guard abs(delta) >= 60 else { return loc("Same as yesterday") }
        let text = CompactDuration.format(abs(delta))
        return delta > 0 ? loc("\(text) longer than yesterday") : loc("\(text) shorter than yesterday")
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetCapsTitle(title: loc("Daylight"), tint: Palette.orange)
            Text(sun.daylight.map(CompactDuration.format) ?? "—")
                .font(.widgetFigure(26))
                .lineLimit(1)
            if let change {
                Text(change).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 10) {
                Label(sunTimeText(sun.sunrise), systemImage: "sunrise")
                Label(sunTimeText(sun.sunset), systemImage: "sunset")
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.top, 3)
            Spacer(minLength: 0)
            Text(nextEvent)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.orange)
                .widgetAccentable()
        }
        .padding(.vertical, 4)
    }

    private func series(from start: Date, days: Int, step: Int) -> [DaylightDay] {
        Astronomy.daylight(
            from: start,
            days: days,
            step: step,
            latitude: place.latitude,
            longitude: place.longitude
        )
    }

    private var nextDays: some View {
        let days = series(from: now, days: 6, step: 1)
        let longest = max(days.map(\.seconds).max() ?? 1, 1)
        return VStack(spacing: 7) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                HStack(spacing: 10) {
                    Text(index == 0 ? loc("Today") : day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 12))
                        .frame(width: 58, alignment: .leading)
                        .lineLimit(1)
                    ThinBar(value: day.seconds / longest * 0.96, tint: Palette.orange)
                    Text(CompactDuration.format(day.seconds))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 58, alignment: .trailing)
                }
            }
        }
    }

    private var year: some View {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .year, for: now)?.start ?? now
        let days = series(from: start, days: 366, step: 3)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                WidgetSection(title: loc("Daylight through the year"))
                Spacer(minLength: 6)
                Text(place.name).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
            }
            InteractiveChart(
                series: [.daylight(days)],
                height: 108,
                tooltipDate: Date.FormatStyle(date: .abbreviated, time: .omitted)
            )
            HStack(spacing: 8) {
                plate(loc("Sunrise"), sunTimeText(sun.sunrise))
                plate(loc("Sunset"), sunTimeText(sun.sunset))
                plate(loc("Solar noon"), sunTimeText(solarNoon))
            }
            solstices(start: start)
            Spacer(minLength: 0)
        }
    }

    /// Halfway between sunrise and sunset.
    private var solarNoon: Date? {
        guard let sunrise = sun.sunrise, let daylight = sun.daylight else { return nil }
        return sunrise.addingTimeInterval(daylight / 2)
    }

    private func plate(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func solstices(start: Date) -> some View {
        let year = series(from: start, days: 366, step: 1)
        if let longest = year.max(by: { $0.seconds < $1.seconds }),
           let shortest = year.min(by: { $0.seconds < $1.seconds })
        {
            VStack(spacing: 7) {
                solstice("moon", loc("Shortest day"), shortest)
                solstice("sun.max", loc("Longest day"), longest)
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        }
    }

    private func solstice(_ symbol: String, _ title: String, _ day: DaylightDay) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(Palette.orange).widgetAccentable()
            Text(verbatim: "\(title) · \(day.date.formatted(.dateTime.day().month(.abbreviated)))").lineLimit(1)
            Spacer(minLength: 4)
            Text(CompactDuration.format(day.seconds)).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}
