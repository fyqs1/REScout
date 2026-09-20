import Foundation
import Network
import SystemConfiguration
import SystemConfiguration.CaptiveNetwork
import CoreLocation

#if canImport(NetworkExtension)
import NetworkExtension
#endif

final class NetworkCollector: NSObject, CLLocationManagerDelegate {
    static let shared = NetworkCollector()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.fyqs.REScout.network")
    private let locationManager = CLLocationManager()

    private var pathStatus = "—"
    private var interfaceType = "—"
    private var isExpensive = false
    private var isConstrained = false
    private var publicIP = ""
    private var lastPublicFetch: Date?
    private var ssid = ""
    private var bssid = ""

    private var lastSampleTime: Date?
    private var lastWifiIn: UInt64 = 0
    private var lastWifiOut: UInt64 = 0
    private var lastCellIn: UInt64 = 0
    private var lastCellOut: UInt64 = 0
    private var wifiUpBps: Double = 0
    private var wifiDownBps: Double = 0
    private var cellularUpBps: Double = 0
    private var cellularDownBps: Double = 0

    private var lastSSIDRefresh: Date?

    private override init() {
        super.init()
        locationManager.delegate = self
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.pathStatus = path.status == .satisfied
                ? L10n.tr("Network Satisfied")
                : L10n.tr("Network Unsatisfied")
            self.isExpensive = path.isExpensive
            self.isConstrained = path.isConstrained
            if path.usesInterfaceType(.wifi) {
                self.interfaceType = "Wi‑Fi"
            } else if path.usesInterfaceType(.cellular) {
                self.interfaceType = L10n.tr("Cellular")
            } else if path.usesInterfaceType(.wiredEthernet) {
                self.interfaceType = L10n.tr("Ethernet")
            } else if path.status == .satisfied {
                self.interfaceType = L10n.tr("Other")
            } else {
                self.interfaceType = L10n.tr("None")
            }
        }
        monitor.start(queue: queue)
    }

    func requestSSIDPermissionIfNeeded() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            DispatchQueue.main.async {
                ActivityLogStore.log(
                    .info,
                    category: L10n.tr("Log Category Permission"),
                    message: L10n.tr("Log Request Location")
                )
                self.locationManager.requestWhenInUseAuthorization()
            }
        }
    }

    func collect(fetchPublicIP: Bool = false) -> NetworkInfo {
        refreshRates()
        refreshSSID()
        if fetchPublicIP {
            maybeFetchPublicIP()
        }

        let addresses = InterfaceAddresses.current()
        let proxy = ProxyVPNManager.effectiveProxySummary()
            ?? ProxySettingsManager.currentSnapshot().summary
        let dns = DNSInfo.servers().joined(separator: ", ")

        return NetworkInfo(
            pathStatus: pathStatus,
            interfaceType: interfaceType,
            isExpensive: isExpensive,
            isConstrained: isConstrained,
            ssid: ssid,
            bssid: bssid,
            localIPv4: addresses.ipv4.isEmpty ? "—" : addresses.ipv4.joined(separator: ", "),
            localIPv6: addresses.ipv6.isEmpty ? "" : addresses.ipv6.joined(separator: ", "),
            gateway: addresses.gateway,
            dnsServers: dns,
            proxySummary: proxy,
            publicIP: publicIP,
            wifiUpBps: wifiUpBps,
            wifiDownBps: wifiDownBps,
            cellularUpBps: cellularUpBps,
            cellularDownBps: cellularDownBps
        )
    }

    private func refreshRates() {
        let counters = InterfaceAddresses.byteCounters()
        let now = Date()
        if let last = lastSampleTime {
            let dt = now.timeIntervalSince(last)
            if dt > 0.2 {
                wifiDownBps = Double(counters.wifiIn &- lastWifiIn) / dt
                wifiUpBps = Double(counters.wifiOut &- lastWifiOut) / dt
                cellularDownBps = Double(counters.cellIn &- lastCellIn) / dt
                cellularUpBps = Double(counters.cellOut &- lastCellOut) / dt
            }
        }
        lastSampleTime = now
        lastWifiIn = counters.wifiIn
        lastWifiOut = counters.wifiOut
        lastCellIn = counters.cellIn
        lastCellOut = counters.cellOut
    }

    private func refreshSSID() {
        let status = locationManager.authorizationStatus
        let authorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
        guard authorized else {
            return
        }
        if let last = lastSSIDRefresh, Date().timeIntervalSince(last) < 10 {
            return
        }
        lastSSIDRefresh = Date()

        // Path 1: CaptiveNetwork (works better with wifi-info entitlement)
        if let interfaces = CNCopySupportedInterfaces() as? [String] {
            for name in interfaces {
                if let info = CNCopyCurrentNetworkInfo(name as CFString) as NSDictionary? {
                    let ssidValue = info[kCNNetworkInfoKeySSID] as? String
                    let bssidValue = info[kCNNetworkInfoKeyBSSID] as? String
                    if let ssidValue, !ssidValue.isEmpty {
                        ssid = ssidValue
                        bssid = bssidValue ?? ""
                        return
                    }
                }
            }
        }

        // Path 2: NEHotspotNetwork — only after location is granted (otherwise iOS may prompt).
        if #available(iOS 14.0, *) {
            NEHotspotNetwork.fetchCurrent { [weak self] network in
                guard let self else { return }
                if let network, !network.ssid.isEmpty {
                    self.ssid = network.ssid
                    self.bssid = network.bssid
                }
            }
        }
    }

    private func maybeFetchPublicIP() {
        if let last = lastPublicFetch, Date().timeIntervalSince(last) < 30, !publicIP.isEmpty {
            return
        }
        lastPublicFetch = Date()
        guard let url = URL(string: "https://api.ipify.org?format=text") else { return }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            if error != nil { return }
            if let data, let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                self.publicIP = text
            }
        }.resume()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshSSID()
        let status = manager.authorizationStatus
        ActivityLogStore.log(
            .info,
            category: L10n.tr("Log Category Permission"),
            message: String(format: L10n.tr("Log Location Status Format"), "\(status.rawValue)")
        )
    }
}

