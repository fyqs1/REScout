import Foundation

struct ProxySnapshot: Equatable {
    var httpEnabled: Bool
    var httpHost: String
    var httpPort: Int
    var httpsEnabled: Bool
    var httpsHost: String
    var httpsPort: Int
    var pacURL: String
    var summary: String
    var scopedNotes: [String]
    var wifiServiceName: String

    static var empty: ProxySnapshot {
        ProxySnapshot(
            httpEnabled: false, httpHost: "", httpPort: 8080,
            httpsEnabled: false, httpsHost: "", httpsPort: 8080,
            pacURL: "", summary: L10n.tr("No Proxy"), scopedNotes: [],
            wifiServiceName: ""
        )
    }
}

enum ProxySettingsManager {
    private static let prefsCandidates = [
        "/private/var/preferences/SystemConfiguration/preferences.plist",
        "/var/preferences/SystemConfiguration/preferences.plist"
    ]

    static func resolvedPrefsPath() -> String? {
        let fm = FileManager.default
        return prefsCandidates.first { fm.isReadableFile(atPath: $0) || fm.fileExists(atPath: $0) }
    }

    static func currentSnapshot() -> ProxySnapshot {
        var snap = ProxySnapshot.empty
        var prefsHadWiFi = false

        if let path = resolvedPrefsPath(),
           let root = loadMutablePlist(path),
           let service = findPrimaryWiFiService(in: root) {
            prefsHadWiFi = true
            snap.wifiServiceName = service.name
            let proxies = service.proxies
            if intValue(proxies["HTTPEnable"]) != 0 {
                snap.httpEnabled = true
                snap.httpHost = stringValue(proxies["HTTPProxy"])
                snap.httpPort = intValue(proxies["HTTPPort"]) ?? 0
            } else {
                // Explicitly disabled in prefs — do not let CFNetwork resurrect old values.
                snap.httpEnabled = false
                snap.httpHost = ""
                snap.httpPort = 8080
            }
            if intValue(proxies["HTTPSEnable"]) != 0 {
                snap.httpsEnabled = true
                snap.httpsHost = stringValue(proxies["HTTPSProxy"])
                snap.httpsPort = intValue(proxies["HTTPSPort"]) ?? 0
            } else {
                snap.httpsEnabled = false
                snap.httpsHost = ""
            }
            let pac = stringValue(proxies["ProxyAutoConfigURLString"])
            if !pac.isEmpty { snap.pacURL = pac }
        }

        // Effective proxy from CFNetwork (covers Packet Tunnel NEProxySettings while
        // system Wi‑Fi “Configure Proxy” remains off).
        if let cf = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
            let cfHTTPHost = cf["HTTPProxy"] as? String ?? ""
            let cfHTTPSHost = cf["HTTPSProxy"] as? String ?? ""
            let cfHTTPOn = !cfHTTPHost.isEmpty && (
                (cf["HTTPEnable"] as? NSNumber)?.boolValue == true || intValue(cf["HTTPEnable"]) != 0
            )
            let cfHTTPSOn = !cfHTTPSHost.isEmpty && (
                (cf["HTTPSEnable"] as? NSNumber)?.boolValue == true || intValue(cf["HTTPSEnable"]) != 0
            )

            if !snap.httpEnabled, cfHTTPOn {
                snap.httpEnabled = true
                snap.httpHost = cfHTTPHost
                snap.httpPort = intValue(cf["HTTPPort"]) ?? 0
                if prefsHadWiFi { snap.scopedNotes.append("VPN/CFNetwork") }
            } else if !prefsHadWiFi, !cfHTTPHost.isEmpty {
                snap.httpEnabled = true
                snap.httpHost = cfHTTPHost
                snap.httpPort = intValue(cf["HTTPPort"]) ?? 0
            }

            if !snap.httpsEnabled, cfHTTPSOn {
                snap.httpsEnabled = true
                snap.httpsHost = cfHTTPSHost
                snap.httpsPort = intValue(cf["HTTPSPort"]) ?? 0
            } else if !prefsHadWiFi, !cfHTTPSHost.isEmpty {
                snap.httpsEnabled = true
                snap.httpsHost = cfHTTPSHost
                snap.httpsPort = intValue(cf["HTTPSPort"]) ?? 0
            }

            if snap.pacURL.isEmpty, let pac = cf["ProxyAutoConfigURLString"] as? String, !pac.isEmpty {
                snap.pacURL = pac
            }
        }

