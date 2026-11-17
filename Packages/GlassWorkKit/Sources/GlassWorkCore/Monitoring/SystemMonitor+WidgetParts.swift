import Foundation

/// Pieces of the widget snapshot that come from one store each.
extension SystemMonitor {
    var widgetWeather: WidgetWeather {
        WidgetWeather(reports: weather.reports, isStale: weather.isStale, hasPlaces: !weather.places.isEmpty)
    }

    var widgetRates: WidgetRates {
        WidgetRates(quotes: rates.snapshot.quotes, updatedAt: rates.snapshot.updatedAt, isStale: rates.isStale)
    }
}
