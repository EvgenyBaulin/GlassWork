import GlassWorkCore
import SwiftUI

/// What the sidebar shows while something is typed in the search field.
public struct SettingsSearchResults: View {
    private let query: String
    private let opened: String?
    private let open: (SettingsResult) -> Void

    public init(query: String, opened: String?, open: @escaping (SettingsResult) -> Void) {
        self.query = query
        self.opened = opened
        self.open = open
    }

    public var body: some View {
        let results = SettingsIndex.search(query)
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc("\(results.count) results · EN + RU keywords"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                ForEach(results, id: \.result.id) { item in
                    row(item.result, match: item.match)
                }
                if results.isEmpty {
                    Text(loc("Nothing found"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                } else {
                    Text(loc("↩ opens the first result"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ result: SettingsResult, match: SettingMatch) -> some View {
        let isOpened = result.id == opened
        return Button {
            open(result)
        } label: {
            HStack(spacing: 8) {
                icon(result)
                VStack(alignment: .leading, spacing: 1) {
                    Text(highlighted(result.title))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(caption(result, match: match))
                        .font(.system(size: 11))
                        .foregroundStyle(isOpened ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(isOpened ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(isOpened ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7))
            .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func icon(_ result: SettingsResult) -> some View {
        if let module = result.module {
            ModuleIcon(module, size: 22)
        } else {
            Image(systemName: "gearshape")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.gray.gradient, in: .rect(cornerRadius: 5))
        }
    }

    /// The breadcrumb, plus the word that matched when the title alone would not explain the hit.
    private func caption(_ result: SettingsResult, match: SettingMatch) -> String {
        guard let word = match.matchedWord, word != result.title else { return result.breadcrumb }
        return "\(result.breadcrumb) · \(word)"
    }

    private func highlighted(_ title: String) -> AttributedString {
        var text = AttributedString(title)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty, let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].backgroundColor = Palette.yellow.opacity(0.35)
        }
        return text
    }
}
