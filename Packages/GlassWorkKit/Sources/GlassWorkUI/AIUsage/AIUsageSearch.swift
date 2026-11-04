import GlassWorkCore

/// How Settings search finds this module. It lives here with the rest of the module's text.
enum ModuleSearchExtras {
    static let words: [ModuleSearchWords] = [
        ModuleSearchWords(
            module: .aiUsage,
            english: "AI Usage",
            russian: "Использование ИИ",
            keywords: ["limits", "tokens", "лимиты", "токены", "Claude Code", "Codex", "Gemini"]
        ),
    ]
}
