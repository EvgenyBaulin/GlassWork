import GlassWorkCore
import SwiftUI

/// Inputs every time widget needs.
struct TimeContext {
    let size: WidgetSize
    let snapshot: WidgetSnapshot
    let now: Date
    /// Seconds only move in GlassWork's own windows; WidgetKit refreshes once a minute.
    let showsSeconds: Bool

    var places: [ClockPlace] {
        ClockPlace.list(snapshot)
    }

    var cities: [ClockPlace] {
        ClockPlace.list(snapshot, includesLocal: false)
    }

    var local: ClockTime {
        ClockPlace.local.time(at: now)
    }

    /// "Monday, November 2".
    var longDate: String {
        now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// "Week 45 · Day 306".
    var weekAndDay: String {
        let calendar = Calendar.current
        let week = calendar.component(.weekOfYear, from: now)
        let day = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        return "\(loc("Week \(week)")) · \(loc("Day \(day)"))"
    }
}

/// Analog clock: a dial, then world clocks as the widget grows.
struct AnalogClockWidget: View {
    let context: TimeContext

    private var here: ClockPlace {
        .local
    }

    var body: some View {
        switch context.size {
        case .small:
            AnalogDial(time: context.local, showsSeconds: context.showsSeconds, label: here.code)
        case .medium:
            HStack(spacing: 10) {
                ForEach(context.places.prefix(4)) { place in
                    PlaceDial(place: place, now: context.now)
                }
            }
        case .large:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    AnalogDial(time: context.local, showsSeconds: context.showsSeconds).frame(width: 112, height: 112)
                    localFacts
                    Spacer(minLength: 0)
                }
                Divider()
                cityList(limit: 4)
                Spacer(minLength: 0)
            }
        case .extraLarge:
            HStack(spacing: 18) {
                AnalogDial(
                    time: context.local,
                    showsSeconds: context.showsSeconds,
                    label: here.name.uppercased()
                )
                Divider()
                worldGrid.frame(width: 340)
            }
        }
    }

    private var localFacts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(here.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(here.timeText(at: context.now))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(context.longDate).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            Text(verbatim: "\(loc("Local")) · \(here.utcOffset(at: context.now))")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func cityList(limit: Int) -> some View {
        if context.cities.isEmpty {
            NoCitiesHint()
        } else {
            VStack(spacing: 8) {
                ForEach(context.cities.prefix(limit)) { place in
                    HStack(spacing: 10) {
                        AnalogDial(time: place.time(at: context.now), showsSeconds: false, shadesByDaylight: true)
                            .frame(width: 34, height: 34)
                        PlaceRow(place: place, now: context.now, timeSize: 17)
                    }
                }
            }
        }
    }

    private var worldGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetSection(title: ModuleID.worldClocks.title)
                Spacer(minLength: 6)
                Text(context.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if context.cities.isEmpty {
                NoCitiesHint()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12) {
                ForEach(context.cities.prefix(6)) { place in
                    PlaceDial(place: place, now: context.now).frame(height: 136)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A dial with numbers instead of ticks; the current hour is orange.
struct NumeralsClockWidget: View {
    let context: TimeContext

    private var now: Date {
        context.now
    }

    private var here: ClockPlace {
        .local
    }

    private var weekday: String {
        now.formatted(.dateTime.weekday(.wide)).uppercased()
    }

    var body: some View {
        switch context.size {
        case .small:
            AnalogDial(time: context.local, numerals: true, showsSeconds: false)
        case .medium:
            HStack(spacing: 16) {
                AnalogDial(time: context.local, numerals: true, showsSeconds: false)
                VStack(alignment: .leading, spacing: 3) {
                    ClockFigure(place: here, now: now, size: 38)
                    orange(weekday)
                    Text(now.formatted(.dateTime.month(.wide).day())).font(.system(size: 13))
                    Spacer(minLength: 0)
                    Text(verbatim: "\(here.name) · \(here.utcOffset(at: now))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
                Spacer(minLength: 0)
            }
        case .large:
            VStack(spacing: 10) {
                AnalogDial(time: context.local, numerals: true, showsSeconds: context.showsSeconds)
                    .frame(maxHeight: 220)
                HStack(spacing: 8) {
                    ForEach(context.cities.prefix(3)) { place in
                        plate(place)
                    }
                }
                if context.cities.isEmpty {
                    NoCitiesHint()
                }
                Text(verbatim: "\(context.longDate) · \(here.name)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .extraLarge:
            HStack(spacing: 24) {
                AnalogDial(time: context.local, numerals: true, showsSeconds: context.showsSeconds)
                VStack(alignment: .leading, spacing: 5) {
                    ClockFigure(place: here, now: now, size: 50)
                    orange(context.longDate.uppercased())
                    Text(verbatim: "\(context.weekAndDay) · \(here.name)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Divider().padding(.vertical, 6)
                    if context.cities.isEmpty {
                        NoCitiesHint()
                    }
                    VStack(spacing: 11) {
                        ForEach(context.cities.prefix(4)) { place in
                            PlaceRow(place: place, now: now, timeSize: 16)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 330)
            }
        }
    }

    private func orange(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.orange)
            .lineLimit(1)
            .widgetAccentable()
    }

    private func plate(_ place: ClockPlace) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(place.name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Text(place.timeText(at: now))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(place.caption(at: now)).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}

/// Thin type on empty glass. There is no AM or PM here on purpose.
struct MinimalClockWidget: View {
    let context: TimeContext

    private var now: Date {
        context.now
    }

    private var here: ClockPlace {
        .local
    }

    var body: some View {
        switch context.size {
        case .small:
            VStack(spacing: 4) {
                time(size: 50)
                Text(now.formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .medium:
            HStack(alignment: .center) {
                time(size: 74)
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(now.formatted(.dateTime.weekday(.wide))).font(.system(size: 13, weight: .medium))
                    Text(now.formatted(.dateTime.month(.wide).day()))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(here.name).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                }
                .padding(.vertical, 6)
            }
        case .large:
            VStack(alignment: .leading, spacing: 8) {
                time(size: 88)
                Text(context.longDate).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                cities(limit: 4)
            }
        case .extraLarge:
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    time(size: 130)
                    Text(context.longDate).font(.system(size: 15)).foregroundStyle(.secondary)
                    Text(here.name).font(.system(size: 12)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                cities(limit: 6).frame(width: 330)
            }
        }
    }

    private func time(size: CGFloat) -> some View {
        Text(here.digits(at: now))
            .font(.system(size: size, weight: .ultraLight, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.4)
            .lineLimit(1)
    }

    @ViewBuilder
    private func cities(limit: Int) -> some View {
        if context.cities.isEmpty {
            NoCitiesHint()
        }
        VStack(spacing: 0) {
            ForEach(context.cities.prefix(limit)) { place in
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(place.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(place.caption(at: now))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(place.timeText(at: now))
                            .font(.system(size: 22, weight: .ultraLight, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }
}

/// Split-flap cards for the hour and minute.
struct FlipClockWidget: View {
    let context: TimeContext

    private var now: Date {
        context.now
    }

    private var here: ClockPlace {
        .local
    }

    private var second: String {
        String(format: "%02d", context.local.second)
    }

    var body: some View {
        switch context.size {
        case .small:
            VStack(alignment: .leading, spacing: 6) {
                weekday
                cards(height: 90)
                Text(smallCaption).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        case .medium:
            HStack(spacing: 12) {
                cards(height: 134)
                VStack(alignment: .leading, spacing: 2) {
                    weekday
                    Text(now.formatted(.dateTime.month(.wide).day()))
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    seconds(cardHeight: 34)
                }
                .frame(width: 84, alignment: .leading)
            }
        case .large:
            VStack(alignment: .leading, spacing: 10) {
                cards(height: 156)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        weekday
                        Text(now.formatted(.dateTime.month(.wide).day())).font(.system(size: 16, weight: .medium))
                    }
                    Spacer()
                    seconds(cardHeight: 38)
                }
                Divider()
                cityRows(limit: 3, cardHeight: 24)
                Spacer(minLength: 0)
            }
        case .extraLarge:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    cards(height: 212)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            weekday
                            Text(now.formatted(.dateTime.month(.wide).day().year()))
                                .font(.system(size: 17, weight: .medium))
                            Text(context.weekAndDay).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        seconds(cardHeight: 50)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 330)
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    WidgetSection(title: ModuleID.worldClocks.title)
                    cityRows(limit: 5, cardHeight: 44)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// WidgetKit refreshes once a minute, so seconds would be wrong there.
    private var smallCaption: String {
        let date = now.formatted(.dateTime.month(.abbreviated).day())
        return context.showsSeconds ? "\(date) · \(second) \(loc("s"))" : date
    }

    private var weekday: some View {
        Text(now.formatted(.dateTime.weekday(.wide)).uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.orange)
            .lineLimit(1)
            .widgetAccentable()
    }

    private func cards(height: CGFloat) -> some View {
        HStack(spacing: 7) {
            FlipCard(text: here.hourText(at: now), height: height, note: here.dayPeriod(at: now))
            FlipCard(text: here.minuteText(at: now), height: height)
        }
    }

    @ViewBuilder
    private func seconds(cardHeight: CGFloat) -> some View {
        if context.showsSeconds {
            VStack(alignment: .leading, spacing: 2) {
                FlipCard(text: second, height: cardHeight).frame(width: cardHeight * 1.25)
                Text(loc("seconds")).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func cityRows(limit: Int, cardHeight: CGFloat) -> some View {
        if context.cities.isEmpty {
            NoCitiesHint()
        }
        VStack(spacing: 8) {
            ForEach(context.cities.prefix(limit)) { place in
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        FlipCard(text: place.hourText(at: now), height: cardHeight)
                        FlipCard(text: place.minuteText(at: now), height: cardHeight)
                    }
                    .frame(width: cardHeight * 2.4)
                    if cardHeight > 30 {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(place.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(place.caption(at: now))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(place.dayPeriod(at: now) ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        Text(place.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: [place.caption(at: now), place.dayPeriod(at: now)]
                            .compactMap(\.self)
                            .joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

/// One card of a flip clock: digits on a plate split by a hairline, with AM or PM in the corner.
struct FlipCard: View {
    let text: String
    let height: CGFloat
    var note: String?
    @Environment(\.colorScheme) private var colorScheme

    private var plate: Color {
        colorScheme == .dark ? Color(red: 0.11, green: 0.10, blue: 0.15) : .white
    }

    var body: some View {
        Text(text)
            .font(.system(size: height * 0.62, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(plate, in: .rect(cornerRadius: max(height * 0.1, 4)))
            .overlay {
                Rectangle().fill(.primary.opacity(0.18)).frame(height: 1)
            }
            .overlay(alignment: .bottomLeading) {
                if let note {
                    Text(note)
                        .font(.system(size: max(height * 0.08, 8), weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(height * 0.07)
                }
            }
    }
}
