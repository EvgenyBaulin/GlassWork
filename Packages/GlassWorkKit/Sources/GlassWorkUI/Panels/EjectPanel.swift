import AppKit
import GlassWorkCore
import SwiftUI

struct EjectPanel: View {
    let monitor: SystemMonitor
    private let activity = EjectActivity.shared

    var body: some View {
        let volumes = monitor.ejectableVolumes
        PanelFrame(module: .eject, subtitle: loc("\(volumes.count) volumes")) {
            EjectList(
                volumes: volumes,
                asksFirst: monitor.ejectOptions.asksFirst,
                ejecting: activity.ejecting,
                failures: activity.failures,
                eject: eject
            )
        }
    }

    private func eject(_ volumes: [DiskVolume]) {
        activity.eject(volumes) {
            monitor.refresh(includingSlow: true)
            activity.forget(except: monitor.ejectableVolumes)
        }
    }
}

/// The volumes and Eject All. The question stays inside the panel, which a separate dialog would close.
struct EjectList: View {
    let volumes: [DiskVolume]
    let asksFirst: Bool
    /// Paths of volumes being ejected, and why the ones that would not go are still here.
    let ejecting: Set<String>
    let failures: [String: String]
    let eject: ([DiskVolume]) -> Void
    @State private var isConfirming: Bool

    init(
        volumes: [DiskVolume],
        asksFirst: Bool,
        startsConfirming: Bool = false,
        ejecting: Set<String> = [],
        failures: [String: String] = [:],
        eject: @escaping ([DiskVolume]) -> Void
    ) {
        self.volumes = volumes
        self.asksFirst = asksFirst
        self.ejecting = ejecting
        self.failures = failures
        self.eject = eject
        _isConfirming = State(initialValue: startsConfirming)
    }

    var body: some View {
        ForEach(volumes) { volume in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "externaldrive").foregroundStyle(.secondary)
                    Text(volume.name).font(.system(size: 13))
                    Spacer()
                    if ejecting.contains(volume.path) {
                        ProgressView().controlSize(.small)
                        Text(loc("Ejecting…")).font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        Button(loc("Eject")) { eject([volume]) }.controlSize(.small)
                    }
                }
                if let reason = failures[volume.path], !ejecting.contains(volume.path) {
                    Text(reason).font(.system(size: 11)).foregroundStyle(Palette.orange)
                }
            }
        }
        if volumes.isEmpty {
            Text(loc("Nothing to eject")).foregroundStyle(.secondary).font(.system(size: 12))
        }
        if volumes.count > 1 {
            Divider()
            if isConfirming {
                confirmation
            } else {
                Button(loc("Eject All"), action: ejectAllTapped).controlSize(.small)
            }
        }
    }

    private var confirmation: some View {
        HStack {
            Text(loc("Eject \(volumes.count) disks?")).font(.system(size: 12))
            Spacer()
            Button(loc("Cancel")) { isConfirming = false }.controlSize(.small)
            Button(loc("Eject")) { ejectAll() }.controlSize(.small)
        }
    }

    private func ejectAllTapped() {
        if asksFirst {
            isConfirming = true
        } else {
            ejectAll()
        }
    }

    private func ejectAll() {
        isConfirming = false
        eject(volumes)
    }
}
