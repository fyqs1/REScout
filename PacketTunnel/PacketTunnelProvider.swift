import NetworkExtension

/// VPN-style HTTP(S) proxy: brings up a Packet Tunnel and applies
/// `NEProxySettings` on the tunnel. System Wi‑Fi “Configure Proxy” stays off;
/// status bar shows the VPN indicator while connected.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var reading = false
    private var readPending = false

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let conf = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        let host = (conf["proxyHost"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let port = (conf["proxyPort"] as? Int)
            ?? (conf["proxyPort"] as? NSNumber)?.intValue
            ?? 8080
        let mirrorHTTPS = (conf["mirrorHTTPS"] as? Bool)
            ?? (conf["mirrorHTTPS"] as? NSNumber)?.boolValue
            ?? true

        guard !host.isEmpty, (1...65535).contains(port) else {
            completionHandler(
                NSError(
                    domain: "PacketTunnel",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing proxy host/port"]
                )
            )
            return
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: host)

        // Tiny fake interface, no default route — IP stays on physical iface;
        // system still applies tunnel `proxySettings` for HTTP(S) (VPN icon on).
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.255"])
        ipv4.includedRoutes = [
            NEIPv4Route(destinationAddress: "198.18.0.1", subnetMask: "255.255.255.255")
        ]
        settings.ipv4Settings = ipv4

        let proxy = NEProxySettings()
        proxy.httpEnabled = true
        proxy.httpServer = NEProxyServer(address: host, port: port)
        if mirrorHTTPS {
            proxy.httpsEnabled = true
            proxy.httpsServer = NEProxyServer(address: host, port: port)
        }
        // Empty-string match domain → apply to all hostnames (common NE pattern).
        proxy.matchDomains = [""]
        proxy.excludeSimpleHostnames = false
        proxy.exceptionList = ["localhost", "*.local", "127.0.0.1", "::1"]
        settings.proxySettings = proxy

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                completionHandler(error)
                return
            }
            self?.startReadingPackets()
            completionHandler(nil)
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        reading = false
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        completionHandler?(messageData)
    }

    private func startReadingPackets() {
        reading = true
        pumpPackets()
    }

    private func pumpPackets() {
        guard reading, !readPending else { return }
        readPending = true
        packetFlow.readPackets { [weak self] _, _ in
            guard let self else { return }
            self.readPending = false
            if self.reading {
                self.pumpPackets()
            }
        }
    }
}
