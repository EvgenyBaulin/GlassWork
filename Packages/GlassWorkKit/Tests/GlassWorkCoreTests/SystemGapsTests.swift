import Foundation
@testable import GlassWorkCore
import Testing

struct SystemGapsTests {
    @Test func noInterfaceMeansOffline() {
        let counters = [InterfaceCounters(name: "en0", received: 100, sent: 10)]
        #expect(NetworkSample.between(counters, [], seconds: 2).isOffline)
        #expect(!NetworkSample.between(counters, counters, seconds: 2).isOffline)
    }

    @Test func tunnelsAloneAreOffline() {
        let tunnel = [InterfaceCounters(name: "utun3", received: 100, sent: 10)]
        #expect(NetworkSample.between(tunnel, tunnel, seconds: 2).isOffline)
    }
}
