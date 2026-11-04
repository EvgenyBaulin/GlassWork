import Foundation

/// Fan control as a widget sees it. The extension cannot ask the app, so all of this travels in the snapshot.
public struct WidgetFanState: Codable, Sendable, Equatable {
    public enum Control: String, Codable, Sendable {
        /// The service runs and the user turned control on.
        case ready
        /// The service is installed, but control is off in Settings.
        case off
        case notInstalled
        /// Waiting for the user to allow the service in System Settings.
        case needsApproval
    }

    public enum Notice: Codable, Sendable, Equatable {
        case failsafeMax(celsius: Double)
        case returnedToAuto
    }

    public struct Preset: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public var mode: FanMode
    public var control: Control
    public var notice: Notice?
    public var presets: [Preset]
    public var selectedPresetID: String
    public var curve: [FanCurve.Point]
    public var sensor: SensorChoice
    public var customRPM: Double

    public init(
        mode: FanMode = .auto,
        control: Control = .notInstalled,
        notice: Notice? = nil,
        presets: [Preset] = FanPreset.builtIn.map { Preset(id: $0.id, name: $0.name) },
        selectedPresetID: String = FanPreset.balanced.id,
        curve: [FanCurve.Point] = FanPreset.balanced.curve.points,
        sensor: SensorChoice = .averageCPU,
        customRPM: Double = 0
    ) {
        self.mode = mode
        self.control = control
        self.notice = notice
        self.presets = presets
        self.selectedPresetID = selectedPresetID
        self.curve = curve
        self.sensor = sensor
        self.customRPM = customRPM
    }

    public var canControl: Bool {
        control == .ready
    }

    public var selectedPreset: Preset? {
        presets.first { $0.id == selectedPresetID }
    }
}

public extension FanControlModel {
    var widgetState: WidgetFanState {
        let settings = settings
        return WidgetFanState(
            mode: mode,
            control: widgetControl,
            notice: widgetNotice,
            presets: settings.presets.map { WidgetFanState.Preset(id: $0.id, name: $0.name) },
            selectedPresetID: settings.selectedPresetID,
            curve: settings.selectedCurve.points,
            sensor: settings.sensor,
            customRPM: settings.customRPM
        )
    }

    private var widgetControl: WidgetFanState.Control {
        switch helperState {
        case .installed: canControl ? .ready : .off
        case .needsApproval: .needsApproval
        default: .notInstalled
        }
    }

    private var widgetNotice: WidgetFanState.Notice? {
        switch notice {
        case let .failsafeMax(celsius, _): .failsafeMax(celsius: celsius)
        case .returnedToAuto: .returnedToAuto
        case nil: nil
        }
    }
}

public extension FanControlModel {
    /// Does what a Fans widget button asks. Without control this is a no-op, so the widget cannot change anything.
    func perform(_ action: WidgetCommand.Action) {
        guard canControl else { return }
        switch action {
        case .toggleFanMax:
            toggleMax()
        case let .setFanMode(mode):
            select(mode)
        case let .selectFanPreset(id):
            if settings.presets.contains(where: { $0.id == id }) {
                updateSettings { $0.selectPreset(id) }
            }
        case let .setFanCustom(rpm):
            // The engine keeps the target inside each fan's limits.
            if rpm.isFinite, rpm > 0 {
                updateSettings {
                    $0.customRPM = rpm
                    $0.customPerFan = false
                }
                select(.custom)
            }
        default:
            break
        }
    }
}

/// Read and write speeds in bytes per second, oldest first.
public struct WidgetDiskHistory: Codable, Sendable, Equatable {
    public var read: [History<Double>.Point]
    public var write: [History<Double>.Point]

    public init(read: [History<Double>.Point] = [], write: [History<Double>.Point] = []) {
        self.read = read
        self.write = write
    }
}

/// The forecast with what the widget needs to say about its age.
public struct WidgetWeather: Codable, Sendable, Equatable {
    public var reports: [WeatherReport]
    public var isStale: Bool
    /// False only when no city is saved, as opposed to a forecast that has not arrived yet.
    public var hasPlaces: Bool

    public init(reports: [WeatherReport] = [], isStale: Bool = false, hasPlaces: Bool = true) {
        self.reports = reports
        self.isStale = isStale
        self.hasPlaces = hasPlaces
    }
}

/// Rates with what the widget needs to say about their age.
public struct WidgetRates: Codable, Sendable, Equatable {
    public var quotes: [RateQuote]
    public var updatedAt: Date?
    public var isStale: Bool

    public init(quotes: [RateQuote] = [], updatedAt: Date? = nil, isStale: Bool = false) {
        self.quotes = quotes
        self.updatedAt = updatedAt
        self.isStale = isStale
    }
}
