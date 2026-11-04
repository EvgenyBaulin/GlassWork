import Foundation

public extension WidgetKind {
    /// The Screen Time log feeds all of these.
    static let screenTimeKinds: Set<WidgetKind> = [
        .screenTime, .screenTimeWeek, .categories, .breaks, .appTime, .mostUsed, .focusTime,
    ]

    /// Filled by the `gh` tool, which is worth running only for these.
    static let githubKinds: Set<WidgetKind> = [.github, .githubReviews, .githubActions, .contributions]

    /// Only in the system gallery: GlassWork's own desktop windows do not get new widgets.
    static let systemOnlyKinds: Set<WidgetKind> = [.github, .todayAtAGlance, .photoFrame, .onThisDay, .birthdays]

    /// What GlassWork's own desktop windows offer. Macs without fans never see the Fans widget.
    static var gallery: [WidgetKind] {
        allCases.filter { ($0 != .fans || FanHardware.hasFans) && !systemOnlyKinds.contains($0) }
    }

    /// The developer module that collects this widget's data.
    var developerModule: ModuleID? {
        switch self {
        case .git: .git
        case .devServers: .devServers
        case .containers: .docker
        case .aiUsage: .aiUsage
        case .wifiSignal: .wifi
        default: nil
        }
    }

    /// Charts need steady readings, so these keep sampling even when only a system widget shows them.
    var keepsHistory: Bool {
        self == .fans || self == .diskActivity
    }
}

public extension MonitorDemand {
    /// What a set of widgets reads. A kind not listed here needs nothing from the monitor.
    init(widgets kinds: Set<WidgetKind>) {
        self.init()
        cpu = !kinds.isDisjoint(with: [.activity])
        memory = !kinds.isDisjoint(with: [.activity, .macHealth, .uptime])
        gpu = kinds.contains(.activity)
        network = kinds.contains(.network)
        disk = !kinds.isDisjoint(with: [.storage, .diskActivity])
        battery = !kinds.isDisjoint(with: [.battery, .todayAtAGlance])
        sensors = !kinds.isDisjoint(with: [.temperature, .fans])
        slowProcesses = !kinds.isDisjoint(with: [.activity, .topApps])
        developer = Set(kinds.compactMap(\.developerModule))
        devices = kinds.contains(.devices)
        timeMachine = kinds.contains(.timeMachine)
    }

    /// What this asks for that `other` does not read already.
    func subtracting(_ other: MonitorDemand) -> MonitorDemand {
        var rest = MonitorDemand()
        rest.cpu = cpu && !other.cpu
        rest.memory = memory && !other.memory
        rest.network = network && !other.network
        rest.disk = disk && !other.disk
        rest.battery = battery && !other.battery
        rest.gpu = gpu && !other.gpu
        rest.sensors = sensors && !other.sensors
        rest.slowProcesses = slowProcesses && !other.slowProcesses && !other.processes
        return rest
    }

    /// True when `SystemMonitor` has something to sample. Developer modules, devices and backups read at their own
    /// pace.
    var readsSamples: Bool {
        cpu || memory || network || disk || battery || gpu || sensors || processes || slowProcesses
    }
}
