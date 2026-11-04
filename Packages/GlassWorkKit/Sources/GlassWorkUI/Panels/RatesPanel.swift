import GlassWorkCore
import SwiftUI

extension RateSource {
    var title: String {
        switch self {
        case .cbr: loc("CBR")
        case .frankfurter: loc("ECB")
        case .coinGecko: "CoinGecko"
        }
    }
}

/// Every configured pair with its day change and chart, or the list of pairs.
struct RatesPanel: View {
    let store: RatesStore
    @State private var isEditing = false
    @State private var hovered: RatePair?

    var body: some View {
        PanelFrame(
            module: .rates,
            subtitle: subtitle,
            footerTitle: isEditing ? loc("Done") : loc("Edit pairs"),
            footerAction: { isEditing.toggle() }
        ) {
            if isEditing {
                RatePairsEditor(store: store)
            } else {
                banner
                pairs
            }
        }
    }

    private var subtitle: String {
        guard let date = store.snapshot.updatedAt else { return "" }
        return loc("Updated \(date.formatted(date: .omitted, time: .shortened))")
    }

    @ViewBuilder
    private var banner: some View {
        if store.isStale {
            let date = store.snapshot.updatedAt?.formatted(.dateTime.weekday().day().month().hour().minute())
            PanelBanner(
                symbol: "icloud.slash",
                title: loc("You’re offline"),
                message: date.map { loc("Rates from \($0)") } ?? loc("No saved rates yet"),
                actionTitle: loc("Retry"),
                action: retry
            )
        } else if !store.failedSources.isEmpty {
            PanelBanner(
                symbol: "exclamationmark.triangle",
                title: failureTitle,
                message: loc("Will retry in 5 min"),
                actionTitle: loc("Retry"),
                action: retry
            )
        }
    }

    private var failureTitle: String {
        let names = store.failedSources.map(\.title).sorted()
        return names.count == 1
            ? loc("\(names[0]) is not responding")
            : loc("Not responding: \(names.joined(separator: ", "))")
    }

    @ViewBuilder
    private var pairs: some View {
        if store.snapshot.quotes.isEmpty, store.status == .loading || store.status == .idle {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 40)
        } else {
            VStack(spacing: 2) {
                ForEach(store.settings.pairs) { pair in
                    RateRow(
                        pair: pair,
                        quote: store.snapshot.quote(for: pair),
                        isStale: store.isStale,
                        isUnavailable: store.isUnavailable(pair)
                    )
                    .background(hovered == pair ? .white.opacity(0.06) : .clear, in: .rect(cornerRadius: 8))
                    .onHover { hovered = $0 ? pair : hovered == pair ? nil : hovered }
                    .zIndex(hovered == pair ? 1 : 0)
                }
            }
        }
    }

    private func retry() {
        Task { await store.retry() }
    }
}

/// One pair: name and source, a chart that answers to the cursor, the value and its day change.
struct RateRow: View {
    let pair: RatePair
    let quote: RateQuote?
    var isStale = false
    var isUnavailable = false
    var initialHover: Date?

    private var isOld: Bool {
        isStale || isUnavailable
    }

    private var tint: Color {
        guard let quote, !isStale else { return Palette.gray }
        return quote.isUp ? Palette.green : Palette.red
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(pair.id).font(.system(size: 13, weight: .semibold))
                Text(pair.source?.title ?? "—").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(width: 78, alignment: .leading)
            middle.frame(maxWidth: .infinity)
            VStack(alignment: .trailing, spacing: 1) {
                Text(isUnavailable ? "—" : quote.map { Format.exchangeRate($0.value) } ?? "—")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                change
            }
            .frame(width: 98, alignment: .trailing)
        }
        .opacity(isStale ? 0.7 : 1)
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var middle: some View {
        if isUnavailable {
            Text(loc("Source unavailable")).font(.system(size: 11)).foregroundStyle(Palette.orange).lineLimit(1)
        } else if let quote, quote.history.count > 1 {
            InteractiveChart(
                series: [series(quote)],
                domain: ItemContent.padded(quote.history.map(\.value)),
                height: 32,
                tooltipDate: .dateTime.day().month(),
                initialHover: initialHover
            )
        } else {
            // Keeps the columns in place for a pair that has only one value so far.
            Color.clear.frame(height: 32)
        }
    }

    @ViewBuilder
    private var change: some View {
        if let quote, !isOld {
            Text(changeText(quote))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
        } else {
            Text("—").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func changeText(_ quote: RateQuote) -> String {
        let amount = Format.exchangeRateChange(quote.change, of: quote.value)
        return "\(quote.isUp ? "↑" : "↓") \(amount)  \(Format.signedPercent(quote.changeShare))"
    }

    private func series(_ quote: RateQuote) -> ChartSeries {
        var history = History<Double>(capacity: max(quote.history.count, 1))
        for point in quote.history {
            history.append(point.value, at: point.date)
        }
        return ChartSeries(
            id: pair.id,
            title: pair.id,
            color: tint,
            points: history.points,
            format: { Format.exchangeRate($0) }
        )
    }
}

/// Reorder, remove and add pairs, and choose the one in the menu bar.
struct RatePairsEditor: View {
    let store: RatesStore
    @State private var text = ""
    @Environment(\.panelActions) private var actions

    private static let rowHeight: CGFloat = 26

    private var typed: RatePair? {
        RatePair(parsing: text)
    }

    private var canAdd: Bool {
        guard let typed else { return false }
        return typed.source != nil && !store.settings.pairs.contains(typed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSection(title: loc("Pairs · drag to reorder"), caption: loc("In bar")) {
                List {
                    ForEach(store.settings.pairs) { pair in
                        row(pair)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove(perform: move)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: min(CGFloat(store.settings.pairs.count) * Self.rowHeight, 182))
            }
            PanelSection(title: loc("Add a pair")) {
                HStack {
                    TextField("GBP/RUB", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button(loc("Add"), action: add)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAdd)
                }
                validation
            }
        }
    }

    @ViewBuilder
    private var validation: some View {
        if let typed, !text.isEmpty {
            if store.settings.pairs.contains(typed) {
                Text(loc("Already in the list")).foregroundStyle(.secondary).font(.system(size: 11))
            } else if let source = typed.source {
                Text("✓ \(typed.id) · \(source.title)").foregroundStyle(Palette.green).font(.system(size: 11))
            } else {
                Text(loc("No source publishes this pair")).foregroundStyle(Palette.orange).font(.system(size: 11))
            }
        } else {
            Text(loc("Fiat: CBR, ECB · Crypto: CoinGecko")).foregroundStyle(.tertiary).font(.system(size: 11))
        }
    }

    private func row(_ pair: RatePair) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal").font(.system(size: 11)).foregroundStyle(.tertiary)
            Text(pair.id).font(.system(size: 13, weight: .semibold))
            Text(pair.source?.title ?? "—").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button {
                actions.updateSettings { $0.rates.barPair = pair }
            } label: {
                let isShown = store.settings.shownPair == pair
                Image(systemName: isShown ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isShown ? Palette.blue : .secondary)
            }
            .buttonStyle(.plain)
            .help(loc("Show in the menu bar"))
            Button {
                actions.updateSettings { $0.rates.pairs.removeAll { $0 == pair } }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(loc("Remove"))
        }
    }

    private func add() {
        guard canAdd, let typed else { return }
        actions.updateSettings { $0.rates.pairs.append(typed) }
        text = ""
    }

    private func move(from source: IndexSet, to destination: Int) {
        actions.updateSettings { $0.rates.pairs.move(fromOffsets: source, toOffset: destination) }
    }
}
