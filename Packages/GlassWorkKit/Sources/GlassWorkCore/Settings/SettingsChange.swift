import Foundation

/// What differs between two versions of the settings, in terms a toast can name.
public struct SettingsChange: Sendable, Equatable {
    public enum Area: String, Sendable, CaseIterable {
        case modules, numberStyle, hiding, alerts, widgets, personalWidgets, dock, weather, rates
        case clipboard, fans, windowTiles, hub, island, diagnosticLog, shortcuts, other
    }

    public let area: Area
    /// Set when exactly one module changed.
    public let module: ModuleID?

    public init(area: Area, module: ModuleID? = nil) {
        self.area = area
        self.module = module
    }

    public init(from old: AppSettings, to new: AppSettings) {
        if old.modules != new.modules {
            let changed = zip(old.modules, new.modules).filter { $0 != $1 }.map(\.0.id)
            let sameShape = old.modules.count == new.modules.count && old.modules.map(\.id) == new.modules.map(\.id)
            self.init(area: .modules, module: sameShape && changed.count == 1 ? changed[0] : nil)
            return
        }
        let areas: [(Area, Bool)] = [
            (.numberStyle, old.numberStyle != new.numberStyle),
            (.hiding, old.hiding != new.hiding),
            (.alerts, old.alerts != new.alerts),
            (.widgets, old.widgets != new.widgets),
            (.personalWidgets, old.personalWidgets != new.personalWidgets),
            (.dock, old.dock != new.dock),
            (.weather, old.weather != new.weather),
            (.rates, old.rates != new.rates),
            (.clipboard, old.clipboard != new.clipboard),
            (.fans, old.fans != new.fans),
            (.windowTiles, old.windowTiles != new.windowTiles),
            (.hub, old.hub != new.hub),
            (.island, old.island != new.island),
            (.diagnosticLog, old.keepsDiagnosticLog != new.keepsDiagnosticLog),
            (.shortcuts, old.shortcuts != new.shortcuts),
        ]
        let changed = areas.filter(\.1).map(\.0)
        self.init(area: changed.count == 1 ? changed[0] : .other)
    }
}
