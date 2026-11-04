import Foundation
import Observation

/// Where the Mac's own position stands. It stays `.off` until the user turns it on.
public enum LocationStatus: Sendable, Equatable {
    case off, waiting, denied, ready
}

/// Forecasts for the user's places. Asks Open-Meteo only while something on screen needs them.
@MainActor
@Observable
public final class WeatherStore {
    public private(set) var reports: [WeatherReport]
    public private(set) var status = FetchStatus.idle
    public private(set) var settings = WeatherSettings()
    public private(set) var currentPlace: WeatherPlace?
    public var locationStatus = LocationStatus.off
    /// Set by the app: true while the module is in the menu bar or a panel is open.
    public var isActive = false

    @ObservationIgnored private let fetcher: any HTTPFetching
    @ObservationIgnored private let store: SnapshotStore
    @ObservationIgnored private var schedule: RefreshSchedule

    public init(fetcher: any HTTPFetching = URLSessionFetcher(), store: SnapshotStore = SnapshotStore()) {
        self.fetcher = fetcher
        self.store = store
        let saved = store.read(WeatherSnapshot.self, for: WeatherSnapshot.key)?.reports ?? []
        reports = saved
        schedule = RefreshSchedule(lastSuccess: saved.map(\.fetchedAt).max())
    }

    /// The Mac's position first, then the user's cities. The first one shows in the menu bar.
    public var places: [WeatherPlace] {
        (settings.useCurrentLocation ? [currentPlace].compactMap(\.self) : []) + settings.places
    }

    public var primaryReport: WeatherReport? {
        places.lazy.compactMap { self.report(for: $0) }.first
    }

    public func report(for place: WeatherPlace) -> WeatherReport? {
        reports.first { $0.place.id == place.id }
    }

    /// Whether the data on screen did not come from the latest attempt.
    public var isStale: Bool {
        status == .offline || status == .failed
    }

    public func apply(_ new: WeatherSettings) {
        guard new != settings else { return }
        let placesChanged = new.places != settings.places || new.useCurrentLocation != settings.useCurrentLocation
        settings = new
        if placesChanged {
            schedule.expire()
        }
    }

    public func setCurrentPlace(_ place: WeatherPlace?) {
        guard place != currentPlace else { return }
        currentPlace = place
        schedule.expire()
    }

    /// Called on every monitor read, which also pauses this during sleep.
    public func tick(at date: Date) {
        guard isActive, status != .loading, !places.isEmpty, schedule.isDue(at: date) else { return }
        Task { await refresh(at: date) }
    }

    /// Asks for every place. Failed places keep their last report.
    public func refresh(at date: Date = Date()) async {
        guard status != .loading else { return }
        status = .loading
        let results = await fetch(places, at: date)
        let fresh = results.compactMap { try? $0.get() }
        let failure = results.lazy.compactMap { result -> (any Error)? in
            if case let .failure(error) = result {
                return error
            }
            return nil
        }.first
        if !fresh.isEmpty {
            merge(fresh)
        }
        schedule.record(success: failure == nil, at: date)
        status = failure.map { FetchStatus.isOffline($0) ? .offline : .failed } ?? .ready
    }

    /// Clears the wait after a failure, for the Try Again button.
    public func retry() async {
        schedule.expire()
        await refresh()
    }

    public func search(_ query: String) async throws -> [WeatherPlace] {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        guard let url = OpenMeteo.searchURL(for: query, language: language) else { return [] }
        return try await OpenMeteo.places(from: fetcher.data(from: url))
    }

    private func merge(_ fresh: [WeatherReport]) {
        let kept = reports.filter { old in
            places.contains { $0.id == old.place.id } && !fresh.contains { $0.place.id == old.place.id }
        }
        reports = kept + fresh
        try? store.write(WeatherSnapshot(reports: reports), for: WeatherSnapshot.key)
    }

    private func fetch(_ places: [WeatherPlace], at date: Date) async -> [Result<WeatherReport, any Error>] {
        let fetcher = fetcher
        return await withTaskGroup(of: Result<WeatherReport, any Error>.self) { group in
            for place in places {
                group.addTask {
                    await Self.result(for: place, fetcher: fetcher, at: date)
                }
            }
            var results: [Result<WeatherReport, any Error>] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private nonisolated static func result(
        for place: WeatherPlace,
        fetcher: any HTTPFetching,
        at date: Date
    ) async -> Result<WeatherReport, any Error> {
        guard let url = OpenMeteo.forecastURL(for: place) else { return .failure(URLError(.badURL)) }
        do {
            return try await .success(OpenMeteo.report(from: fetcher.data(from: url), place: place, now: date))
        } catch {
            return .failure(error)
        }
    }
}