private enum InterfaceAddresses {
    static func current() -> (ipv4: [String], ipv6: [String], gateway: String) {
        var ipv4: [String] = []
        var ipv6: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return ([], [], "")
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) != IFF_LOOPBACK else { continue }
            guard let addr = current.pointee.ifa_addr else { continue }
            let name = String(cString: current.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") || name.hasPrefix("bridge") else { continue }

            if addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                ipv4.append(String(cString: hostname))
            } else if addr.pointee.sa_family == UInt8(AF_INET6) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: hostname)
                if !ip.hasPrefix("fe80") {
                    ipv6.append(ip)
                }
            }
        }

        var gateway = ""
        var buffer = [CChar](repeating: 0, count: 64)
        if DOVCopyDefaultGateway(&buffer, Int32(buffer.count)) == 1 {
            gateway = String(cString: buffer)
        } else if let first = ipv4.first, let inferred = inferGateway(from: first) {
            gateway = inferred + " " + L10n.tr("Inferred")
        }
        return (ipv4, ipv6, gateway)
    }

    private static func inferGateway(from ipv4: String) -> String? {
        let parts = ipv4.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return nil }
        // Common home LAN guess: x.x.x.1
        return "\(parts[0]).\(parts[1]).\(parts[2]).1"
    }

    static func byteCounters() -> (wifiIn: UInt64, wifiOut: UInt64, cellIn: UInt64, cellOut: UInt64) {
        var wifiIn: UInt64 = 0
        var wifiOut: UInt64 = 0
        var cellIn: UInt64 = 0
        var cellOut: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return (0, 0, 0, 0)
        }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: current.pointee.ifa_name)
            let data = unsafeBitCast(current.pointee.ifa_data, to: UnsafeMutablePointer<if_data>?.self)
            guard let data else { continue }
            if name.hasPrefix("en") {
                wifiIn += UInt64(data.pointee.ifi_ibytes)
                wifiOut += UInt64(data.pointee.ifi_obytes)
            } else if name.hasPrefix("pdp_ip") {
                cellIn += UInt64(data.pointee.ifi_ibytes)
                cellOut += UInt64(data.pointee.ifi_obytes)
            }
        }
        return (wifiIn, wifiOut, cellIn, cellOut)
    }
}

private enum DNSInfo {
    static func servers() -> [String] {
        var buffer = [CChar](repeating: 0, count: 512)
        let written = DOVCopyDNSServers(&buffer, Int32(buffer.count))
        guard written > 0 else { return [] }
        let text = String(cString: buffer)
        return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
