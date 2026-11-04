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
}

/// Analog clock: a dial, then world clocks as the widget grows.
struct AnalogClockWidget: View {
    let context: TimeContext

    var body: some View {
        switch context.size {
        case .small:
            AnalogDial(time: context.local, showsSeconds: context.showsSeconds)
        case .medium:
            HStack(spacing: 10) {
                ForEach(context.places.prefix(4)) { place in
                    PlaceDial(place: place, now: context.now, showsSeconds: false)
                }
            }
        case .large:
            VStack(spacing: 12) {
                AnalogDial(time: context.local, showsSeconds: context.showsSeconds)
                    .frame(maxHeight: 200)
                cityList(limit: 4)
            }
        case .extraLarge:
            HStack(spacing: 24) {
                AnalogDial(time: context.local, showsSeconds: context.showsSeconds)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(context.places.prefix(6)) { place in
                        PlaceDial(place: place, now: context.now)
                            .frame(height: 110)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cityList(limit: Int) -> some View {
        if context.cities.isEmpty {
            NoCitiesHint()
        } else {
            VStack(spacing: 8) {
                ForEach(context.cities.prefix(limit)) { place in
                    PlaceRow(place: place, now: context.now, timeSize: 17)
                }
            }
        }
    }
}

/// A dial with numbers instead of ticks; the current hour is orange.
struct NumeralsClockWidget: View {
    let context: TimeContext

    private var now: Date {
        context.now
    }

    var body: some View {
        switch context.size {
        case .small:
            AnalogDial(time: context.local, numerals: true, showsSeconds: false)
        case .medium:
            HStack(spacing: 16) {
                AnalogDial(time: context.local, numerals: true, showsSeconds: false)
                digital(timeSize: 40)
            }
        case .large:
            VStack(spacing: 14) {
                AnalogDial(time: context.local, numerals: true, showsSeconds: context.showsSeconds)
                    .frame(maxHeight: 220)
                HStack(spacing: 10) {
                    ForEach(context.cities.prefix(3)) { place in
                        plate(place)
                    }
                }
                if context.cities.isEmpty {
                    NoCitiesHint()
                }
            }
        case .extraLarge:
            HStack(spacing: 24) {
                AnalogDial(time: context.local, numerals: true, showsSeconds: context.showsSeconds)
                VStack(alignment: .leading, spacing: 12) {
                    digital(timeSize: 56)
                    Text(loc("Week \(Calendar.current.component(.weekOfYear, from: now))"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Divider()
                    if context.cities.isEmpty {
                        NoCitiesHint()
                    }
                    ForEach(context.cities.prefix(4)) { place in
                        PlaceRow(place: place, now: now, timeSize: 17)
                    }
                }
            }
        }
    }

    private func digital(timeSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(now.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.orange)
            Text(now.formatted(date: .omitted, time: .shortened))
                .font(.system(size: timeSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(now.formatted(.dateTime.day().month(.wide)))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func plate(_ place: ClockPlace) -> some View {
        VStack(spacing: 2) {
            Text(place.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Text(place.timeText(at: now))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}

/// Thin type on empty glass.
struct MinimalClockWidget: View {
    let context: TimeContext

    private var now: Date {
        context.now
    }

    private var timeSize: CGFloat {
        switch context.size {
        case .small: 46
        case .medium: 72
        case .large: 84
        case .extraLarge: 130
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if context.size != .small {
                Text(now.formatted(.dateTime.weekday(.wide)).uppercased())
                    .font(.system(size: 12, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
            }
            Text(now.formatted(date: .omitted, time: .shortened))
                .font(.system(size: timeSize, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            Text(dateText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if context.size == .large || context.size == .extraLarge {
                Spacer(minLength: 8)
                cities(limit: context.size == .large ? 4 : 6)
            }
        }
    }

    private var dateText: String {
        let style: Date.FormatStyle = context.size == .small
            ? .dateTime.day().month(.abbreviated)
            : .dateTime.day().month(.wide)
        let date = now.formatted(style)
        return context.size == .medium ? "\(date) · \(ClockPlace.local.name)" : date
    }

    @ViewBuilder
    private func cities(limit: Int) -> some View {
        if context.cities.isEmpty {
            NoCitiesHint()
        }
        let columns = context.size == .extraLarge ? 2 : 1
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: columns), spacing: 0) {
            ForEach(context.cities.prefix(limit)) { place in
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Text(place.name).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(place.timeText(at: now))
                            .font(.system(size: 22, weight: .ultraLight, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 6)
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

    private var cardHeight: CGFloat {
        switch context.size {
        case .small: 70
        case .medium: 96
        case .large: 130
        case .extraLarge: 170
        }
    }

    var body: some View {
        switch context.size {
        case .small:
            VStack(alignment: .leading, spacing: 8) {
                weekday
                cards
            }
        case .medium:
            HStack(spacing: 14) {
                cards
                VStack(alignment: .leading, spacing: 4) {
                    weekday
                    Text(now.formatted(.dateTime.day().month(.wide))).font(.system(size: 15, weight: .medium))
                    if context.showsSeconds {
                        FlipCard(text: String(format: "%02d", context.local.second), height: 36)
                            .frame(width: 44)
                    }
                }
            }
        case .large, .extraLarge:
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        weekday
                        Text(now.formatted(.dateTime.day().month(.wide))).font(.system(size: 15, weight: .medium))
                    }
                    Spacer()
                    Text(loc("Week \(Calendar.current.component(.weekOfYear, from: now))"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                cards
                miniCards(limit: context.size == .large ? 3 : 5)
            }
        }
    }

    private var weekday: some View {
        Text(now.formatted(.dateTime.weekday(.wide)).uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.orange)
    }

    private var cards: some View {
        HStack(spacing: 8) {
            FlipCard(text: hourText(ClockPlace.local.zone), height: cardHeight)
            FlipCard(text: minuteText(ClockPlace.local.zone), height: cardHeight)
        }
    }

    private func hourText(_ zone: TimeZone) -> String {
        now.formatted(Date.FormatStyle(timeZone: zone).hour(.twoDigits(amPM: .omitted)))
    }

    private func minuteText(_ zone: TimeZone) -> String {
        now.formatted(Date.FormatStyle(timeZone: zone).minute(.twoDigits))
    }

    @ViewBuilder
    private func miniCards(limit: Int) -> some View {
        if context.cities.isEmpty {
            NoCitiesHint()
        }
        HStack(spacing: 10) {
            ForEach(context.cities.prefix(limit)) { place in
                VStack(spacing: 4) {
                    HStack(spacing: 3) {
                        FlipCard(text: hourText(place.zone), height: 36)
                        FlipCard(text: minuteText(place.zone), height: 36)
                    }
                    Text(place.name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// One card of a flip clock: digits on a dark plate split by a hairline.
struct FlipCard: View {
    let text: String
    let height: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: height * 0.66, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(.quaternary.opacity(0.7), in: .rect(cornerRadius: height * 0.12))
            .overlay {
                Rectangle().fill(.black.opacity(0.35)).frame(height: 1)
            }
    }
}
