import GlassWorkCore
import SwiftUI

/// A word a day from the Mac's own dictionary, with the days before it as it grows.
struct WordOfDayWidget: View {
    let context: TimeContext

    private var words: [WordOfDay] {
        context.snapshot.words
    }

    var body: some View {
        if let today = words.first {
            switch context.size {
            case .small:
                VStack(alignment: .leading, spacing: 4) {
                    WidgetCapsTitle(title: loc("Word of the Day"), tint: Palette.teal)
                    title(today, size: 24)
                    details(today)
                    meaning(today, lines: 3).padding(.top, 3)
                    Spacer(minLength: 0)
                    Text(dateText).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            case .medium:
                VStack(alignment: .leading, spacing: 6) {
                    header
                    title(today, size: 30)
                    details(today)
                    meaning(today, lines: 3)
                    Spacer(minLength: 0)
                }
            case .large:
                VStack(alignment: .leading, spacing: 8) {
                    entry(today, lines: 5)
                    Spacer(minLength: 0)
                }
            case .extraLarge:
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        entry(today, lines: 8)
                        Spacer(minLength: 0)
                    }
                    Divider()
                    earlier(limit: 5).frame(width: 340)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetCapsTitle(title: loc("Word of the Day"), tint: Palette.teal)
                Spacer()
                Text(loc("Open GlassWork to look up today's word"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var dateText: String {
        context.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var header: some View {
        HStack {
            WidgetCapsTitle(title: loc("Word of the Day"), tint: Palette.teal)
            Spacer(minLength: 6)
            Text(dateText).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
        }
    }

    @ViewBuilder
    private func entry(_ word: WordOfDay, lines: Int) -> some View {
        header
        title(word, size: 30)
        details(word)
        meaning(word, lines: lines)
        if word.definition != nil, let example = word.example {
            Text(verbatim: "“\(example)”").font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(3)
        }
        if !word.synonyms.isEmpty {
            Divider().padding(.vertical, 2)
            WidgetSection(title: loc("Similar"))
            HStack(spacing: 6) {
                ForEach(word.synonyms.prefix(4), id: \.self) { synonym in
                    Text(synonym)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: .capsule)
                }
            }
        }
        if context.size == .large {
            Divider().padding(.vertical, 2)
            earlier(limit: 3)
        }
    }

    private func title(_ word: WordOfDay, size: CGFloat) -> some View {
        Text(word.word)
            .font(.system(size: size, weight: .bold))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    private func details(_ word: WordOfDay) -> some View {
        HStack(spacing: 8) {
            if let pronunciation = word.pronunciation {
                Text(verbatim: "/\(pronunciation)/").foregroundStyle(.secondary).lineLimit(1)
            }
            if let part = word.partOfSpeech {
                if context.size == .small {
                    Text(part).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(part)
                        .foregroundStyle(Palette.teal)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 2)
                        .background(Palette.teal.opacity(0.15), in: .capsule)
                        .widgetAccentable()
                }
            }
        }
        .font(.system(size: context.size == .small ? 11 : 12))
    }

    /// The thesaurus often gives an example and synonyms instead of a definition.
    @ViewBuilder
    private func meaning(_ word: WordOfDay, lines: Int) -> some View {
        if let definition = word.definition {
            Text(definition).font(.system(size: 13)).lineLimit(lines)
        } else if let example = word.example {
            Text(verbatim: "“\(example)”").font(.system(size: 13)).lineLimit(lines)
        }
    }

    private func earlier(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetSection(title: loc("Earlier"))
            ForEach(words.dropFirst().prefix(limit)) { word in
                VStack(alignment: .leading, spacing: 1) {
                    Text(word.word).font(.system(size: 14, weight: .semibold))
                    if let text = word.definition ?? word.example ?? word.synonyms.first {
                        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
