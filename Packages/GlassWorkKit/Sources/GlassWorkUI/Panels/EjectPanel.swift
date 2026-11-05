import AppKit
import GlassWorkCore
import SwiftUI

struct EjectPanel: View {
    let monitor: SystemMonitor

    var body: some View {
        let volumes = monitor.ejectableVolumes
        PanelFrame(module: .eject, subtitle: loc("\(volumes.count) volumes")) {
            EjectList(volumes: volumes, asksFirst: monitor.ejectOptions.asksFirst, eject: eject)
        }
    }

    private func eject(_ volumes: [DiskVolume]) {
        for volume in volumes {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: URL(filePath: volume.path))
        }
        monitor.refresh(includingSlow: true)
    }
}

/// The volumes and Eject All. The question stays inside the panel, which a separate dialog would close.
struct EjectList: View {
    let volumes: [DiskVolume]
    let asksFirst: Bool
    let eject: ([DiskVolume]) -> Void
    @State private var isConfirming: Bool

    init(
        volumes: [DiskVolume],
        asksFirst: Bool,
        startsConfirming: Bool = false,
        eject: @escaping ([DiskVolume]) -> Void
    ) {
        self.volumes = volumes
        self.asksFirst = asksFirst
        self.eject = eject
        _isConfirming = State(initialValue: startsConfirming)
    }

    var body: some View {
        ForEach(volumes) { volume in
            HStack {
                Image(systemName: "externaldrive").foregroundStyle(.secondary)
                Text(volume.name).font(.system(size: 13))
                Spacer()
                Button(loc("Eject")) { eject([volume]) }.controlSize(.small)
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
