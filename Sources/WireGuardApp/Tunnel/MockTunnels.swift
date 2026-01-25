//
// Copyright © 2025 Freecomm. All Rights Reserved.

import NetworkExtension

// Creates mock tunnels for the iOS Simulator.

#if targetEnvironment(simulator)
class MockTunnels {

    static let tunnelNames = [
        "NetNavi Agent"
    ]

    // static let tunnelNames: [String] = []
    static let address = "192.168.%d.%d/32"
    static let dnsServers = ["8.8.8.8", "8.8.4.4"]
    static let endpoint = "demo.netnavi.io:51820"
    static let allowedIPs = "0.0.0.0/0"

    static func createMockTunnels() -> [NETunnelProviderManager] {
        return tunnelNames.map { tunnelName -> NETunnelProviderManager in

            var interface = InterfaceConfiguration(privateKey: PrivateKey())
            interface.addresses = [IPAddressRange(from: String(format: address, Int.random(in: 1 ... 10), Int.random(in: 1 ... 254)))!]
            interface.dns = dnsServers.map { DNSServer(from: $0)! }

            var peer = PeerConfiguration(publicKey: PrivateKey().publicKey)
            peer.endpoint = Endpoint(from: endpoint)
            peer.allowedIPs = [IPAddressRange(from: allowedIPs)!]

            let tunnelConfiguration = TunnelConfiguration(name: tunnelName, interface: interface, peers: [peer])

            let tunnelProviderManager = NETunnelProviderManager()
            tunnelProviderManager.protocolConfiguration = NETunnelProviderProtocol(tunnelConfiguration: tunnelConfiguration)
            tunnelProviderManager.localizedDescription = tunnelConfiguration.name
            tunnelProviderManager.isEnabled = true

            return tunnelProviderManager
        }
    }
}
#endif
