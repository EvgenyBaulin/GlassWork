import GlassWorkCore
import SwiftUI

/// One place on a clock face: the Mac's own zone or a saved city.
struct ClockPlace: Identifiable {
    let id: String
    let name: String
    let zone: TimeZone

    /// The Mac's own zone first, then the saved cities, so a clock always has something to show.
    static func list(_ snapshot: WidgetSnapshot, includesLocal: Bool = true) -> [ClockPlace] {
        let cities = snapshot.everyday.cities.compactMap { city in
            city.zone.map { ClockPlace(id: city.id, name: city.name, zone: $0) }
        }
        return (includesLocal ? [local] : []) + cities
    }

    static var local: ClockPlace {
        let zone = TimeZone.current
        let name = zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
        return ClockPlace(id: "local", name: name ?? loc("Local"), zone: zone)
    }

    func time(at date: Date) -> ClockTime {
        ClockTime(date: date, timeZone: zone)
    }

    func timeText(at date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
    }

    /// The time without AM or PM: "3:47", or "15:47" where the Mac shows 24 hours.
    func digits(at date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: zone).hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
    }

    func hourText(at date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: zone).hour(.defaultDigits(amPM: .omitted)))
    }

    func minuteText(at date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: zone).minute(.twoDigits))
    }

    /// "AM" or "PM"; nil where the Mac shows 24 hours.
    func dayPeriod(at date: Date) -> String? {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        guard format.contains("a") else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateFormat = "a"
        return formatter.string(from: date)
    }

    /// "UTC+3".
    func utcOffset(at date: Date) -> String {
        let hours = Double(zone.secondsFromGMT(for: date)) / 3600
        let sign = hours < 0 ? "−" : "+"
        return "UTC\(sign)\(abs(hours).formatted(.number.precision(.fractionLength(0 ... 1))))"
    }

    /// Three letters for a dial, such as MOS.
    var code: String {
        String(name.prefix(3)).uppercased()
    }

    /// "Today", "Tomorrow" or "Yesterday", with the hours from this Mac when the zone differs.
    func caption(at date: Date) -> String {
        guard id != Self.local.id else { return loc("Local") }
        let time = time(at: date)
        let day = switch time.dayOffset {
        case 1: loc("Tomorrow")
        case -1: loc("Yesterday")
        default: loc("Today")
        }
        guard time.hoursFromReference != 0 else { return day }
        let hours = time.hoursFromReference
        let sign = hours > 0 ? "+" : "−"
        let amount = abs(hours).formatted(.number.precision(.fractionLength(0 ... 1)))
        return "\(day), \(sign)\(amount) \(loc("h"))"
    }
}

/// Analog dial. Hands read the time they are given, so every place can have its own.
struct AnalogDial: View {
    let time: ClockTime
    var numerals = false
    var showsSeconds = true
    /// Day and night faces for world clocks: a pale dial by day, a dark one by night.
    var shadesByDaylight = false
    /// Printed on the dial above the center.
    var label: String?

    private var face: Color {
        guard shadesByDaylight else { return Color.primary.opacity(0.08) }
        return time.isDaytime ? Color.white.opacity(0.9) : Color.black.opacity(0.55)
    }

    private var ink: Color {
        guard shadesByDaylight else { return .primary }
        return time.isDaytime ? Color.black.opacity(0.85) : Color.white.opacity(0.9)
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(face)
                Circle().strokeBorder(ink.opacity(0.18), lineWidth: 1)
                marks(side: side)
                if let label {
                    Text(verbatim: label)
                        .font(.system(size: max(side * 0.075, 9), weight: .semibold))
                        .foregroundStyle(ink.opacity(0.5))
                        .offset(y: -side * 0.17)
                }
                hand(length: side * 0.26, width: max(side * 0.035, 2), angle: time.hourAngle, color: ink)
                hand(length: side * 0.39, width: max(side * 0.022, 1.5), angle: time.minuteAngle, color: ink)
                if showsSeconds {
                    hand(
                        length: side * 0.42,
                        width: max(side * 0.01, 1),
                        angle: time.secondAngle,
                        color: Palette.orange
                    )
                }
                Circle().fill(Palette.orange).frame(width: side * 0.05, height: side * 0.05)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func marks(side: CGFloat) -> some View {
        if numerals {
            ForEach(1 ... 12, id: \.self) { number in
                let angle = Double(number) * 30 * .pi / 180
                let isCurrent = number == (time.hour % 12 == 0 ? 12 : time.hour % 12)
                Text("\(number)")
                    .font(.system(size: side * 0.14, weight: isCurrent ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isCurrent ? Palette.orange : ink.opacity(0.85))
                    .position(
                        x: side / 2 + sin(angle) * side * 0.36,
                        y: side / 2 - cos(angle) * side * 0.36
                    )
            }
        } else {
            if side > 80 {
                ForEach(0 ..< 60, id: \.self) { minute in
                    if minute % 5 != 0 {
                        Capsule()
                            .fill(ink.opacity(0.25))
                            .frame(width: 1, height: side * 0.025)
                            .offset(y: -side * 0.445)
                            .rotationEffect(.degrees(Double(minute) * 6))
                    }
                }
            }
            ForEach(0 ..< 12, id: \.self) { index in
                Capsule()
                    .fill(ink.opacity(index % 3 == 0 ? 0.8 : 0.35))
                    .frame(width: index % 3 == 0 ? max(side * 0.025, 2) : max(side * 0.012, 1), height: side * 0.07)
                    .offset(y: -side * 0.42)
                    .rotationEffect(.degrees(Double(index) * 30))
            }
        }
    }

    private func hand(length: CGFloat, width: CGFloat, angle: Double, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(angle))
    }
}

/// A small card with the name, caption and time of one place.
struct PlaceRow: View {
    let place: ClockPlace
    let now: Date
    var timeSize: CGFloat = 20

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(place.caption(at: now)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(place.timeText(at: now))
                .font(.system(size: timeSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// A place as a dial with its name and time underneath.
struct PlaceDial: View {
    let place: ClockPlace
    let now: Date
    var numerals = false
    var showsSeconds = false

    var body: some View {
        VStack(spacing: 4) {
            AnalogDial(
                time: place.time(at: now),
                numerals: numerals,
                showsSeconds: showsSeconds,
                shadesByDaylight: true
            )
            Text(place.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Text(place.caption(at: now)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Text(place.timeText(at: now)).font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
        }
    }
}

/// A big time with AM or PM small beside it.
struct ClockFigure: View {
    let place: ClockPlace
    let now: Date
    let size: CGFloat
    var weight = Font.Weight.semibold

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.12) {
            Text(place.digits(at: now))
                .font(.system(size: size, weight: weight, design: .rounded))
                .monospacedDigit()
            if let period = place.dayPeriod(at: now) {
                Text(period).font(.system(size: max(size * 0.36, 10), weight: .medium)).opacity(0.7)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Shown where a clock lists cities and none are saved yet.
struct NoCitiesHint: View {
    var body: some View {
        Text(loc("Add cities in World Clocks"))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
}
