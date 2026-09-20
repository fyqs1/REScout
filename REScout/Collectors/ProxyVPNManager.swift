import Foundation
import NetworkExtension

enum ProxyVPNStatus: Equatable {
    case invalid
    case disconnected
    case connecting
    case connected
    case disconnecting
    case reasserting
    case unknown(Int)

    var titleKey: String {
        switch self {
        case .invalid: return "Proxy VPN Invalid"
        case .disconnected: return "Proxy VPN Disconnected"
        case .connecting: return "Proxy VPN Connecting"
        case .connected: return "Proxy VPN Connected"
        case .disconnecting: return "Proxy VPN Disconnecting"
        case .reasserting: return "Proxy VPN Reasserting"
        case .unknown: return "Proxy VPN Unknown"
        }
    }

    static func from(_ status: NEVPNStatus) -> ProxyVPNStatus {
        switch status {
        case .invalid: return .invalid
        case .disconnected: return .disconnected
        case .connecting: return .connecting
        case .connected: return .connected
        case .disconnecting: return .disconnecting
        case .reasserting: return .reasserting
        @unknown default: return .unknown(status.rawValue)
        }
    }
}

/// Manages a Packet Tunnel that applies HTTP(S) proxy via NEProxySettings.
enum ProxyVPNManager {
    static let tunnelBundleID = "com.fyqs.REScout.PacketTunnel"
    static let displayName = "REScout Proxy"

    private static let lock = NSLock()
    private static var cachedStatus: ProxyVPNStatus = .disconnected
    private static var cachedHost = ""
    private static var cachedPort = 8080
    private static var isObserving = false

    /// Sync peek for overview / network rows (updated by `startObserving` / `refreshCache` / connect).
    static func currentStatus() -> ProxyVPNStatus {
        lock.lock()
        defer { lock.unlock() }
        return cachedStatus
    }

    /// When VPN proxy is active, prefer this over system Wi‑Fi prefs (often still “No Proxy”).
    static func effectiveProxySummary() -> String? {
        lock.lock()
        let status = cachedStatus
        let host = cachedHost
        let port = cachedPort
        lock.unlock()

        switch status {
        case .connected, .connecting, .reasserting:
            if !host.isEmpty {
                return "\(host):\(port)"
            }
            return L10n.tr(status.titleKey)
        default:
            return nil
        }
    }

    static func startObserving() {
        lock.lock()
        let already = isObserving
        if !already { isObserving = true }
        lock.unlock()
        guard !already else { return }
        refreshCache()
        NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { _ in
            refreshCache()
        }
    }

    static func refreshCache(completion: (() -> Void)? = nil) {
        loadManager { result in
            if case .success(let manager) = result {
                updateCache(from: manager)
            }
            completion?()
        }
    }

    static func updateCache(from manager: NETunnelProviderManager) {
        let status = ProxyVPNStatus.from(manager.connection.status)
        var host = ""
        var port = 8080
        if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
           let conf = proto.providerConfiguration {
            if let h = conf["proxyHost"] as? String, !h.isEmpty {
                host = h
            }
            if let p = conf["proxyPort"] as? Int {
                port = p
            } else if let n = conf["proxyPort"] as? NSNumber {
                port = n.intValue
            }
        }
        lock.lock()
        cachedStatus = status
        cachedHost = host
        cachedPort = port
        lock.unlock()
    }

    static func loadManager(completion: @escaping (Result<NETunnelProviderManager, Error>) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let existing = managers?.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == tunnelBundleID
            }) ?? managers?.first {
                completion(.success(existing))
                return
            }
            completion(.success(NETunnelProviderManager()))
        }
    }

    static func connect(
        host: String,
        port: Int,
        mirrorHTTPS: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, (1...65535).contains(port) else {
            completion(.failure(proxyError(1, L10n.tr("Proxy Invalid Input"))))
            return
        }

        loadManager { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let manager):
                let proto = NETunnelProviderProtocol()
                proto.providerBundleIdentifier = tunnelBundleID
                proto.serverAddress = "\(trimmed):\(port)"
                proto.providerConfiguration = [
                    "proxyHost": trimmed,
                    "proxyPort": port,
                    "mirrorHTTPS": mirrorHTTPS
                ]

                manager.protocolConfiguration = proto
                manager.localizedDescription = displayName
                manager.isEnabled = true

                manager.saveToPreferences { saveError in
                    if let saveError {
                        completion(.failure(saveError))
                        return
                    }
                    manager.loadFromPreferences { loadError in
                        if let loadError {
                            completion(.failure(loadError))
                            return
                        }
                        do {
                            try manager.connection.startVPNTunnel()
                            completion(.success(()))
                        } catch {
                            completion(.failure(error))
                        }
                    }
                }
            }
        }
    }

    static func disconnect(completion: @escaping (Result<Void, Error>) -> Void) {
        loadManager { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let manager):
                manager.connection.stopVPNTunnel()
                completion(.success(()))
            }
        }
    }

    static func removeProfile(completion: @escaping (Result<Void, Error>) -> Void) {
        loadManager { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let manager):
                manager.removeFromPreferences { error in
                    if let error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    private static func proxyError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "ProxyVPN", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
