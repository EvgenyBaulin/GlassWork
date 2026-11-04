import Foundation
import notify

/// Something a widget asks the app to do. The extension is sandboxed, so it can only pass this along.
public struct WidgetCommand: Codable, Sendable, Equatable, Identifiable {
    public enum Action: Codable, Sendable, Equatable, Hashable {
        case toggleFanMax
        case setFanMode(FanMode)
        case selectFanPreset(String)
        case setFanCustom(rpm: Double)
        case setTodo(id: String, completed: Bool)
        case startTimer(seconds: Double)
        case toggleTimer(UUID)
        case eject(path: String)
        case runCommand(UUID)
    }

    public var id: UUID
    public var issuedAt: Date
    public var action: Action

    public init(id: UUID = UUID(), issuedAt: Date = Date(), action: Action) {
        self.id = id
        self.issuedAt = issuedAt
        self.action = action
    }
}

public extension WidgetCommand.Action {
    /// As one string, the form an App Intent parameter can carry.
    var encoded: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    init?(encoded text: String) {
        guard let value = try? JSONDecoder().decode(Self.self, from: Data(text.utf8)) else { return nil }
        self = value
    }

    var isFanAction: Bool {
        switch self {
        case .toggleFanMax, .setFanMode, .selectFanPreset, .setFanCustom: true
        default: false
        }
    }

    /// The widgets that show the outcome and should redraw at once.
    var affectedKinds: [WidgetKind] {
        switch self {
        case .toggleFanMax, .setFanMode, .selectFanPreset, .setFanCustom: [.fans]
        case .setTodo: [.todo]
        case .startTimer, .toggleTimer: [.timer]
        case .eject: [.storage]
        case .runCommand: [.commands]
        }
    }
}

/// Commands waiting in the shared container, one file each.
public struct WidgetCommandInbox: Sendable {
    /// Older commands are dropped. A Max tapped while the app was closed must not start the fans on the next launch.
    public static let maxAge: TimeInterval = 10

    public let directory: URL

    public init(directory: URL = AppGroup.containerURL.appending(path: "Commands", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    public func send(_ command: WidgetCommand) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let file = directory.appending(path: "\(command.id.uuidString).json", directoryHint: .notDirectory)
        try encoder.encode(command).write(to: file, options: .atomic)
    }

    /// Empties the inbox and returns what is still fresh, oldest first.
    public func drain(at date: Date = Date()) -> [WidgetCommand] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let commands = files.compactMap { file -> WidgetCommand? in
            defer { try? FileManager.default.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? decoder.decode(WidgetCommand.self, from: data)
        }
        return commands
            .filter { abs(date.timeIntervalSince($0.issuedAt)) <= Self.maxAge }
            .sorted { $0.issuedAt < $1.issuedAt }
    }
}

/// The Darwin notification that says the inbox has something. It carries nothing itself.
public enum WidgetCommandSignal {
    public static var name: String {
        "\(AppGroup.identifier ?? "io.github.evgenybaulin.glasswork").widget-command"
    }

    public static func post() {
        notify_post(name)
    }

    /// Calls `handler` on the main queue for as long as the app runs.
    public static func observe(_ handler: @escaping @Sendable () -> Void) {
        var token: Int32 = 0
        notify_register_dispatch(name, &token, .main) { _ in handler() }
    }
}
