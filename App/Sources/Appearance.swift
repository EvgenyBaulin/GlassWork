import AppKit

/// Switches macOS between light and dark.
///
/// Uses the system's own private call, because scripting System Events needs an Automation prompt.
enum Appearance {
    private typealias SetTheme = @convention(c) (Bool) -> Void

    static func toggle() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(library, "SLSSetAppearanceThemeLegacy")
        else { return }
        unsafeBitCast(symbol, to: SetTheme.self)(!isDark)
    }
}
