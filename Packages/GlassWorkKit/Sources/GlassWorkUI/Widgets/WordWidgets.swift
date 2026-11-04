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
                    header
                    Spacer()
                    title(today, size: 26)
                    partOfSpeech(today)
                }
            case .medium:
                VStack(alignment: .leading, spacing: 6) {
                    header
                    title(today, size: 28)
                    partOfSpeech(today)
                    body(today, lines: 3)
                    Spacer(minLength: 0)
                }
            case .large:
                VStack(alignment: .leading, spacing: 8) {
                    header
                    title(today, size: 34)
                    partOfSpeech(today)
                    body(today, lines: 5)
                    Divider()
                    earlier(limit: 3)
                    Spacer(minLength: 0)
                }
            case .extraLarge:
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        header
                        title(today, size: 48)
                        partOfSpeech(today)
                        body(today, lines: 8)
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        earlier(limit: 5)
                        Spacer(minLength: 0)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                header
                Spacer()
                Text(loc("Open GlassWork to look up today's word"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var header: some View {
        WidgetHeader(title: loc("Word of the Day"), symbol: "character.book.closed", tint: Palette.purple)
    }

    private func title(_ word: WordOfDay, size: CGFloat) -> some View {
        Text(word.word)
            .font(.system(size: size, weight: .semibold, design: .serif))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    private func partOfSpeech(_ word: WordOfDay) -> some View {
        HStack(spacing: 6) {
            if let part = word.partOfSpeech {
                Text(part).italic().foregroundStyle(Palette.purple)
            }
            if let pronunciation = word.pronunciation, context.size != .small {
                Text("|\(pronunciation)|").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
    }

    @ViewBuilder
    private func body(_ word: WordOfDay, lines: Int) -> some View {
        if let definition = word.definition {
            Text(definition).font(.system(size: 13)).lineLimit(lines)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if let example = word.example {
                    Text(verbatim: "“\(example)”").font(.system(size: 13).italic()).lineLimit(max(lines / 2, 2))
                }
                if !word.synonyms.isEmpty {
                    Text(loc("Similar: \(word.synonyms.joined(separator: ", "))"))
                        .font(.system(size: 13))
                        .foregroundStyle(word.example == nil ? .primary : .secondary)
                        .lineLimit(lines)
                }
            }
        }
    }

    private func earlier(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("Earlier")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(words.dropFirst().prefix(limit)) { word in
                VStack(alignment: .leading, spacing: 1) {
                    Text(word.word).font(.system(size: 14, weight: .semibold, design: .serif))
                    if let text = word.definition ?? word.example ?? word.synonyms.first {
                        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }
}