        snap.summary = makeSummary(snap)
        if snap.httpPort == 0 { snap.httpPort = 8080 }
        if snap.httpsPort == 0 { snap.httpsPort = snap.httpPort }
        if snap.httpsHost.isEmpty { snap.httpsHost = snap.httpHost }
        return snap
    }

    static func apply(host: String, port: Int, enabled: Bool, mirrorHTTPS: Bool) -> Result<String, Error> {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !enabled || (!trimmedHost.isEmpty && (1...65535).contains(port)) else {
            return .failure(proxyError(1, L10n.tr("Proxy Invalid Input")))
        }
        guard let path = resolvedPrefsPath() else {
            return .failure(proxyError(2, L10n.tr("Proxy Prefs Missing")))
        }
        guard let root = loadMutablePlist(path) else {
            return .failure(proxyError(3, L10n.tr("Proxy Prefs Unreadable")))
        }

        let targets = allWiFiServicesMutable(in: root)
        guard !targets.isEmpty else {
            let detail = diagnoseServices(in: root)
            let msg = L10n.tr("Proxy WiFi Service Missing") + (detail.isEmpty ? "" : " \(detail)")
            return .failure(proxyError(4, msg))
        }

        let proxyPayload = buildProxiesPayload(
            host: trimmedHost,
            port: port,
            enabled: enabled,
            mirrorHTTPS: mirrorHTTPS,
            template: targets.first.flatMap { asStringAnyDict($0.service["Proxies"]) }
        )

        // Update ALL Wi-Fi NetworkServices in the in-memory plist.
        // Do NOT call SCPreferencesApply before disk write — configd will clobber the file.
        guard let networkServices = ensureMutableDict(root, key: "NetworkServices") else {
            return .failure(proxyError(3, L10n.tr("Proxy Prefs Unreadable")))
        }
        for t in targets {
            let svc = ensureMutableValue(in: networkServices, key: t.uuid) ?? t.service
            svc["Proxies"] = NSMutableDictionary(dictionary: proxyPayload)
            networkServices[t.uuid] = svc
        }
        root["NetworkServices"] = networkServices

        let backup = path + ".REScout.bak"
        if let existing = try? Data(contentsOf: URL(fileURLWithPath: path)), !existing.isEmpty {
            _ = DOVWriteDataToPathAsRoot(existing, backup)
        }

        let data: Data
        do {
            data = try PropertyListSerialization.data(
                fromPropertyList: root,
                format: .binary,
                options: 0
            )
        } catch {
            return .failure(error)
        }

        if let writeErr = DOVWriteDataToPathAsRoot(data, path) as String? {
            return .failure(proxyError(5, "\(L10n.tr("Proxy Write Failed")) \(writeErr)"))
        }

        // Verify persisted value matches what we asked for.
        if let verifyRoot = loadMutablePlist(path),
           let primary = findPrimaryWiFiService(in: verifyRoot) {
            let proxies = primary.proxies
            if enabled {
                let gotHost = stringValue(proxies["HTTPProxy"])
                let gotPort = intValue(proxies["HTTPPort"]) ?? 0
                let on = intValue(proxies["HTTPEnable"]) != 0
                if !on || gotHost != trimmedHost || gotPort != port {
                    return .failure(proxyError(
                        6,
                        "\(L10n.tr("Proxy Write Failed")) verify \(gotHost):\(gotPort) enable=\(on)"
                    ))
                }
            } else if intValue(proxies["HTTPEnable"]) != 0 {
                return .failure(proxyError(6, "\(L10n.tr("Proxy Write Failed")) still enabled after clear"))
            }
        }

        // Soft notify after verified disk write (configd should reload FROM file).
        notifyNetworkChange()

        let name = findPrimaryWiFiServiceMutable(in: root)?.name ?? targets[0].name
        let msg = enabled
            ? String(format: L10n.tr("Proxy Applied Format"), "\(trimmedHost):\(port)", name)
            : String(format: L10n.tr("Proxy Cleared Format"), name)
        return .success(msg)
    }

    // MARK: - Internals

    private static func loadMutablePlist(_ path: String) -> NSMutableDictionary? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let obj = try? PropertyListSerialization.propertyList(
            from: data,
            options: [.mutableContainersAndLeaves],
            format: &format
        ) else { return nil }
        if let m = obj as? NSMutableDictionary { return m }
        if let d = obj as? NSDictionary { return d.mutableCopy() as? NSMutableDictionary }
        return nil
    }

    private struct WiFiServiceInfo {
        let name: String
        let proxies: [String: Any]
    }

    private struct MutableWiFiService {
        let uuid: String
        let name: String
        var service: NSMutableDictionary
        var networkServices: NSMutableDictionary
    }

    private static func findPrimaryWiFiService(in root: NSMutableDictionary) -> WiFiServiceInfo? {
        guard let mutable = findPrimaryWiFiServiceMutable(in: root) else { return nil }
        return WiFiServiceInfo(
            name: mutable.name,
            proxies: asStringAnyDict(mutable.service["Proxies"]) ?? [:]
        )
    }

    /// Modern iOS keeps real Interface/Proxies under top-level NetworkServices;
    /// Sets/*/Network/Service only stores `__LINK__` stubs.
    private static func findPrimaryWiFiServiceMutable(in root: NSMutableDictionary) -> MutableWiFiService? {
        allWiFiServicesMutable(in: root).first
    }

    private static func allWiFiServicesMutable(in root: NSMutableDictionary) -> [MutableWiFiService] {
        guard let networkServices = ensureMutableDict(root, key: "NetworkServices") else {
            return []
        }

        let currentIDs = currentSetServiceIDs(in: root)
        var candidates: [(uuid: String, service: NSMutableDictionary, name: String, inCurrent: Bool, rank: Int)] = []

        let keys = networkServices.allKeys.compactMap { $0 as? String }
        for uuid in keys {
            guard let svc = ensureMutableValue(in: networkServices, key: uuid) else { continue }
            let iface = asStringAnyDict(svc["Interface"]) ?? [:]
            let serviceName = stringValue(svc["UserDefinedName"])
            guard isWiFiInterface(iface, serviceName: serviceName) else { continue }
            let name = serviceName.isEmpty
                ? (stringValue(iface["UserDefinedName"]).isEmpty ? "Wi-Fi" : stringValue(iface["UserDefinedName"]))
                : serviceName
            candidates.append((
                uuid,
                svc,
                name,
                currentIDs.contains(uuid),
                wifiRank(name: name, iface: iface)
            ))
        }

        let sorted = candidates.sorted { a, b in
            if a.inCurrent != b.inCurrent { return a.inCurrent && !b.inCurrent }
            if a.rank != b.rank { return a.rank < b.rank }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return sorted.map {
            MutableWiFiService(
                uuid: $0.uuid,
                name: $0.name,
                service: $0.service,
                networkServices: networkServices
            )
        }
    }

    private static func buildProxiesPayload(
        host: String,
        port: Int,
        enabled: Bool,
        mirrorHTTPS: Bool,
        template: [String: Any]?
    ) -> [String: Any] {
        var proxies = template ?? [:]
        if proxies["ExceptionsList"] == nil {
            proxies["ExceptionsList"] = ["*.local", "169.254/16"]
        }
        if proxies["FTPPassive"] == nil {
            proxies["FTPPassive"] = 1
        }
        if enabled {
            proxies["HTTPEnable"] = 1
            proxies["HTTPProxy"] = host
            proxies["HTTPPort"] = port
            if mirrorHTTPS {
                proxies["HTTPSEnable"] = 1
                proxies["HTTPSProxy"] = host
                proxies["HTTPSPort"] = port
            }
        } else {
            proxies["HTTPEnable"] = 0
            proxies["HTTPSEnable"] = 0
            proxies["ProxyAutoConfigEnable"] = 0
            proxies.removeValue(forKey: "HTTPProxy")
            proxies.removeValue(forKey: "HTTPSProxy")
            proxies.removeValue(forKey: "HTTPPort")
            proxies.removeValue(forKey: "HTTPSPort")
        }
        return proxies
    }

    private static func diagnoseServices(in root: NSMutableDictionary) -> String {
        guard let ns = root["NetworkServices"] as? NSDictionary else {
            return "[no NetworkServices]"
        }
        var bits: [String] = []
        bits.append("NS=\(ns.count)")
        for key in ns.allKeys.prefix(12) {
            guard let uuid = key as? String,
                  let svc = ns[uuid] as? NSDictionary else { continue }
            let iface = asStringAnyDict(svc["Interface"]) ?? [:]
            let name = stringValue(svc["UserDefinedName"])
            let hw = stringValue(iface["Hardware"])
            let dev = stringValue(iface["DeviceName"])
            bits.append("\(name)/\(hw)/\(dev)")
        }
        return "[" + bits.joined(separator: "; ") + "]"
    }

    private static func currentSetServiceIDs(in root: NSMutableDictionary) -> Set<String> {
        var ids = Set<String>()
        let currentRaw = stringValue(root["CurrentSet"])
        let setID = currentRaw.split(separator: "/").last.map(String.init) ?? currentRaw
        guard !setID.isEmpty,
              let sets = root["Sets"] as? NSDictionary else { return ids }
        let setDict = (sets[setID] as? NSDictionary) ?? (sets[currentRaw] as? NSDictionary)
        guard let setDict,
              let network = setDict["Network"] as? NSDictionary,
              let services = network["Service"] as? NSDictionary else { return ids }
        for key in services.allKeys {
            if let s = key as? String { ids.insert(s) }
        }
        return ids
    }

    private static func wifiRank(name: String, iface: [String: Any]) -> Int {
        let lower = name.lowercased()
        if lower == "wi-fi" || lower == "wifi" { return 0 }
        if lower.contains("wi-fi") || lower.contains("wifi") || name.contains("无线") { return 1 }
        if stringValue(iface["Hardware"]).caseInsensitiveCompare("AirPort") == .orderedSame { return 2 }
        return 3
    }

    private static func isWiFiInterface(_ iface: [String: Any], serviceName: String) -> Bool {
        let hardware = stringValue(iface["Hardware"]).lowercased()
        let type = stringValue(iface["Type"]).lowercased()
        let device = stringValue(iface["DeviceName"]).lowercased()
        let userName = {
            let fromIface = stringValue(iface["UserDefinedName"])
            return (fromIface.isEmpty ? serviceName : fromIface).lowercased()
        }()

        if hardware == "airport" { return true }
        if type == "airport" || type.contains("ieee80211") { return true }
        if userName == "wi-fi" || userName == "wifi" { return true }
        if userName.contains("wi-fi") || userName.contains("wifi") { return true }
        if userName.contains("无线") { return true }
        if device.hasPrefix("en") && hardware == "airport" { return true }
        return false
    }

    private static func ensureMutableDict(_ root: NSMutableDictionary, key: String) -> NSMutableDictionary? {
        if let m = root[key] as? NSMutableDictionary { return m }
        if let d = root[key] as? NSDictionary {
            let m = (d.mutableCopy() as? NSMutableDictionary) ?? NSMutableDictionary(dictionary: d)
            root[key] = m
            return m
        }
        return nil
    }

    private static func ensureMutableValue(in parent: NSMutableDictionary, key: String) -> NSMutableDictionary? {
        if let m = parent[key] as? NSMutableDictionary { return m }
        if let d = parent[key] as? NSDictionary {
            let m = (d.mutableCopy() as? NSMutableDictionary) ?? NSMutableDictionary(dictionary: d)
            parent[key] = m
            return m
        }
        return nil
    }

    private static func mutableChild(named key: String, of parent: NSMutableDictionary) -> NSMutableDictionary {
        if let m = parent[key] as? NSMutableDictionary { return m }
        if let d = parent[key] as? NSDictionary {
            let m = (d.mutableCopy() as? NSMutableDictionary) ?? NSMutableDictionary(dictionary: d)
            parent[key] = m
            return m
        }
        let m = NSMutableDictionary()
        parent[key] = m
        return m
    }

    private static func asStringAnyDict(_ value: Any?) -> [String: Any]? {
        if let d = value as? [String: Any] { return d }
        guard let d = value as? NSDictionary else { return nil }
        var out: [String: Any] = [:]
        d.enumerateKeysAndObjects { key, obj, _ in
            if let ks = key as? String {
                out[ks] = obj
            }
        }
        return out
    }

    private static func stringValue(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }

    private static func notifyNetworkChange() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.apple.system.config.network_change" as CFString),
            nil,
            nil,
            true
        )
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.apple.SystemConfiguration.NetworkConfigurationChanged" as CFString),
            nil,
            nil,
            true
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String, let i = Int(s) { return i }
        return nil
    }

    private static func makeSummary(_ snap: ProxySnapshot) -> String {
        var parts: [String] = []
        if snap.httpEnabled, !snap.httpHost.isEmpty {
            parts.append("HTTP \(snap.httpHost):\(snap.httpPort)")
        }
        if snap.httpsEnabled, !snap.httpsHost.isEmpty {
            parts.append("HTTPS \(snap.httpsHost):\(snap.httpsPort)")
        }
        if !snap.pacURL.isEmpty {
            parts.append("PAC \(snap.pacURL)")
        }
        parts.append(contentsOf: snap.scopedNotes)
        return parts.isEmpty ? L10n.tr("No Proxy") : Array(Set(parts)).sorted().joined(separator: " | ")
    }

    private static func proxyError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "Proxy", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
