import Foundation
import GlassWorkCore

/// Switches to dark after sunset and to light after sunrise while the Appearance module follows the sun.
///
/// It looks once a minute, which is cheap, and also right after the Mac wakes: a timer set for the exact moment
/// would fire late then. It acts only when the sun's side of the day changes, so a click on the Appearance item
/// holds until the next sunrise or sunset.
@MainActor
final class SunAppearanceScheduler {
    private var timer: Timer?
    private var last: Bool?
    private var place: () -> WeatherPlace? = { nil }

    /// Starts or stops with the option. `place` is asked again at every look, since a position may arrive later.
    func apply(isOn: Bool, place: @escaping () -> WeatherPlace?) {
        self.place = place
        guard isOn else {
            timer?.invalidate()
            timer = nil
            last = nil
            return
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.look() }
        }
        look()
    }

    private func look(at date: Date = Date()) {
        let wanted = place()
            .flatMap { SunAppearance.wantsDark(at: date, latitude: $0.latitude, longitude: $0.longitude) }
        guard let dark = SunAppearance.change(wanted: wanted, last: last) else { return }
        last = dark
        if dark != Appearance.isDark {
            Appearance.set(dark: dark)
        }
    }
}
