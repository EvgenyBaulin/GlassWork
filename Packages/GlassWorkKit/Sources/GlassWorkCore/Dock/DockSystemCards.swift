import Foundation

/// How long a click on a Keep Awake card keeps the Mac awake.
public enum KeepAwakeDuration: CaseIterable, Sendable, Equatable {
    case quarterHour, hour, untilOff

    /// Nil keeps it on until it is turned off.
    public var minutes: Int? {
        switch self {
        case .quarterHour: 15
        case .hour: 60
        case .untilOff: nil
        }
    }
}

/// What the Keep Awake card of the Dock shows: GlassWork's own switch, and what else holds the Mac awake.
public struct KeepAwakeCardState: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case off
        case onUntilOff
        case until(Date)
    }

    /// A program other than GlassWork that keeps the Mac, or its display, from sleeping.
    public struct Other: Sendable, Equatable, Identifiable {
        public var id: Int
        public var pid: Int32
        public var name: String
        public var reason: String
        public var keepsDisplayOn: Bool
        /// Only a `caffeinate` of this user can be stopped from here.
        public var canStop: Bool
    }

    public var status: Status
    /// Whether GlassWork's own Keep Awake keeps the display on too. Nil while it is off.
    public var keepsDisplayOn: Bool?
    public var others: [Other]

    public var isOn: Bool {
        status != .off
    }

    /// - Parameter stoppable: The pids of `caffeinate` programs of this user.
    public init(
        isOn: Bool,
        ends: Date?,
        keepsDisplayOn: Bool,
        blockers: [SleepBlocker],
        stoppable: Set<Int32> = [],
        at date: Date = Date()
    ) {
        if !isOn {
            status = .off
        } else if let ends, ends > date {
            status = .until(ends)
        } else {
            status = .onUntilOff
        }
        self.keepsDisplayOn = isOn ? keepsDisplayOn : nil
        others = blockers.map {
            Other(
                id: $0.id,
                pid: $0.pid,
                name: $0.process,
                reason: $0.reason,
                keepsDisplayOn: $0.kind == .display,
                canStop: $0.isCaffeinate && stoppable.contains($0.pid)
            )
        }
    }

    /// The pids that can be stopped, out of the blockers: a `caffeinate` that belongs to this user.
    public static func stoppable(
        among blockers: [SleepBlocker],
        facts: (Int32) -> CaffeinateStopper.ProcessFacts? = CaffeinateStopper.facts(of:)
    ) -> Set<Int32> {
        Set(blockers.filter { CaffeinateStopper.canStop(facts($0.pid)) }.map(\.pid))
    }
}

/// The sound the Mac plays and records with now.
public struct SoundInfo: Sendable, Equatable {
    public var outputName: String?
    /// From 0 to 1; nil when the output has no volume of its own, as a digital output.
    public var volume: Double?
    public var isMuted: Bool
    public var inputName: String?

    public init(outputName: String? = nil, volume: Double? = nil, isMuted: Bool = false, inputName: String? = nil) {
        self.outputName = outputName
        self.volume = volume
        self.isMuted = isMuted
        self.inputName = inputName
    }

    public enum Level: Sendable, Equatable {
        case muted
        case percent(Int)
        case unknown
    }

    public var level: Level {
        if isMuted || volume == 0 {
            return .muted
        }
        return volume.map { .percent(Int(($0 * 100).rounded())) } ?? .unknown
    }
}

/// Whether a microphone or a camera is running now, and which device it is. macOS does not say which app uses it.
public struct CaptureStatus: Sendable, Equatable {
    /// The names of the microphones that are running.
    public var microphones: [String]
    public var cameras: [String]

    public init(microphones: [String] = [], cameras: [String] = []) {
        self.microphones = microphones
        self.cameras = cameras
    }

    public var isMicrophoneInUse: Bool {
        !microphones.isEmpty
    }

    public var isCameraInUse: Bool {
        !cameras.isEmpty
    }

    public enum Activity: Sendable, Equatable {
        case idle, microphone, camera, both
    }

    public var activity: Activity {
        switch (isMicrophoneInUse, isCameraInUse) {
        case (false, false): .idle
        case (true, false): .microphone
        case (false, true): .camera
        case (true, true): .both
        }
    }
}

/// Everything the Sound and Mic & Camera cards read in one go.
public struct SystemMediaReading: Sendable, Equatable {
    public var sound: SoundInfo
    public var capture: CaptureStatus

    public init(sound: SoundInfo = SoundInfo(), capture: CaptureStatus = CaptureStatus()) {
        self.sound = sound
        self.capture = capture
    }
}
