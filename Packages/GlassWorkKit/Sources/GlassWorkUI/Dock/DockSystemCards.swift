import GlassWorkCore
import SwiftUI

/// Words and looks for the Sound and Mic & Camera tiles and the three cards, kept apart from the views.
enum DockSystemText {
    static func level(_ info: SoundInfo) -> String {
        switch info.level {
        case .muted: loc("Muted")
        case let .percent(value): "\(value)%"
        case .unknown: "—"
        }
    }

    static func caption(_ activity: CaptureStatus.Activity) -> String {
        switch activity {
        case .idle: loc("Idle")
        case .microphone: loc("Mic")
        case .camera: loc("Camera")
        case .both: loc("Mic + Cam")
        }
    }

    static func title(_ status: KeepAwakeCardState.Status) -> String {
        status == .off ? loc("Off") : loc("On")
    }

    static func detail(_ status: KeepAwakeCardState.Status, clock: (Date) -> String) -> String {
        switch status {
        case .off: loc("Pick a time to start")
        case .onUntilOff: loc("Until you turn it off")
        case let .until(end): loc("Until \(clock(end))")
        }
    }

    static func title(_ duration: KeepAwakeDuration) -> String {
        switch duration {
        case .quarterHour: loc("15 min")
        case .hour: loc("1 hour")
        case .untilOff: loc("Until off")
        }
    }
}

/// What a Sound or Mic & Camera tile shows: it changes with the state, so a camera in use stands out.
struct DockSystemTileLook {
    var symbol: String
    var tint: Color
    var caption: String

    @MainActor
    static func of(_ module: ModuleID, monitor: SystemMonitor) -> DockSystemTileLook? {
        let reading = monitor.media.reading
        switch module {
        case .sound:
            guard let sound = reading?.sound else {
                return DockSystemTileLook(symbol: module.symbol, tint: module.tint, caption: "—")
            }
            let silent = sound.level == .muted
            return DockSystemTileLook(
                symbol: silent ? "speaker.slash.fill" : module.symbol,
                tint: module.tint,
                caption: DockSystemText.level(sound)
            )
        case .micCamera:
            let activity = reading?.capture.activity ?? .idle
            let symbol = switch activity {
            case .idle, .microphone: "mic.fill"
            case .camera, .both: "video.fill"
            }
            return DockSystemTileLook(
                symbol: symbol,
                tint: activity == .idle ? module.tint : Palette.orange,
                caption: DockSystemText.caption(activity)
            )
        default:
            return nil
        }
    }
}

/// The head of a Dock card: the module's icon and its name.
private struct DockCardHeader: View {
    let module: ModuleID

    var body: some View {
        HStack(spacing: 8) {
            ModuleIcon(module, size: 24)
            Text(module.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(module.tint)
            Spacer()
        }
    }
}

// MARK: Keep Awake

/// The Keep Awake card of the Dock: the switch, quick durations, and what else keeps the Mac awake.
struct DockKeepAwakeCard: View {
    let monitor: SystemMonitor
    @State private var blockers: [SleepBlocker] = []
    @State private var stoppable: Set<Int32> = []

