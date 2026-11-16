import Foundation

/// Whether a Focus mode is on, with the mode's name and SF Symbol when the system files say.
public struct FocusReading: Sendable, Equatable {
    public var isOn: Bool
    public var modeID: String?
    public var name: String?
    public var symbol: String?

    public init(isOn: Bool, modeID: String? = nil, name: String? = nil, symbol: String? = nil) {
        self.isOn = isOn
        self.modeID = modeID
        self.name = name
        self.symbol = symbol
    }
}

/// Reads the Focus state from the files the system keeps in `~/Library/DoNotDisturb/DB`.
/// Without Full Disk Access the files cannot be opened; the reading is then nil, never "off".
public enum FocusFiles {
    public static let assertionsName = "Assertions.json"
    public static let configurationsName = "ModeConfigurations.json"

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(
            path: "Library/DoNotDisturb/DB",
            directoryHint: .isDirectory
        )
    }

    /// The current state, or nil when the assertions file is missing, unreadable or not understood.
    /// A missing or unreadable configurations file only leaves the name and symbol empty.
    public static func read(in directory: URL = defaultDirectory) -> FocusReading? {
        guard let assertions = try? Data(contentsOf: directory.appending(path: assertionsName)) else { return nil }
        let configurations = try? Data(contentsOf: directory.appending(path: configurationsName))
        return parse(assertions: assertions, configurations: configurations)
    }

    public static func modificationDate(in directory: URL = defaultDirectory) -> Date? {
        let path = directory.appending(path: assertionsName).path(percentEncoded: false)
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    public static func parse(assertions: Data, configurations: Data?) -> FocusReading? {
        guard let store = try? JSONDecoder().decode(FocusAssertionsFile.self, from: assertions).data.first else {
            return nil
        }
        // With several modes on, the one switched on last is the one the system shows.
        let active = (store.storeAssertionRecords ?? []).max {
            ($0.assertionStartDateTimestamp ?? 0) < ($1.assertionStartDateTimestamp ?? 0)
        }
        guard let active else { return FocusReading(isOn: false) }
        let modeID = active.assertionDetails?.assertionDetailsModeIdentifier
        let mode = modeID.flatMap { id in
            configurations.flatMap { try? JSONDecoder().decode(FocusConfigurationsFile.self, from: $0) }?
                .data.first?.modeConfigurations[id]?.mode
        }
        return FocusReading(isOn: true, modeID: modeID, name: mode?.name, symbol: mode?.symbolImageName)
    }
}

private struct FocusAssertionsFile: Decodable {
    var data: [Store]

    struct Store: Decodable {
        var storeAssertionRecords: [Record]?
    }

    struct Record: Decodable {
        var assertionStartDateTimestamp: Double?
        var assertionDetails: Details?
    }

    struct Details: Decodable {
        var assertionDetailsModeIdentifier: String?
    }
}

private struct FocusConfigurationsFile: Decodable {
    var data: [Store]

    struct Store: Decodable {
        var modeConfigurations: [String: Configuration]
    }

    struct Configuration: Decodable {
        var mode: Mode?
    }

    struct Mode: Decodable {
        var name: String?
        var symbolImageName: String?
    }
}
