import Foundation

struct DeviceSnapshot: Equatable {
    var system: SystemInfo
    var cpu: CPUInfo
    var memory: MemoryInfo
    var storage: StorageInfo
    var battery: BatteryInfo
    var network: NetworkInfo
    var jailbreak: JailbreakInfo
    var updatedAt: Date
}

struct SystemInfo: Equatable {
    var deviceName: String
    var marketingModel: String
    var machineIdentifier: String
    var systemName: String
    var systemVersion: String
    var buildNumber: String
    var uptimeDescription: String
    var thermalState: String
    var lowPowerMode: Bool
    var screenResolution: String
    var screenScale: String
    var brightness: String
    var volume: String
    var carrier: String
    var idfv: String
    var idfa: String
    var trackingStatus: String
}

struct CPUInfo: Equatable {
    var usagePercent: Double
    var idlePercent: Double
    var coreCount: Int
    var activeCoreCount: Int
    var architecture: String
    var cpuName: String
    var currentFrequency: String
    var maxFrequency: String
}

struct MemoryInfo: Equatable {
    var totalBytes: UInt64
    var usedBytes: UInt64
    var freeBytes: UInt64
    var activeBytes: UInt64
    var inactiveBytes: UInt64
    var wiredBytes: UInt64
    var compressedBytes: UInt64
    var pressure: String
    var usagePercent: Double
}

struct StorageInfo: Equatable {
    var totalBytes: UInt64
    var usedBytes: UInt64
    var freeBytes: UInt64
    var usagePercent: Double
}

struct BatteryInfo: Equatable {
    var levelPercent: Int?
    var state: String
    var lowPowerMode: Bool
    var health: String
    var voltage: String
    var amperage: String
    var temperature: String
    var capacity: String
    var cycleCount: String
    var serial: String
}

struct NetworkInfo: Equatable {
    var pathStatus: String
    var interfaceType: String
    var isExpensive: Bool
    var isConstrained: Bool
    var ssid: String
    var bssid: String
    var localIPv4: String
    var localIPv6: String
    var gateway: String
    var dnsServers: String
    var proxySummary: String
    var publicIP: String
    var wifiUpBps: Double
    var wifiDownBps: Double
    var cellularUpBps: Double
    var cellularDownBps: Double
}

struct JailbreakInfo: Equatable {
    var isJailbroken: Bool
    var statusLabel: String
    var environment: String
    var suspectedJailbreak: String
    var bootstrap: String
    var evidences: [String]
}

extension DeviceSnapshot {
    static var placeholder: DeviceSnapshot {
        DeviceSnapshot(
            system: SystemInfo(
                deviceName: "—", marketingModel: "—", machineIdentifier: "—",
                systemName: "iOS", systemVersion: "—", buildNumber: "—",
                uptimeDescription: "—", thermalState: "—", lowPowerMode: false,
                screenResolution: "—", screenScale: "—", brightness: "—",
                volume: "—", carrier: "", idfv: "—", idfa: "", trackingStatus: ""
            ),
            cpu: CPUInfo(
                usagePercent: 0, idlePercent: 100, coreCount: 0, activeCoreCount: 0,
                architecture: "—", cpuName: "—",
                currentFrequency: "", maxFrequency: ""
            ),
            memory: MemoryInfo(
                totalBytes: 0, usedBytes: 0, freeBytes: 0, activeBytes: 0,
                inactiveBytes: 0, wiredBytes: 0, compressedBytes: 0,
                pressure: "—", usagePercent: 0
            ),
            storage: StorageInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, usagePercent: 0),
            battery: BatteryInfo(
                levelPercent: nil, state: "—", lowPowerMode: false,
                health: "", voltage: "", amperage: "", temperature: "",
                capacity: "", cycleCount: "", serial: ""
            ),
            network: NetworkInfo(
                pathStatus: "—", interfaceType: "—", isExpensive: false, isConstrained: false,
                ssid: "", bssid: "", localIPv4: "—", localIPv6: "",
                gateway: "", dnsServers: "", proxySummary: "—", publicIP: "",
                wifiUpBps: 0, wifiDownBps: 0, cellularUpBps: 0, cellularDownBps: 0
            ),
            jailbreak: JailbreakInfo(
                isJailbroken: false, statusLabel: "—", environment: "—",
                suspectedJailbreak: "", bootstrap: "", evidences: []
            ),
            updatedAt: Date()
        )
    }
}
