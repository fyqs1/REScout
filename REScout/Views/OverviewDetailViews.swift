import SwiftUI

// MARK: - System

struct SystemDetailView: View {
    @EnvironmentObject private var store: DeviceInfoStore
    @EnvironmentObject private var settings: AppSettingsStore

    private var info: SystemInfo { store.snapshot.system }

    var body: some View {
        List {
            Section {
                overviewRow(L10n.tr("Device Name"), info.deviceName)
                overviewRow(L10n.tr("Device Model"), info.marketingModel)
                overviewRow(L10n.tr("Machine ID"), info.machineIdentifier)
                overviewRow(L10n.tr("System Version"), "\(info.systemName) \(info.systemVersion)")
                overviewRow(L10n.tr("Build Number"), info.buildNumber)
                overviewRow(L10n.tr("Uptime"), info.uptimeDescription)
                overviewRow(L10n.tr("Thermal"), info.thermalState)
                overviewRow(L10n.tr("Low Power Mode"), info.lowPowerMode ? L10n.tr("Yes") : L10n.tr("No"))
                overviewRow(L10n.tr("Screen"), "\(info.screenResolution) \(info.screenScale)")
                overviewRow(L10n.tr("Brightness"), info.brightness)
                overviewRow(L10n.tr("Volume"), info.volume)
                overviewOptionalRow(L10n.tr("Carrier"), info.carrier)
                overviewRow("IDFV", info.idfv)
                overviewOptionalRow("IDFA", info.idfa)
                overviewOptionalRow(L10n.tr("Tracking Status"), info.trackingStatus)
            }
        }
        .navigationTitle(L10n.tr("Section System"))
        .navigationBarTitleDisplayMode(.inline)
        .id(settings.localizationEpoch)
    }
}

// MARK: - CPU

struct CPUDetailView: View {
    @EnvironmentObject private var store: DeviceInfoStore
    @EnvironmentObject private var settings: AppSettingsStore

    private var info: CPUInfo { store.snapshot.cpu }

    var body: some View {
        List {
            Section {
                ProgressRow(
                    title: L10n.tr("CPU Usage"),
                    percent: info.usagePercent,
                    detail: Formatters.percent(info.usagePercent)
                )
                overviewRow(L10n.tr("CPU Idle"), Formatters.percent(info.idlePercent))
                overviewRow(L10n.tr("CPU Cores"), "\(info.coreCount) (\(info.activeCoreCount) active)")
                overviewRow(L10n.tr("CPU Arch"), info.architecture)
                overviewOptionalRow(L10n.tr("CPU Name"), info.cpuName)
                overviewOptionalRow(L10n.tr("CPU Freq Current"), info.currentFrequency)
                overviewOptionalRow(L10n.tr("CPU Freq Max"), info.maxFrequency)
            }
        }
        .navigationTitle(L10n.tr("Section CPU"))
        .navigationBarTitleDisplayMode(.inline)
        .id(settings.localizationEpoch)
    }
}

// MARK: - Memory

struct MemoryDetailView: View {
    @EnvironmentObject private var store: DeviceInfoStore
    @EnvironmentObject private var settings: AppSettingsStore

    private var info: MemoryInfo { store.snapshot.memory }

    var body: some View {
        List {
            Section {
                ProgressRow(
                    title: L10n.tr("Memory Usage"),
                    percent: info.usagePercent,
                    detail: Formatters.percent(info.usagePercent)
                )
                overviewRow(L10n.tr("Memory Total"), Formatters.bytes(info.totalBytes))
                overviewRow(L10n.tr("Memory Used"), Formatters.bytes(info.usedBytes))
                overviewRow(L10n.tr("Memory Free"), Formatters.bytes(info.freeBytes))
                overviewRow(L10n.tr("Memory Active"), Formatters.bytes(info.activeBytes))
                overviewRow(L10n.tr("Memory Inactive"), Formatters.bytes(info.inactiveBytes))
                overviewRow(L10n.tr("Memory Wired"), Formatters.bytes(info.wiredBytes))
                overviewRow(L10n.tr("Memory Compressed"), Formatters.bytes(info.compressedBytes))
                overviewRow(L10n.tr("Memory Pressure"), info.pressure)
            }

            Section {
                NavigationLink {
                    RunningAppsView()
                } label: {
                    Label(L10n.tr("Processes Title"), systemImage: "app.dashed")
                }
            } footer: {
                Text(L10n.tr("Processes Entry Footer"))
            }
        }
        .navigationTitle(L10n.tr("Section Memory"))
        .navigationBarTitleDisplayMode(.inline)
        .id(settings.localizationEpoch)
    }
}

// MARK: - Storage

struct StorageDetailView: View {
    @EnvironmentObject private var store: DeviceInfoStore
    @EnvironmentObject private var settings: AppSettingsStore

    private var info: StorageInfo { store.snapshot.storage }

    var body: some View {
        List {
            Section {
                ProgressRow(
                    title: L10n.tr("Disk Usage"),
                    percent: info.usagePercent,
                    detail: Formatters.percent(info.usagePercent)
                )
                overviewRow(L10n.tr("Disk Total"), Formatters.bytes(info.totalBytes))
                overviewRow(L10n.tr("Disk Used"), Formatters.bytes(info.usedBytes))
                overviewRow(L10n.tr("Disk Free"), Formatters.bytes(info.freeBytes))
            }
        }
        .navigationTitle(L10n.tr("Section Storage"))
        .navigationBarTitleDisplayMode(.inline)
        .id(settings.localizationEpoch)
    }
}

