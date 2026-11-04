import Foundation

/// Words the Word of the Day draws from, in a fixed order. The system dictionary cannot list its words,
/// so the choice comes from this list and the dictionary only supplies the meaning.
public enum WordList {
    public static let words: [String] = [
        "aplomb", "ardent", "arduous", "avid", "banal", "benevolent", "bolster", "candid", "capricious", "cascade",
        "catalyst", "cherish", "cogent", "compelling", "concise", "conundrum", "copious", "cryptic", "cultivate",
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
