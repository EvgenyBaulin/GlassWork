import Foundation
import Network

/// Calls back on the main actor when the set of network interfaces changes: Wi-Fi joins or drops, a VPN tunnel
/// comes up or goes away. The first report, which only describes the network as it is, is skipped.
@MainActor
final class NetworkPathWatcher {
    private let monitor = NWPathMonitor()
    private let onChange: @MainActor () -> Void
    private var isFirst = true

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.report() }
        }
        monitor.start(queue: DispatchQueue(label: "GlassWork.network-path"))
    }

    deinit {
        monitor.cancel()
    }

    private func report() {
        if isFirst {
            isFirst = false
        } else {
            onChange()
        }
    }
}
