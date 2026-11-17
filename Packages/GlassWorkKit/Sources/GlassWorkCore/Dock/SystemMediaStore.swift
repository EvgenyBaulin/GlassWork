import Foundation
import Observation

/// Where the Sound and Mic & Camera cards get their facts. The real one listens to Core Audio and CoreMediaIO;
/// tests give it fixed readings.
@MainActor
public protocol SystemMediaBackend: AnyObject {
    func read() -> SystemMediaReading
    /// Calls `onChange` whenever something that `read()` reports may have changed. No polling.
    func startListening(_ onChange: @escaping @MainActor () -> Void)
    func stopListening()
}

/// The live reading behind the Sound and Mic & Camera tiles and cards.
///
/// It listens only while something that shows it is on screen: each tile or card calls `retain()` when it appears
/// and `release()` when it goes. With no one holding it, no listener is registered and nothing is read.
@MainActor
@Observable
public final class SystemMediaStore {
    public private(set) var reading: SystemMediaReading?

    @ObservationIgnored private let backend: any SystemMediaBackend
    @ObservationIgnored private var holders = 0

    public init(backend: any SystemMediaBackend = CoreMediaBackend()) {
        self.backend = backend
    }

    public var isListening: Bool {
        holders > 0
    }

    public func retain() {
        holders += 1
        guard holders == 1 else { return }
        reading = backend.read()
        backend.startListening { [weak self] in self?.refresh() }
    }

    public func release() {
        guard holders > 0 else { return }
        holders -= 1
        guard holders == 0 else { return }
        backend.stopListening()
        reading = nil
    }

    private func refresh() {
        guard holders > 0 else { return }
        let current = backend.read()
        if current != reading {
            reading = current
        }
    }
}