    var body: some View {
        let everyday = monitor.everyday
        DockKeepAwakeCardContent(
            state: KeepAwakeCardState(
                isOn: everyday.isKeepingAwake,
                ends: everyday.keepAwakeEnds,
                keepsDisplayOn: !everyday.letsDisplaySleep,
                blockers: blockers,
                stoppable: stoppable
            ),
            onSelect: { everyday.startKeepAwake(minutes: $0.minutes) },
            onSwitch: { isOn in
                if isOn != everyday.isKeepingAwake {
                    everyday.toggleKeepAwake()
                }
            },
            onStop: { pid in
                CaffeinateStopper.stop(pid)
                blockers.removeAll { $0.pid == pid }
            }
        )
        // Nothing tells when another program takes or lets go of the Mac, so it is read while the card is open.
        .task {
            while !Task.isCancelled {
                let read = SleepBlockers.read()
                blockers = read
                stoppable = KeepAwakeCardState.stoppable(among: read)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

struct DockKeepAwakeCardContent: View {
    let state: KeepAwakeCardState
    var locale = Locale.current
    var timeZone = TimeZone.current
    var onSelect: (KeepAwakeDuration) -> Void = { _ in }
    var onSwitch: (Bool) -> Void = { _ in }
    var onStop: (Int32) -> Void = { _ in }

    static let width = 340.0
    private static let visibleOthers = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DockCardHeader(module: .keepAwake)
            status
            durations
            Divider()
            others
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
    }

    private func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }

    private var status: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DockSystemText.title(state.status))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(DockSystemText.detail(state.status, clock: clock))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let keepsDisplayOn = state.keepsDisplayOn {
                    Text(keepsDisplayOn ? loc("The display stays on too") : loc("The display can sleep"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle(loc("Keep Awake"), isOn: Binding(get: { state.isOn }, set: onSwitch))
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var durations: some View {
        HStack(spacing: 8) {
            ForEach(KeepAwakeDuration.allCases, id: \.self) { duration in
                Button { onSelect(duration) } label: {
                    Text(DockSystemText.title(duration))
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(.quaternary, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var others: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc("Also keeping this Mac awake"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            if state.others.isEmpty {
                Text(loc("Nothing else is keeping this Mac awake."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.others.prefix(Self.visibleOthers)) { other in
                    row(other)
                }
                if state.others.count > Self.visibleOthers {
                    Text(loc("and \(state.others.count - Self.visibleOthers) more"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ other: KeepAwakeCardState.Other) -> some View {
        HStack(spacing: 8) {
            Image(systemName: other.keepsDisplayOn ? "display" : "moon.zzz")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(other.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if !other.reason.isEmpty {
                    Text(other.reason).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if other.canStop {
                Button(loc("Stop")) { onStop(other.pid) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.red)
            }
        }
    }
}

// MARK: Sound

/// The Sound card of the Dock: the output, its volume and the input. Read only.
struct DockSoundCard: View {
    let monitor: SystemMonitor

    var body: some View {
        DockSoundCardContent(info: monitor.media.reading?.sound)
            .onAppear { monitor.media.retain() }
            .onDisappear { monitor.media.release() }
    }
}

struct DockSoundCardContent: View {
    let info: SoundInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DockCardHeader(module: .sound)
            if let info {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(DockSystemText.level(info))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Spacer()
                        Image(systemName: info.level == .muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(.secondary)
                    }
                    if case let .percent(value) = info.level {
                        ThinBar(value: Double(value) / 100, tint: ModuleID.sound.tint)
                    }
                }
                Divider()
                InfoRow(title: loc("Output"), value: info.outputName ?? "—")
                InfoRow(title: loc("Input"), value: info.inputName ?? "—")
            } else {
                Text(loc("Reading…")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: DockKeepAwakeCardContent.width, alignment: .leading)
    }
}

// MARK: Mic & Camera

/// The Mic & Camera card of the Dock: whether either is running now. macOS does not say which app uses it.
struct DockMicCameraCard: View {
    let monitor: SystemMonitor

    var body: some View {
        DockMicCameraCardContent(status: monitor.media.reading?.capture)
            .onAppear { monitor.media.retain() }
            .onDisappear { monitor.media.release() }
    }
}

struct DockMicCameraCardContent: View {
    let status: CaptureStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DockCardHeader(module: .micCamera)
            if let status {
                device(symbol: "mic.fill", title: loc("Microphone"), names: status.microphones)
                device(symbol: "video.fill", title: loc("Camera"), names: status.cameras)
                Text(loc("macOS does not say which app is using them."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text(loc("Reading…")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: DockKeepAwakeCardContent.width, alignment: .leading)
    }

    private func device(symbol: String, title: String, names: [String]) -> some View {
        let isInUse = !names.isEmpty
        let detail = names.filter { !$0.isEmpty }.joined(separator: ", ")
        return HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(isInUse ? Palette.orange : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(isInUse ? Palette.orange : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                Text(isInUse ? loc("In use") : loc("Not in use"))
                    .font(.system(size: 12))
                    .foregroundStyle(isInUse ? Color.primary : Color.secondary)
            }
        }
    }
}
