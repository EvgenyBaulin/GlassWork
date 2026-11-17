import Foundation

/// Words the Word of the Day draws from, in a fixed order. The system dictionary cannot list its words,
/// so the choice comes from this list and the dictionary only supplies the meaning.
public enum WordList {
    public static let words: [String] = [
        "aplomb", "ardent", "arduous", "avid", "banal", "benevolent", "bolster", "candid", "capricious", "cascade",
        "cherish", "cogent", "compelling", "concise", "conundrum", "copious", "cryptic", "cultivate",
        "debacle", "deft", "delineate", "diligent", "discern", "diverge", "eclectic", "elegant", "elicit", "eloquent",
        "elusive", "embark", "emulate", "endeavour", "enigma", "ephemeral", "equanimity", "erudite", "esoteric",
        "euphoria", "exacerbate", "exemplary", "exuberant", "facet", "fastidious", "fathom", "fervent", "flourish",
        "fortitude", "frugal", "futile", "gregarious", "halcyon", "hapless", "harbinger", "hinder", "hone",
        "idiosyncrasy", "immerse", "impetus", "inadvertent", "incessant", "indelible", "ineffable", "ingenuity",
        "inherent", "innate", "insatiable", "intrepid", "intricate", "inundate", "jubilant", "juxtapose", "keen",
        "kindle", "labyrinth", "languid", "lavish", "lethargic", "lucid", "luminous", "magnanimous", "malleable",
        "meander", "mellifluous", "meticulous", "mitigate", "mundane", "nebulous", "nimble", "nostalgia", "nuance",
        "obscure", "obsolete", "ominous", "opulent", "oscillate", "paradox", "pensive", "perennial", "perpetual",
        "pervade", "pinnacle", "placid", "plausible", "poignant", "pragmatic", "precarious", "prodigious", "profound",
        "prolific", "quaint", "quell", "quixotic", "radiant", "rapport", "reclusive", "redolent", "refute",
        "relentless",
        "reminisce", "resilient", "reverie", "rhetoric", "robust", "sagacity", "salient", "scrutinize", "serene",
        "serendipity", "sincere", "solace", "solitude", "sporadic", "stoic", "subtle", "succinct", "surmise",
        "tangible",
        "tenacious", "tranquil", "transient", "trepidation", "ubiquitous", "unwavering", "usurp", "vagabond", "valiant",
        "venerable", "verbose", "vestige", "vibrant", "vicarious", "vigilant", "vivid", "volatile", "wane", "whimsical",
        "wistful", "zealous", "zenith", "abate", "adept", "alleviate", "ambiguous", "amiable", "astute", "austere",
        "bemused", "blithe", "brevity", "buoyant", "cacophony", "clandestine", "convivial", "dexterous", "dwindle",
        "ebullient", "effervescent", "ethereal", "fickle", "fleeting", "garrulous", "gossamer", "impeccable", "jovial",
        "lithe", "mirth", "mollify", "ornate", "pristine", "quandary", "raucous", "sanguine", "tacit", "zephyr",
    ]

    /// The word for a day. The same day always gives the same word, and consecutive days differ.
    public static func word(on date: Date, calendar: Calendar = .current) -> String {
        words[index(on: date, calendar: calendar)]
    }

    public static func index(on date: Date, calendar: Calendar = .current) -> Int {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return day % words.count
    }
}

/// How unusual the words may be.
public enum WordLevel: String, Codable, CaseIterable, Sendable {
    /// Words people meet in everyday reading.
    case common
    /// The same words and the rarer ones as well.
    case any
}

public extension WordList {
    /// Languages that have a list of words.
    static let languages = ["en", "ru"]

    static let rareEnglish: [String] = [
        "acrimony", "bucolic", "calumny", "crepuscular", "defenestrate", "demure", "effulgent", "epiphany",
        "foment", "grandiloquent", "ineluctable", "loquacious", "lugubrious", "mendacious", "nefarious", "obstreperous",
        "pellucid", "perspicacious", "propinquity", "recondite", "sanctimonious", "susurrus", "taciturn", "umbrage",
        "vicissitude", "winsome", "obsequious", "ostensible", "zeitgeist", "abstruse",
    ]

    static let russian: [String] = [
        "ветер", "дорога", "память", "тишина", "свет", "река", "мост", "окно", "дружба", "надежда", "радость",
        "глубина", "поле", "звезда", "огонь", "дождь", "туман", "лес", "море", "берег", "путь", "песня", "сон",
        "тепло", "время", "мечта", "смелость", "терпение", "любопытство", "уют", "простор", "рассвет", "закат",
        "гроза", "радуга", "родник", "тропа", "ветка", "облако", "цветок", "улыбка", "шаг", "голос", "взгляд",
        "сила", "покой", "вечер", "утро", "зима", "весна", "лето", "осень", "город", "книга", "чудо", "добро",
        "правда", "мудрость", "забота",
    ]

    static let rareRussian: [String] = [
        "сумерки", "безмятежность", "сокровенный", "рачительный", "лучезарный", "задумчивый", "окоём", "хрусталь",
        "пытливый", "раздолье", "благодать", "прозорливый", "умиротворение", "отрада", "бескрайний", "вдохновение",
        "чаяние", "многоликий", "неспешный", "заповедный",
    ]

    /// The words of a language at a level. An unknown language gets English.
    static func words(language: String, level: WordLevel) -> [String] {
        let isRussian = language == "ru"
        let common = isRussian ? russian : words
        return level == .common ? common : common + (isRussian ? rareRussian : rareEnglish)
    }

    static func word(on date: Date, language: String, level: WordLevel, calendar: Calendar = .current) -> String {
        let list = words(language: language, level: level)
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return list[day % list.count]
    }
}
