import GlassWorkCore
import SwiftUI
import WidgetKit

/// Exchange rates: the first pair up close, or every pair with its month.
struct RatesWidget: View {
    let context: TimeContext
    var chartHover: Date?

    private var rates: WidgetRates {
        context.snapshot.rates ?? WidgetRates()
    }

    var body: some View {
        if let quote = rates.quotes.first {
            VStack(alignment: .leading, spacing: 6) {
                content(quote).opacity(rates.isStale ? 0.45 : 1)
                if rates.isStale, let date = rates.updatedAt {
                    WidgetStaleBadge(text: loc("Offline · as of \(Format.dataTime(date, now: context.now))"))
                }
            }
        } else {
            WidgetEmptyState(
                symbol: "chart.line.uptrend.xyaxis",
                title: loc("No rates yet"),
                detail: loc("Rates appear after the first update."),
                tint: Palette.green
            )
        }
    }

    @ViewBuilder
    private func content(_ quote: RateQuote) -> some View {
        switch context.size {
        case .small:
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.pair.id).font(.system(size: 12, weight: .semibold))
                figure(quote, size: 30)
                change(quote)
                Spacer(minLength: 2)
                chart(quote, height: 44)
            }
        case .medium:
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quote.pair.id).font(.system(size: 12, weight: .semibold))
                    figure(quote, size: 34)
                    change(quote)
                    Spacer(minLength: 0)
                    sourceNote(quote)
                }
                VStack(alignment: .leading, spacing: 3) {
                    range(quote)
                    chart(quote, height: 90)
                }
            }
        case .large:
            VStack(alignment: .leading, spacing: 4) {
                WidgetTitle(
                    title: loc("Rates"),
                    symbol: "chart.line.uptrend.xyaxis",
                    tint: Palette.green,
                    note: updated
                )
                pairs(limit: 6, chartHeight: 44)
                Spacer(minLength: 0)
            }
        case .extraLarge:
            extraLarge(quote)
        }
    }

    private func extraLarge(_ quote: RateQuote) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetTitle(title: quote.pair.id, symbol: "chart.line.uptrend.xyaxis", tint: Palette.green)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    figure(quote, size: 38)
                    change(quote)
                }
                chart(quote, height: 170)
                stats(quote)
                Spacer(minLength: 0)
                sourceNote(quote)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    WidgetSection(title: loc("All pairs"))
                    Spacer()
                    Text(updated).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                pairs(limit: 7, chartHeight: 38)
                Spacer(minLength: 0)
            }
        }
    }

    private var updated: String {
        rates.updatedAt.map { loc("Updated \(Format.dataTime($0, now: context.now))") } ?? ""
    }

    private func figure(_ quote: RateQuote, size: CGFloat) -> some View {
        Text(Format.exchangeRate(quote.value))
            .font(.widgetFigure(size))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func tint(_ quote: RateQuote) -> Color {
        rates.isStale ? Palette.gray : quote.isUp ? Palette.green : Palette.red
    }

    private func change(_ quote: RateQuote) -> some View {
        Text("\(quote.isUp ? "▲" : "▼") \(Format.signedPercent(quote.changeShare))")
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(tint(quote))
            .lineLimit(1)
            .widgetAccentable()
    }

    private func sourceNote(_ quote: RateQuote) -> some View {
        Text(quote.source.title).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
    }

    private func chart(_ quote: RateQuote, height: CGFloat) -> some View {
        InteractiveChart(
            series: [series(quote)],
            domain: ItemContent.padded(quote.history.map(\.value)),
            height: height,
            tooltipDate: .dateTime.day().month(),
            initialHover: chartHover
        )
    }

    private func series(_ quote: RateQuote) -> ChartSeries {
        ChartSeries(
            id: quote.id,
            title: quote.pair.id,
            color: tint(quote),
            points: quote.history.map { History<Double>.Point(date: $0.date, value: $0.value) },
            format: { Format.exchangeRate($0) }
        )
    }

    private func range(_ quote: RateQuote) -> some View {
        let values = quote.history.map(\.value)
        return HStack {
            WidgetSection(title: loc("30 days"))
            Spacer()
            if let high = values.max(), let low = values.min() {
                let top = Format.exchangeRate(high)
                let bottom = Format.exchangeRate(low)
                Text(loc("H \(top) · L \(bottom)")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func stats(_ quote: RateQuote) -> some View {
        let values = quote.history.map(\.value)
        return HStack(spacing: 6) {
            plate(loc("Open"), values.first)
            plate(loc("High"), values.max())
            plate(loc("Low"), values.min())
        }
    }

    private func plate(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            WidgetSection(title: title)
            Text(value.map { Format.exchangeRate($0) } ?? "—")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 9))
    }

    private func pairs(limit: Int, chartHeight: CGFloat) -> some View {
        VStack(spacing: 5) {
            ForEach(rates.quotes.prefix(limit)) { quote in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(quote.pair.id).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        sourceNote(quote)
                    }
                    .frame(width: 76, alignment: .leading)
                    if quote.history.count > 1 {
                        chart(quote, height: chartHeight).frame(maxWidth: .infinity)
                    } else {
                        Spacer()
                    }
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Format.exchangeRate(quote.value))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                        change(quote).font(.system(size: 10, weight: .semibold))
                    }
                    .frame(width: 74, alignment: .trailing)
                }
            }
        }
    }
}
