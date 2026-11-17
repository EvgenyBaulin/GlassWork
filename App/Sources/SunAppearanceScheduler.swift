import Foundation
import GlassWorkCore

/// Switches to dark after sunset and to light after sunrise while the Appearance module follows the sun.
///
/// It looks once a minute, which is cheap, and also right after the Mac wakes: a timer set for the exact moment
/// would fire late then. It acts only once the sunrise or sunset it was waiting for has passed, so a click on the
/// Appearance item holds until then, and a sunrise slept through is still applied on waking.
@MainActor
final class SunAppearanceScheduler {
    private var timer: Timer?
    private var nextEvent: Date?
    private var place: () -> WeatherPlace? = { nil }

    /// Starts or stops with the option. `place` is asked again at every look, since a position may arrive later.
    func apply(isOn: Bool, place: @escaping () -> WeatherPlace?) {
        self.place = place
        guard isOn else {
            timer?.invalidate()
            timer = nil
            nextEvent = nil
            return
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.look() }
        }
        look()
    }

    private func look(at date: Date = Date()) {
        guard let place = place() else { return }
        let result = SunAppearance.look(
            at: date,
            latitude: place.latitude,
            longitude: place.longitude,
            nextEvent: nextEvent
        )
        nextEvent = result.nextEvent
        if let dark = result.dark, dark != Appearance.isDark {
            Appearance.set(dark: dark)
        }
    }
}
