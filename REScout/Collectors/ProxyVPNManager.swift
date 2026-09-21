import Foundation
import NetworkExtension

extension Notification.Name {
    static let proxyVPNStatusDidUpdate = Notification.Name("REScout.proxyVPNStatusDidUpdate")
}

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

    var blocksConnect: Bool {
        switch self {
        case .connecting, .connected, .disconnecting, .reasserting:
            return true
        default:
            return false
        }
    }

    var allowsDisconnect: Bool {
        switch self {
        case .connecting, .connected, .disconnecting, .reasserting:
            return true
        default:
            return false
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

/// Packet Tunnel that applies HTTP(S) proxy via `NEProxySettings`.
/// All preference I/O and start/stop go through one serial gate on the main thread.
enum ProxyVPNManager {
    static let tunnelBundleID = "com.fyqs.REScout.PacketTunnel"
    static let displayName = "REScout Proxy"

    private enum Keys {
        static let sessionActive = "proxy.vpn.sessionActive"
        static let host = "proxy.vpn.host"
        static let port = "proxy.vpn.port"
        static let mirrorHTTPS = "proxy.vpn.mirrorHTTPS"
    }

    private static let lock = NSLock()
    private static let gate = VPNSerialGate()
    private static var cachedStatus: ProxyVPNStatus = .disconnected
    private static var cachedHost = ""
    private static var cachedPort = 8080
    private static var cachedMirrorHTTPS = true
    private static var isObserving = false
    private static var didResolve = false
    private static var debounceWork: DispatchWorkItem?
    private static var statusObserver: NSObjectProtocol?

    static var sessionExpected: Bool {
        UserDefaults.standard.bool(forKey: Keys.sessionActive)
    }

    static func hasResolvedSession() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return didResolve
    }

    static func currentStatus() -> ProxyVPNStatus {
        lock.lock()
        defer { lock.unlock() }
        return cachedStatus
    }

    static func currentEndpoint() -> (host: String, port: Int, mirrorHTTPS: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (cachedHost, cachedPort, cachedMirrorHTTPS)
    }

    /// Sync peek for overview / network rows.
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

        restorePersistedEndpoint()
        if sessionExpected {
            lock.lock()
            if cachedStatus == .disconnected || cachedStatus == .invalid {
                cachedStatus = .connecting
            }
            lock.unlock()
            publish()
        }

        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { _ in
            scheduleRefresh()
        }
        refreshCache()
    }

    static func refreshCache(completion: (() -> Void)? = nil) {
        gate.enqueue { done in
            loadAllRetrying(attempts: sessionExpected ? 4 : 1, delay: 0.35) { result in
                switch result {
                case .success(let managers):
                    applyManagers(managers)
                case .failure:
                    lock.lock()
                    didResolve = true
                    lock.unlock()
                    publish()
                }
                completion?()
                done()
            }
        }
    }

    static func loadExistingManager(
        completion: @escaping (Result<NETunnelProviderManager?, Error>) -> Void
    ) {
        gate.enqueue { done in
            loadAllFromPreferencesOnMain { result in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let managers):
                    applyManagers(managers)
                    completion(.success(findOurManager(in: managers)))
                }
                done()
            }
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

        persistEndpoint(host: trimmed, port: port, mirrorHTTPS: mirrorHTTPS)
        let expectExisting = sessionExpected || currentStatus().blocksConnect
        setCached(status: .connecting, host: trimmed, port: port, mirrorHTTPS: mirrorHTTPS)
        publish()

        gate.enqueue { done in
            let finish: (Result<Void, Error>) -> Void = { result in
                if case .failure = result, !isTunnelUp(currentStatus()) {
                    setSessionActive(false)
                    setCachedStatus(.disconnected)
                    publish()
                }
                completion(result)
                done()
            }

            loadAllRetrying(attempts: expectExisting ? 4 : 1, delay: 0.35) { result in
                switch result {
                case .failure(let error):
                    finish(.failure(error))
                case .success(let managers):
                    if let existing = findOurManager(in: managers) {
                        startOrReuse(
                            existing,
                            host: trimmed,
                            port: port,
                            mirrorHTTPS: mirrorHTTPS,
                            allowRetryOnStale: true,
                            completion: finish
                        )
                    } else {
                        let created = NETunnelProviderManager()
                        configure(created, host: trimmed, port: port, mirrorHTTPS: mirrorHTTPS)
                        saveReloadAndStart(
                            hintManager: created,
                            host: trimmed,
                            port: port,
                            mirrorHTTPS: mirrorHTTPS,
                            allowRetryOnStale: true,
                            completion: finish
                        )
                    }
                }
            }
        }
    }

    static func disconnect(completion: @escaping (Result<Void, Error>) -> Void) {
        setCachedStatus(.disconnecting)
        publish()

        gate.enqueue { done in
            let finish: (Result<Void, Error>) -> Void = { result in
                if case .success = result {
                    setSessionActive(false)
                    setCachedStatus(.disconnected)
                    publish()
                }
                completion(result)
                done()
            }

            loadAllFromPreferencesOnMain { result in
                switch result {
                case .failure(let error):
                    finish(.failure(error))
                case .success(let managers):
                    guard let manager = findOurManager(in: managers) else {
                        finish(.success(()))
                        return
                    }
                    let status = manager.connection.status
                    if status == .disconnected || status == .invalid {
                        updateCache(from: manager)
                        finish(.success(()))
                        return
                    }
                    manager.connection.stopVPNTunnel()
                    wait(
                        for: manager,
                        timeout: 12,
                        isSuccess: { $0 == .disconnected || $0 == .invalid },
                        isFailure: { _, _ in false }
                    ) { finalStatus in
                        updateCache(from: manager)
                        if finalStatus == .disconnected || finalStatus == .invalid {
                            finish(.success(()))
                        } else {
                            setSessionActive(false)
                            setCachedStatus(.disconnected)
                            publish()
                            finish(.success(()))
                        }
                    }
                }
            }
        }
    }

    static func removeProfile(completion: @escaping (Result<Void, Error>) -> Void) {
        gate.enqueue { done in
            loadAllFromPreferencesOnMain { result in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                    done()
                case .success(let managers):
                    guard let manager = findOurManager(in: managers) else {
                        setSessionActive(false)
                        setCachedStatus(.disconnected)
                        publish()
                        completion(.success(()))
                        done()
                        return
                    }
                    manager.removeFromPreferences { error in
                        DispatchQueue.main.async {
                            if let error {
                                completion(.failure(error))
                            } else {
                                setSessionActive(false)
                                setCachedStatus(.disconnected)
                                publish()
                                completion(.success(()))
                            }
                            done()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Internals

    private static func startOrReuse(
        _ manager: NETunnelProviderManager,
        host: String,
        port: Int,
        mirrorHTTPS: Bool,
        allowRetryOnStale: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let status = manager.connection.status
        updateCache(from: manager)
        publish()

        if status == .connected {
            setSessionActive(true)
            completion(.success(()))
            return
        }
        if status == .connecting || status == .reasserting {
            waitForConnected(manager, completion: completion)
            return
        }

        configure(manager, host: host, port: port, mirrorHTTPS: mirrorHTTPS)
        saveReloadAndStart(
            hintManager: manager,
            host: host,
            port: port,
            mirrorHTTPS: mirrorHTTPS,
            allowRetryOnStale: allowRetryOnStale,
            completion: completion
        )
    }

    private static func saveReloadAndStart(
        hintManager: NETunnelProviderManager,
        host: String,
        port: Int,
        mirrorHTTPS: Bool,
        allowRetryOnStale: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        hintManager.saveToPreferences { saveError in
            DispatchQueue.main.async {
                if let saveError {
                    completion(.failure(saveError))
                    return
                }
                loadAllRetrying(attempts: 3, delay: 0.3) { result in
                    switch result {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let managers):
                        guard let fresh = findOurManager(in: managers) else {
                            completion(.failure(proxyError(7, L10n.tr("Proxy VPN Connect Failed"))))
                            return
                        }
                        applyManagers(managers)
                        startEnabledTunnel(
                            fresh,
                            allowRetryOnStale: allowRetryOnStale,
                            host: host,
                            port: port,
                            mirrorHTTPS: mirrorHTTPS,
                            completion: completion
                        )
                    }
                }
            }
        }
    }

    private static func startEnabledTunnel(
        _ manager: NETunnelProviderManager,
        allowRetryOnStale: Bool,
        host: String,
        port: Int,
        mirrorHTTPS: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if manager.isEnabled {
            startTunnel(
                manager,
                allowRetryOnStale: allowRetryOnStale,
                host: host,
                port: port,
                mirrorHTTPS: mirrorHTTPS,
                completion: completion
            )
            return
        }
        manager.isEnabled = true
        manager.saveToPreferences { enableError in
            DispatchQueue.main.async {
                if let enableError {
                    completion(.failure(enableError))
                    return
                }
                loadAllRetrying(attempts: 3, delay: 0.3) { result in
                    switch result {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let managers):
                        guard let fresh = findOurManager(in: managers) else {
                            completion(.failure(proxyError(7, L10n.tr("Proxy VPN Connect Failed"))))
                            return
                        }
                        startTunnel(
                            fresh,
                            allowRetryOnStale: allowRetryOnStale,
                            host: host,
                            port: port,
                            mirrorHTTPS: mirrorHTTPS,
                            completion: completion
                        )
                    }
                }
            }
        }
    }

    private static func startTunnel(
        _ manager: NETunnelProviderManager,
        allowRetryOnStale: Bool,
        host: String,
        port: Int,
        mirrorHTTPS: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let status = manager.connection.status
        if status == .connected {
            updateCache(from: manager)
            setSessionActive(true)
            publish()
            completion(.success(()))
            return
        }
        if status == .connecting || status == .reasserting {
            waitForConnected(manager, completion: completion)
            return
        }

        do {
            try manager.connection.startVPNTunnel()
            setSessionActive(true)
            updateCache(from: manager)
            publish()
            waitForConnected(manager, completion: completion)
        } catch {
            let ns = error as NSError
            if manager.connection.status == .connected
                || manager.connection.status == .connecting
                || manager.connection.status == .reasserting {
                waitForConnected(manager, completion: completion)
                return
            }
            if allowRetryOnStale,
               ns.domain == NEVPNErrorDomain,
               ns.code == NEVPNError.Code.configurationStale.rawValue {
                loadAllFromPreferencesOnMain { result in
                    switch result {
                    case .failure(let reloadError):
                        completion(.failure(reloadError))
                    case .success(let managers):
                        guard let fresh = findOurManager(in: managers) else {
                            completion(.failure(error))
                            return
                        }
                        startTunnel(
                            fresh,
                            allowRetryOnStale: false,
                            host: host,
                            port: port,
                            mirrorHTTPS: mirrorHTTPS,
                            completion: completion
                        )
                    }
                }
                return
            }
            completion(.failure(error))
        }
    }

    private static func waitForConnected(
        _ manager: NETunnelProviderManager,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        wait(
            for: manager,
            timeout: 20,
            isSuccess: { $0 == .connected },
            isFailure: { status, sawConnecting in
                status == .invalid || (sawConnecting && status == .disconnected)
            }
        ) { finalStatus in
            updateCache(from: manager)
            publish()
            if finalStatus == .connected {
                setSessionActive(true)
                completion(.success(()))
            } else if finalStatus == .connecting || finalStatus == .reasserting {
                completion(.failure(proxyError(8, L10n.tr("Proxy VPN Connect Timeout"))))
            } else {
                completion(.failure(proxyError(9, L10n.tr("Proxy VPN Connect Failed"))))
            }
        }
    }

    private static func wait(
        for manager: NETunnelProviderManager,
        timeout: TimeInterval,
        isSuccess: @escaping (NEVPNStatus) -> Bool,
        isFailure: @escaping (NEVPNStatus, Bool) -> Bool,
        completion: @escaping (NEVPNStatus) -> Void
    ) {
        var finished = false
        var observer: NSObjectProtocol?
        var timeoutWork: DispatchWorkItem?
        var sawConnecting = isTunnelUp(ProxyVPNStatus.from(manager.connection.status))
            || manager.connection.status == .connecting

        let finish: (NEVPNStatus) -> Void = { status in
            guard !finished else { return }
            finished = true
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            timeoutWork?.cancel()
            completion(status)
        }

        if isSuccess(manager.connection.status) {
            finish(manager.connection.status)
            return
        }

        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { _ in
            let status = manager.connection.status
            if status == .connecting || status == .reasserting || status == .connected {
                sawConnecting = true
            }
            updateCache(from: manager)
            publish()
            if isSuccess(status) || isFailure(status, sawConnecting) {
                finish(status)
            }
        }

        let work = DispatchWorkItem {
            finish(manager.connection.status)
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    private static func configure(
        _ manager: NETunnelProviderManager,
        host: String,
        port: Int,
        mirrorHTTPS: Bool
    ) {
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleID
        proto.serverAddress = "\(host):\(port)"
        proto.providerConfiguration = [
            "proxyHost": host,
            "proxyPort": port,
            "mirrorHTTPS": mirrorHTTPS
        ]
        manager.protocolConfiguration = proto
        manager.localizedDescription = displayName
        manager.isEnabled = true
    }

    private static func loadAllRetrying(
        attempts: Int,
        delay: TimeInterval,
        completion: @escaping (Result<[NETunnelProviderManager], Error>) -> Void
    ) {
        loadAllFromPreferencesOnMain { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let managers):
                if findOurManager(in: managers) != nil || attempts <= 1 {
                    completion(.success(managers))
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    loadAllRetrying(attempts: attempts - 1, delay: delay, completion: completion)
                }
            }
        }
    }

    private static func loadAllFromPreferencesOnMain(
        completion: @escaping (Result<[NETunnelProviderManager], Error>) -> Void
    ) {
        let run = {
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                DispatchQueue.main.async {
                    if let error {
                        completion(.failure(error))
                    } else {
                        completion(.success(managers ?? []))
                    }
                }
            }
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    private static func findOurManager(in managers: [NETunnelProviderManager]) -> NETunnelProviderManager? {
        if let match = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier == tunnelBundleID
        }) {
            return match
        }
        return managers.first(where: { $0.localizedDescription == displayName })
    }

    private static func applyManagers(_ managers: [NETunnelProviderManager]) {
        if let manager = findOurManager(in: managers) {
            updateCache(from: manager)
            switch manager.connection.status {
            case .connected, .connecting, .reasserting, .disconnecting:
                setSessionActive(true)
            case .disconnected:
                setSessionActive(false)
                setCachedStatus(.disconnected)
            case .invalid:
                if sessionExpected {
                    setCachedStatus(.connecting)
                } else {
                    setCachedStatus(.invalid)
                }
            @unknown default:
                break
            }
            lock.lock()
            didResolve = true
            lock.unlock()
            publish()
            return
        }

        lock.lock()
        didResolve = true
        let expected = UserDefaults.standard.bool(forKey: Keys.sessionActive)
        if expected {
            if cachedStatus == .disconnected || cachedStatus == .invalid {
                cachedStatus = .connecting
            }
        } else {
            cachedStatus = .disconnected
        }
        lock.unlock()
        publish()
    }

    private static func updateCache(from manager: NETunnelProviderManager) {
        let status = ProxyVPNStatus.from(manager.connection.status)
        var host = ""
        var port = 8080
        var mirror = true
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
            if let m = conf["mirrorHTTPS"] as? Bool {
                mirror = m
            } else if let n = conf["mirrorHTTPS"] as? NSNumber {
                mirror = n.boolValue
            }
        }
        if host.isEmpty {
            restorePersistedEndpoint()
            lock.lock()
            cachedStatus = status
            lock.unlock()
            return
        }
        persistEndpoint(host: host, port: port, mirrorHTTPS: mirror)
        setCached(status: status, host: host, port: port, mirrorHTTPS: mirror)
    }

    private static func scheduleRefresh() {
        debounceWork?.cancel()
        let work = DispatchWorkItem {
            refreshCache()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private static func restorePersistedEndpoint() {
        let host = UserDefaults.standard.string(forKey: Keys.host) ?? ""
        let port = UserDefaults.standard.object(forKey: Keys.port) as? Int ?? 8080
        let mirror = UserDefaults.standard.object(forKey: Keys.mirrorHTTPS) as? Bool ?? true
        lock.lock()
        if !host.isEmpty { cachedHost = host }
        cachedPort = port
        cachedMirrorHTTPS = mirror
        lock.unlock()
    }

    private static func persistEndpoint(host: String, port: Int, mirrorHTTPS: Bool) {
        UserDefaults.standard.set(host, forKey: Keys.host)
        UserDefaults.standard.set(port, forKey: Keys.port)
        UserDefaults.standard.set(mirrorHTTPS, forKey: Keys.mirrorHTTPS)
    }

    private static func setSessionActive(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: Keys.sessionActive)
    }

    private static func setCached(
        status: ProxyVPNStatus,
        host: String,
        port: Int,
        mirrorHTTPS: Bool
    ) {
        lock.lock()
        cachedStatus = status
        cachedHost = host
        cachedPort = port
        cachedMirrorHTTPS = mirrorHTTPS
        lock.unlock()
    }

    private static func setCachedStatus(_ status: ProxyVPNStatus) {
        lock.lock()
        cachedStatus = status
        lock.unlock()
    }

    private static func isTunnelUp(_ status: ProxyVPNStatus) -> Bool {
        switch status {
        case .connected, .connecting, .reasserting: return true
        default: return false
        }
    }

    private static func publish() {
        let post = {
            NotificationCenter.default.post(name: .proxyVPNStatusDidUpdate, object: nil)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    private static func proxyError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "ProxyVPN", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private final class VPNSerialGate {
    private let queue = DispatchQueue(label: "com.fyqs.REScout.proxy-vpn")
    private var busy = false
    private var pending: [(@escaping () -> Void) -> Void] = []

    func enqueue(_ work: @escaping (@escaping () -> Void) -> Void) {
        queue.async {
            self.pending.append(work)
            self.pump()
        }
    }

    private func pump() {
        guard !busy, let work = pending.first else { return }
        pending.removeFirst()
        busy = true
        DispatchQueue.main.async {
            var finished = false
            work { [weak self] in
                guard !finished else { return }
                finished = true
                self?.queue.async {
                    self?.busy = false
                    self?.pump()
                }
            }
        }
    }
}
