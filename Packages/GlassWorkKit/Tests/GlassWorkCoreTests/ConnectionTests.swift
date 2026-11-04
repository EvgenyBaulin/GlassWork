import Foundation
@testable import GlassWorkCore
import Testing

struct TunnelClassifierTests {
    /// `ifconfig` on a Mac with no VPN: macOS keeps these up for its own services.
    private let idle = [
        InterfaceAddress(interface: "lo0", address: "127.0.0.1", isUp: true),
        InterfaceAddress(interface: "en0", address: "192.168.1.20", isUp: true),
        InterfaceAddress(interface: "utun0", address: "fe80::2415:7bd5:6f21:d3b0%utun0", isUp: true),
        InterfaceAddress(interface: "utun1", address: "fe80::9ac2:4f1e:5b0d:17aa%utun1", isUp: true),
    ]

    @Test func systemTunnelsAreNotAVPN() {
        #expect(TunnelClassifier.tunnels(idle).isEmpty)
    }

    @Test func aTunnelWithAnIPv4AddressIsAVPN() {
        let tunnels = TunnelClassifier.tunnels(idle + [
            InterfaceAddress(interface: "utun4", address: "fe80::1%utun4", isUp: true),
            InterfaceAddress(interface: "utun4", address: "10.8.0.6", isUp: true),
        ])

        #expect(tunnels == [TunnelInterface(name: "utun4", address: "10.8.0.6")])
    }

    @Test func aGlobalIPv6AddressCounts() {
        let address = InterfaceAddress(interface: "utun5", address: "2001:db8::5", isUp: true)
        #expect(TunnelClassifier.tunnels([address]).count == 1)
    }

    @Test func localOnlyAddressesDoNotCount() {
        let addresses = [
            InterfaceAddress(interface: "utun5", address: "fd74:1::5", isUp: true),
            InterfaceAddress(interface: "utun6", address: "169.254.10.2", isUp: true),
        ]
        #expect(TunnelClassifier.tunnels(addresses).isEmpty)
    }

    @Test func aDownInterfaceDoesNotCount() {
        let address = InterfaceAddress(interface: "utun13", address: "10.8.0.6", isUp: false)
        #expect(TunnelClassifier.tunnels([address]).isEmpty)
    }

    @Test func eachTunnelIsListedOnce() {
        let addresses = [
            InterfaceAddress(interface: "ipsec0", address: "10.8.0.6", isUp: true),
            InterfaceAddress(interface: "ipsec0", address: "2001:db8::5", isUp: true),
        ]
        #expect(TunnelClassifier.tunnels(addresses).count == 1)
    }
}

struct VPNReadingTests {
    private let work = VPNService(id: "1", name: "Work", kind: "VPN", status: .connected)
    private let personal = VPNService(id: "2", name: "Personal", kind: "IPSec", status: .disconnected)

    @Test func aConnectedServiceIsEnough() {
        let reading = VPNReading(services: [work, personal], tunnels: [])

        #expect(reading.isConnected)
        #expect(reading.connectedService == work)
        #expect(reading.otherServices == [personal])
    }

    @Test func aTunnelFromAnAppSettingsDoesNotKnowIsEnough() {
        let reading = VPNReading(services: [], tunnels: [TunnelInterface(name: "utun4", address: "10.8.0.6")])
        #expect(reading.isConnected)
    }

    @Test func nothingConfigured() {
        let reading = VPNReading(services: [], tunnels: [])

        #expect(!reading.isConnected)
        #expect(!reading.isConfigured)
    }

    @Test func connecting() {
        let reading = VPNReading(
            services: [VPNService(id: "1", name: "Work", kind: "VPN", status: .connecting)],
            tunnels: []
        )

        #expect(reading.isConnecting)
        #expect(!reading.isConnected)
    }

    @Test func pppoeIsNotAVPN() {
        #expect(VPNKind.name(interfaceType: "PPP", underlyingType: "Ethernet") == nil)
        #expect(VPNKind.name(interfaceType: "PPP", underlyingType: "L2TP") == "L2TP")
        #expect(VPNKind.name(interfaceType: "Ethernet", underlyingType: nil) == nil)
    }
}

struct WiFiTests {
    /// Values CoreWLAN reported on a real connection.
    private func link(rssi: Int = -70) -> WiFiLink {
        WiFiLink(rssi: rssi, noise: -94, transmitRate: 324, channel: 36, bandCode: 2, widthCode: 3, phyCode: 6)
    }

    @Test func decodesCoreWLANCodes() {
        let link = link()

        #expect(link.band == .ghz5)
        #expect(link.width == 80)
        #expect(link.standard == "802.11ax (Wi-Fi 6)")
        #expect(link.signalToNoise == 24)
    }

    @Test func unknownCodesStayEmpty() {
        let link = WiFiLink(rssi: -50, noise: -90, transmitRate: 1, channel: 1, bandCode: 0, widthCode: 0, phyCode: 0)

        #expect(link.band == .unknown)
        #expect(link.width == nil)
        #expect(link.standard == nil)
    }

    @Test(arguments: [(-58, 3), (-60, 3), (-61, 2), (-70, 2), (-71, 1)])
    func barsFollowTheLayout(rssi: Int, bars: Int) {
        #expect(link(rssi: rssi).bars == bars)
    }

    @Test(arguments: [
        (-45, WiFiQuality.excellent), (-58, .good), (-65, .fair), (-80, .weak),
    ])
    func qualityWords(rssi: Int, quality: WiFiQuality) {
        #expect(link(rssi: rssi).quality == quality)
    }

    @Test func chartScaleRoundTrips() {
        #expect(WiFiSignal.plotted(-58) == 42)
        #expect(WiFiSignal.rssi(plotted: 42) == -58)
    }
}