// MARK: - Battery

struct BatteryDetailView: View {
    @EnvironmentObject private var store: DeviceInfoStore
    @EnvironmentObject private var settings: AppSettingsStore

    private var info: BatteryInfo { store.snapshot.battery }

    var body: some View {
        List {
            Section {
                if let level = info.levelPercent {
                    ProgressRow(
                        title: L10n.tr("Battery Level"),
                        percent: Double(level),
                        detail: "\(level)%",
                        colorStyle: .battery
                    )
                }
                overviewRow(L10n.tr("Battery State"), info.state)
                overviewRow(L10n.tr("Low Power Mode"), info.lowPowerMode ? L10n.tr("Yes") : L10n.tr("No"))
                overviewOptionalRow(L10n.tr("Battery Health"), info.health)
                overviewOptionalRow(L10n.tr("Battery Voltage"), info.voltage)
                overviewOptionalRow(L10n.tr("Battery Amperage"), info.amperage)
                overviewOptionalRow(L10n.tr("Battery Temperature"), info.temperature)
                overviewOptionalRow(L10n.tr("Battery Capacity"), info.capacity)
                overviewOptionalRow(L10n.tr("Battery Cycles"), info.cycleCount)
                overviewOptionalRow(L10n.tr("Battery Serial"), info.serial)
            }
        }
        .navigationTitle(L10n.tr("Section Battery"))
        .navigationBarTitleDisplayMode(.inline)
        .id(settings.localizationEpoch)
    }
}

// MARK: - Network

struct NetworkDetailView: View {
    @EnvironmentObject private var store: DeviceInfoStore
    @EnvironmentObject private var settings: AppSettingsStore

    private var info: NetworkInfo { store.snapshot.network }

    var body: some View {
        List {
            Section {
                overviewRow(L10n.tr("Network Status"), info.pathStatus)
                overviewRow(L10n.tr("Network Type"), info.interfaceType)
                overviewOptionalRow(L10n.tr("SSID"), info.ssid)
                overviewOptionalRow(L10n.tr("BSSID"), info.bssid)
                overviewRow(L10n.tr("Local IPv4"), info.localIPv4)
                overviewOptionalRow(L10n.tr("Local IPv6"), info.localIPv6)
                overviewOptionalRow(L10n.tr("Gateway"), info.gateway)
                overviewOptionalRow(L10n.tr("DNS"), info.dnsServers)
                overviewOptionalRow(L10n.tr("Public IP"), info.publicIP)
                overviewRow(L10n.tr("WiFi Down"), Formatters.bitsPerSecond(info.wifiDownBps))
                overviewRow(L10n.tr("WiFi Up"), Formatters.bitsPerSecond(info.wifiUpBps))
                overviewRow(L10n.tr("Cellular Down"), Formatters.bitsPerSecond(info.cellularDownBps))
                overviewRow(L10n.tr("Cellular Up"), Formatters.bitsPerSecond(info.cellularUpBps))
                overviewRow(L10n.tr("Expensive"), info.isExpensive ? L10n.tr("Yes") : L10n.tr("No"))
                overviewRow(L10n.tr("Constrained"), info.isConstrained ? L10n.tr("Yes") : L10n.tr("No"))
            }

            Section(L10n.tr("Proxy")) {
                NavigationLink {
                    ProxyDetailView()
                } label: {
                    HStack {
                        Text(L10n.tr("Proxy"))
                        Spacer()
                        Text(info.proxySummary)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("Section Network"))
        .navigationBarTitleDisplayMode(.inline)
        .id(settings.localizationEpoch)
        .onAppear {
            NetworkCollector.shared.requestSSIDPermissionIfNeeded()
            store.refresh(forcePublicIP: true, mode: .light)
        }
    }
}

// MARK: - Jailbreak

struct JailbreakDetailView: View {
    @EnvironmentObject private var store: DeviceInfoStore
    @EnvironmentObject private var settings: AppSettingsStore

    private var info: JailbreakInfo { store.snapshot.jailbreak }

    var body: some View {
        List {
            Section {
                overviewRow(L10n.tr("JB Status"), info.statusLabel)
                overviewRow(L10n.tr("JB Environment"), info.environment)
                overviewOptionalRow(L10n.tr("JB Suspected"), info.suspectedJailbreak)
                overviewOptionalRow(L10n.tr("JB Bootstrap"), info.bootstrap)
            }
            Section(L10n.tr("JB Evidence")) {
                if info.evidences.isEmpty {
                    Text(L10n.tr("JB No Evidence"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(info.evidences, id: \.self) { item in
                        Text(item)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("Section Jailbreak"))
        .navigationBarTitleDisplayMode(.inline)
        .id(settings.localizationEpoch)
    }
}

// MARK: - Activity log

struct ActivityLogDetailView: View {
    @ObservedObject private var log = ActivityLogStore.shared
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        List {
            if log.entries.isEmpty {
                Text(L10n.tr("Activity Log Empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(log.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.category)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(entry.date.formatted(date: .abbreviated, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.caption.monospaced())
                            .foregroundStyle(color(for: entry.levelEnum))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(L10n.tr("Section Activity Log"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(L10n.tr("Clear Activity Log")) {
                    log.clear()
                }
                .disabled(log.entries.isEmpty)
            }
        }
        .id(settings.localizationEpoch)
    }

    private func color(for level: ActivityLogLevel) -> Color {
        switch level {
        case .info: return .primary
        case .warn: return .orange
        case .error: return .red
        }
    }
}
