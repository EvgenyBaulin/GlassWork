import Foundation

public enum FanMode: String, Codable, CaseIterable, Sendable {
    case auto, curve, max, custom
}

/// A temperature source, stored as one string so settings.json stays readable.
public enum SensorChoice: Sendable, Hashable {
    case averageCPU, hottestCPU, averageGPU, averageSoC
    case sensor(String)

    private static let sensorPrefix = "sensor:"
}

extension SensorChoice: RawRepresentable, Codable {
    public init?(rawValue: String) {
        switch rawValue {
        case "avgCPU": self = .averageCPU
        case "maxCPU": self = .hottestCPU
        case "avgGPU": self = .averageGPU
        case "avgSoC": self = .averageSoC
        default:
            guard rawValue.hasPrefix(Self.sensorPrefix), rawValue.count > Self.sensorPrefix.count else { return nil }
            self = .sensor(String(rawValue.dropFirst(Self.sensorPrefix.count)))
        }
    }

    public var rawValue: String {
        switch self {
        case .averageCPU: "avgCPU"
        case .hottestCPU: "maxCPU"
        case .averageGPU: "avgGPU"
        case .averageSoC: "avgSoC"
        case let .sensor(key): Self.sensorPrefix + key
        }
    }
}

public extension SensorChoice {
    /// True when `celsius(for:)` needs this key to answer for this choice.
    func covers(_ key: String) -> Bool {
        let group = SensorGroup(key: key)
        return switch self {
        case .averageCPU, .hottestCPU: group == .cpuPerformance || group == .cpuEfficiency
        case .averageGPU: group == .gpu
        case .averageSoC: group == .soc
        case let .sensor(chosen): key == chosen
        }
    }
}

public extension SensorSample {
    func celsius(for choice: SensorChoice) -> Double? {
        switch choice {
        case .averageCPU: averageCPU
        case .hottestCPU: readings
            .filter { $0.group == .cpuPerformance || $0.group == .cpuEfficiency }
            .map(\.celsius)
            .max()
        case .averageGPU: averageGPU
        case .averageSoC: averageSoC
        case let .sensor(key): readings.first { $0.key == key }?.celsius
        }
    }
}

/// A different curve on the power adapter and on battery.
public struct FanPowerRules: Sendable, Equatable {
    public var isEnabled = false
    public var adapterPresetID = FanPreset.balanced.id
    public var batteryPresetID = FanPreset.silent.id

    public init() {}
}

/// Saved fan choices.
///
/// Nothing here is optional or a dictionary on purpose: saving overlays the new JSON on the old file,
/// so a key that disappears from the encoded value would keep its old content.
public struct FanSettings: Sendable, Equatable {
    /// What to do after launch. The running mode is never saved, so nothing resumes by itself.
    public var launchMode = FanMode.auto
    public var isControlEnabled = false
    public var sensor = SensorChoice.averageCPU
    public var selectedPresetID = FanPreset.balanced.id
    /// Unsaved edit of the selected built-in preset. Empty when there is none.
    public var draftPoints: [FanCurve.Point] = []
    public var userPresets: [FanPreset] = []
    public var separateCurves = false
    /// One preset per fan, by fan index, used with `separateCurves`.
    public var fanPresetIDs: [String] = []
    public var customPerFan = false
    public var customRPM = 0.0
    /// One target per fan, by fan index, used with `customPerFan`.
    public var customRPMs: [Double] = []
    public var powerRules = FanPowerRules()
    /// In Curve mode, leaves the fans to the system below `handOverCelsius` instead of holding the minimum.
    public var handsOverWhenCool = false
    public var handOverCelsius = 45.0

    /// Stops well short of the failsafe, because the system would be running the fans in that range.
    public static let handOverRange = 30.0 ... 80.0

    public init() {}

    /// Nil when the option is off. A hand edit cannot put the threshold anywhere odd.
    public var handOverThreshold: Double? {
        guard handsOverWhenCool else { return nil }
        guard handOverCelsius.isFinite else { return 45 }
        return Swift.min(Swift.max(handOverCelsius, Self.handOverRange.lowerBound), Self.handOverRange.upperBound)
    }

    public var presets: [FanPreset] {
        FanPreset.builtIn + userPresets
    }

    public func preset(_ id: String) -> FanPreset {
        presets.first { $0.id == id } ?? .balanced
    }

    public var selectedPreset: FanPreset {
        preset(selectedPresetID)
    }

