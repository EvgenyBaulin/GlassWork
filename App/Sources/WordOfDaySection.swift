import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// Which language the word is in, which dictionary explains it and how rare the words may be.
struct WordOfDaySection: View {
    let store: SettingsStore
    @State private var dictionaries: [SystemDictionary] = []

    private var settings: WordOfDaySettings {
        store.settings.widgets.wordOfDay
    }

    var body: some View {
        Section(loc("Word of the Day")) {
            Picker(loc("Language"), selection: binding(\.language)) {
                ForEach(SystemDictionaries.languages(in: dictionaries), id: \.self) {
                    Text(Self.name(of: $0)).tag($0)
                }
            }
            Picker(loc("Dictionary"), selection: binding(\.dictionaryID)) {
                Text(loc("Automatic")).tag(String?.none)
                ForEach(SystemDictionaries.dictionaries(for: settings.language, in: dictionaries)) {
                    Text($0.name).tag(String?.some($0.id))
                }
            }
            Picker(loc("Words"), selection: binding(\.level)) {
                Text(loc("Common words")).tag(WordLevel.common)
                Text(loc("Any words")).tag(WordLevel.any)
            }
        }
        .task { dictionaries = await Task.detached { SystemDictionaries.installed() }.value }
    }

    /// A new language drops the dictionary, which may not know it.
    private func binding<Value>(_ keyPath: WritableKeyPath<WordOfDaySettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                store.update { settings in
                    let previous = settings.widgets.wordOfDay.language
                    settings.widgets.wordOfDay[keyPath: keyPath] = value
                    if settings.widgets.wordOfDay.language != previous {
                        settings.widgets.wordOfDay.dictionaryID = nil
                    }
                }
            }
        )
    }

    private static func name(of language: String) -> String {
        Locale.current.localizedString(forLanguageCode: language)?.capitalized ?? language
    }
}
