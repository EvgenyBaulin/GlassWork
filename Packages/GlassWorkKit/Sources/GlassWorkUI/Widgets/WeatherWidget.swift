import GlassWorkCore
import SwiftUI
import WidgetKit

/// Conditions now, the coming hours and the week for the first saved place.
struct WeatherWidget: View {
    let context: TimeContext

    private var weather: WidgetWeather {
        context.snapshot.weather ?? WidgetWeather()
    }

    var body: some View {
        if let report = weather.reports.first {
            VStack(alignment: .leading, spacing: 8) {
                content(report).opacity(weather.isStale ? 0.45 : 1)
                if weather.isStale {
                    WidgetStaleBadge(
                        text: loc("Offline · as of \(Format.dataTime(report.fetchedAt, now: context.now))")
                    )
                }
            }
        } else if weather.hasPlaces {
            WidgetChecking(symbol: "cloud.sun", tint: Palette.cyan)
        } else {
            WidgetEmptyState(
                symbol: "location",
                title: loc("Weather needs a place"),
                detail: loc("Add a city or turn on location in GlassWork Settings."),
                tint: Palette.blue
            )
        }
    }

    @ViewBuilder
    private func content(_ report: WeatherReport) -> some View {
        switch context.size {
        case .small: small(report)
        case .medium:
            VStack(alignment: .leading, spacing: 8) {
                now(report, figure: 40)
                hours(report, count: 5)
            }
        case .large:
            VStack(alignment: .leading, spacing: 10) {
                now(report, figure: 48)
                Divider()
                hours(report, count: 6)
                Divider()
                days(report, count: 5, spacing: 14)
                Spacer(minLength: 0)
            }
        case .extraLarge:
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    now(report, figure: 48)
                    Divider()
                    hours(report, count: 6)
                    details(report)
                    Spacer(minLength: 0)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    WidgetSection(title: loc("7-day forecast"))
                    days(report, count: 7, spacing: 12)
                    otherPlaces
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func small(_ report: WeatherReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            place(report)
            HStack(alignment: .top) {
                Text(Format.degrees(report.current.temperature)).font(.widgetFigure(44)).monospacedDigit()
                Spacer(minLength: 0)
                symbol(report.current.condition, isDay: report.current.isDay, size: 28)
            }
            Spacer(minLength: 0)
            Text(report.current.condition.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            highLow(report)
        }
    }

    private func now(_ report: WeatherReport, figure: CGFloat) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                place(report)
                Text(Format.degrees(report.current.temperature)).font(.widgetFigure(figure)).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                symbol(report.current.condition, isDay: report.current.isDay, size: 26)
                Text(report.current.condition.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                highLow(report)
            }
        }
    }

    private func place(_ report: WeatherReport) -> some View {
        HStack(spacing: 3) {
            Text(report.place.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            if report.place.isCurrentLocation {
                Image(systemName: "location.fill").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func highLow(_ report: WeatherReport) -> some View {
        if let today = report.days.first {
            let high = Format.degrees(today.high)
            let low = Format.degrees(today.low)
            Text(loc("H:\(high) L:\(low)")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func symbol(_ condition: WeatherCondition, isDay: Bool, size: CGFloat) -> some View {
        Image(systemName: condition.symbol(isDay: isDay))
            .font(.system(size: size))
            .foregroundStyle(condition.tint)
            .widgetAccentable()
    }

    private func hours(_ report: WeatherReport, count: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(report.hours.prefix(count).enumerated()), id: \.element.id) { index, hour in
                VStack(spacing: 4) {
                    Text(index == 0 && !weather.isStale ? loc("Now") : hourLabel(hour.date, in: report))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    symbol(hour.condition, isDay: hour.isDay, size: 14).frame(height: 16)
                    Text(Format.degrees(hour.temperature)).font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func hourLabel(_ date: Date, in report: WeatherReport) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted).hour(.defaultDigits(amPM: .abbreviated))
        style.timeZone = report.zone
        return date.formatted(style)
    }

    private func days(_ report: WeatherReport, count: Int, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(Array(report.days.prefix(count).enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 6) {
                    Text(index == 0 ? loc("Today") : dayLabel(day.date, in: report))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .frame(width: 58, alignment: .leading)
                    symbol(day.condition, isDay: true, size: 13).frame(width: 20)
                    Text(Format.degrees(day.low))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                    DayRangeBar(
                        low: day.low,
                        high: day.high,
                        scale: report.temperatureRange ?? day.low ... max(day.high, day.low + 1),
                        current: index == 0 ? report.current.temperature : nil
                    )
                    Text(Format.degrees(day.high))
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
    }

    private func dayLabel(_ date: Date, in report: WeatherReport) -> String {
        var style = Date.FormatStyle().weekday(.abbreviated)
        style.timeZone = report.zone
        return date.formatted(style)
    }

    private func details(_ report: WeatherReport) -> some View {
        let current = report.current
        let index = Int(current.uvIndex.rounded())
        return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                plate(loc("Feels"), Format.degrees(current.feelsLike))
                plate(loc("Humidity"), Format.percent(current.humidity / 100))
            }
            GridRow {
                plate(loc("Wind"), Format.windSpeed(current.windSpeed))
                plate(loc("UV"), "\(index) \(UVLevel(index: current.uvIndex).title)")
            }
        }
    }

    private func plate(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            WidgetSection(title: title)
            Text(value).font(.system(size: 17, weight: .semibold, design: .rounded)).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 9))
    }

    @ViewBuilder
    private var otherPlaces: some View {
        let others = weather.reports.dropFirst().prefix(2)
        if !others.isEmpty {
            Divider()
            WidgetSection(title: loc("Saved cities"))
            ForEach(Array(others)) { report in
                HStack(spacing: 8) {
                    Text(report.place.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(report.current.condition.title).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1)
                    symbol(report.current.condition, isDay: report.current.isDay, size: 13).frame(width: 20)
                    Text(Format.degrees(report.current.temperature)).font(.system(size: 12, weight: .semibold))
                }
            }
        }
    }
}