    public var hasDraft: Bool {
        !draftPoints.isEmpty
    }

    /// The curve being edited: the draft when there is one, otherwise the selected preset.
    public var selectedCurve: FanCurve {
        hasDraft ? FanCurve(points: draftPoints) : selectedPreset.curve
    }

    /// Power rules win over separate curves, which win over the selected curve.
    public func curve(forFan index: Int, isOnAC: Bool) -> FanCurve {
        if powerRules.isEnabled {
            return preset(isOnAC ? powerRules.adapterPresetID : powerRules.batteryPresetID).curve
        }
        if separateCurves, fanPresetIDs.indices.contains(index), fanPresetIDs[index] != selectedPresetID {
            return preset(fanPresetIDs[index]).curve
        }
        return selectedCurve
    }

    public func customTarget(forFan index: Int) -> Double {
        customPerFan && customRPMs.indices.contains(index) ? customRPMs[index] : customRPM
    }

    /// Removes a user preset, moving everything that used it to Balanced.
    public mutating func deletePreset(_ id: String) {
        guard !preset(id).isBuiltIn else { return }
        userPresets.removeAll { $0.id == id }
        let fallback = FanPreset.balanced.id
        if selectedPresetID == id {
            selectedPresetID = fallback
            draftPoints = []
        }
        fanPresetIDs = fanPresetIDs.map { $0 == id ? fallback : $0 }
        if powerRules.adapterPresetID == id {
            powerRules.adapterPresetID = fallback
        }
        if powerRules.batteryPresetID == id {
            powerRules.batteryPresetID = fallback
        }
    }

    /// Built-in presets keep their names.
    public mutating func renamePreset(_ id: String, to name: String) {
        guard let index = userPresets.firstIndex(where: { $0.id == id }) else { return }
        userPresets[index].name = name
    }

    /// Applies an edit: a user preset changes in place, a built-in one keeps a draft.
    public mutating func applyEdit(_ curve: FanCurve) {
        if let index = userPresets.firstIndex(where: { $0.id == selectedPresetID }) {
            userPresets[index].curve = curve
        } else {
            draftPoints = curve == selectedPreset.curve ? [] : curve.points
        }
    }

    /// Keeps the current curve as a new preset and selects it.
    public mutating func saveCurve(as name: String, id: String = UUID().uuidString) {
        userPresets.append(FanPreset(id: id, name: name, curve: selectedCurve))
        selectedPresetID = id
        draftPoints = []
    }

    public mutating func selectPreset(_ id: String) {
        selectedPresetID = preset(id).id
        draftPoints = []
    }
}

private extension KeyedDecodingContainer {
    /// One bad hand edit falls back to the default instead of losing the whole file.
    func lossy<Value: Decodable>(_ key: Key, _ fallback: Value) -> Value {
        (try? decodeIfPresent(Value.self, forKey: key)) ?? fallback
    }
}

extension FanPowerRules: Codable {
    private enum CodingKeys: String, CodingKey {
        case isEnabled, adapterPresetID, batteryPresetID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = container.lossy(.isEnabled, false)
        adapterPresetID = container.lossy(.adapterPresetID, FanPreset.balanced.id)
        batteryPresetID = container.lossy(.batteryPresetID, FanPreset.silent.id)
    }
}

extension FanSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case launchMode, isControlEnabled, sensor, selectedPresetID, draftPoints, userPresets
        case separateCurves, fanPresetIDs, customPerFan, customRPM, customRPMs, powerRules
        case handsOverWhenCool, handOverCelsius
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchMode = container.lossy(.launchMode, .auto)
        isControlEnabled = container.lossy(.isControlEnabled, false)
        sensor = container.lossy(.sensor, .averageCPU)
        selectedPresetID = container.lossy(.selectedPresetID, FanPreset.balanced.id)
        draftPoints = container.lossy(.draftPoints, [])
        userPresets = container.lossy(.userPresets, [])
        separateCurves = container.lossy(.separateCurves, false)
        fanPresetIDs = container.lossy(.fanPresetIDs, [])
        customPerFan = container.lossy(.customPerFan, false)
        customRPM = container.lossy(.customRPM, 0)
        customRPMs = container.lossy(.customRPMs, [])
        powerRules = container.lossy(.powerRules, FanPowerRules())
        handsOverWhenCool = container.lossy(.handsOverWhenCool, false)
        handOverCelsius = container.lossy(.handOverCelsius, 45)
    }
}
