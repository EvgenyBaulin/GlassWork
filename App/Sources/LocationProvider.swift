import CoreLocation
import GlassWorkCore

/// The Mac's position for the Weather module.
///
/// The manager does not exist until the user turns the option on, so macOS is never asked before that.
@MainActor
final class LocationProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let store: WeatherStore
    private var manager: CLLocationManager?

    init(store: WeatherStore) {
        self.store = store
    }

    func apply(isOn: Bool) {
        guard isOn != (manager != nil) else { return }
        if isOn {
            let created = CLLocationManager()
            created.delegate = self
            created.desiredAccuracy = kCLLocationAccuracyKilometer
            manager = created
            store.locationStatus = .waiting
            update(created)
        } else {
            manager?.delegate = nil
            manager = nil
            store.locationStatus = .off
            store.setCurrentPlace(nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        update(manager)
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let position = locations.last?.coordinate else { return }
        store.locationStatus = .ready
        store.setCurrentPlace(WeatherPlace(
            id: WeatherPlace.currentLocationID,
            name: "",
            country: "",
            latitude: Self.rounded(position.latitude),
            longitude: Self.rounded(position.longitude)
        ))
    }

    func locationManager(_: CLLocationManager, didFailWithError error: any Error) {
        if (error as? CLError)?.code == .denied {
            store.locationStatus = .denied
        }
    }

    private func update(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: store.locationStatus = .denied
        default: manager.requestLocation()
        }
    }

    /// About a kilometre: all a forecast needs, and all that leaves the Mac.
    private static func rounded(_ degrees: Double) -> Double {
        (degrees * 100).rounded() / 100
    }
}
