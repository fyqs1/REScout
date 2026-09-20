import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: DeviceInfoStore
    @EnvironmentObject private var settings: AppSettingsStore
    @ObservedObject private var activityLog = ActivityLogStore.shared
    @State private var editMode: EditMode = .inactive
    @State private var activeSection: OverviewSectionID?
    @State private var holdingDetailPause = false

    var body: some View {
        NavigationView {
            List {
                ForEach(settings.overviewOrder) { section in
                    // Programmatic NavigationLink hides the system trailing chevron
                    // (outer arrow). Keep the chevron drawn inside the card.
                    Button {
                        activeSection = section
                    } label: {
                        OverviewSummaryCard(title: L10n.tr(section.titleKey), icon: section.icon) {
                            summaryContent(for: section)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove(perform: settings.moveOverview)

                Text(String(format: L10n.tr("Updated At Format"), store.snapshot.updatedAt.formatted(date: .omitted, time: .standard)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if !settings.autoRefreshOverview {
                    Text(L10n.tr("Overview Manual Refresh Hint"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
            .background(
                NavigationLink(
                    destination: Group {
                        if let section = activeSection {
                            destination(for: section)
                        } else {
                            EmptyView()
                        }
                    },
                    isActive: Binding(
                        get: { activeSection != nil },
                        set: { if !$0 { activeSection = nil } }
                    ),
                    label: { EmptyView() }
                )
                .hidden()
            )
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(L10n.tr("Overview"))
            .id(settings.localizationEpoch)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(editMode.isEditing ? L10n.tr("Done") : L10n.tr("Reorder")) {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        store.refresh(forcePublicIP: true, mode: .full)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(L10n.tr("Refresh"))
                }
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: activeSection) { section in
            syncDetailPause(section != nil)
        }
        .onDisappear {
            syncDetailPause(false)
        }
    }

    private func syncDetailPause(_ shouldHold: Bool) {
        if shouldHold, !holdingDetailPause {
            store.pushLivePause()
            holdingDetailPause = true
        } else if !shouldHold, holdingDetailPause {
            store.popLivePause()
            holdingDetailPause = false
        }
    }

    @ViewBuilder
    private func destination(for section: OverviewSectionID) -> some View {
        switch section {
        case .system: SystemDetailView()
        case .cpu: CPUDetailView()
        case .memory: MemoryDetailView()
        case .storage: StorageDetailView()
        case .battery: BatteryDetailView()
        case .network: NetworkDetailView()
        case .jailbreak: JailbreakDetailView()
        case .activityLog: ActivityLogDetailView()
        }
    }

    @ViewBuilder
    private func summaryContent(for section: OverviewSectionID) -> some View {
        switch section {
        case .system:
            row(L10n.tr("Device Model"), store.snapshot.system.marketingModel)
            row(L10n.tr("System Version"), "\(store.snapshot.system.systemName) \(store.snapshot.system.systemVersion)")
            row(L10n.tr("Uptime"), store.snapshot.system.uptimeDescription)
        case .cpu:
            ProgressRow(
                title: L10n.tr("CPU Usage"),
                percent: store.snapshot.cpu.usagePercent,
                detail: Formatters.percent(store.snapshot.cpu.usagePercent)
            )
            row(L10n.tr("CPU Cores"), "\(store.snapshot.cpu.coreCount)")
            optionalRow(L10n.tr("CPU Name"), store.snapshot.cpu.cpuName)
        case .memory:
            ProgressRow(
                title: L10n.tr("Memory Usage"),
                percent: store.snapshot.memory.usagePercent,
                detail: Formatters.percent(store.snapshot.memory.usagePercent)
            )
            row(
                L10n.tr("Memory Used"),
                "\(Formatters.bytes(store.snapshot.memory.usedBytes)) / \(Formatters.bytes(store.snapshot.memory.totalBytes))"
            )
        case .storage:
            ProgressRow(
                title: L10n.tr("Disk Usage"),
                percent: store.snapshot.storage.usagePercent,
                detail: Formatters.percent(store.snapshot.storage.usagePercent)
            )
            row(L10n.tr("Disk Free"), Formatters.bytes(store.snapshot.storage.freeBytes))
        case .battery:
            if let level = store.snapshot.battery.levelPercent {
                ProgressRow(
                    title: L10n.tr("Battery Level"),
                    percent: Double(level),
                    detail: "\(level)%",
                    colorStyle: .battery
                )
            }
            row(L10n.tr("Battery State"), store.snapshot.battery.state)
        case .network:
            row(L10n.tr("Network Type"), store.snapshot.network.interfaceType)
            row(L10n.tr("Local IPv4"), store.snapshot.network.localIPv4)
            optionalRow(L10n.tr("SSID"), store.snapshot.network.ssid)
        case .jailbreak:
            row(L10n.tr("JB Status"), store.snapshot.jailbreak.statusLabel)
            row(L10n.tr("JB Environment"), store.snapshot.jailbreak.environment)
        case .activityLog:
            if activityLog.entries.isEmpty {
                Text(L10n.tr("Activity Log Empty"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(activityLog.entries.prefix(3)) { entry in
                    HStack {
                        Text(entry.category)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(entry.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(L10n.tr("Tap For Full Details"))
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
        }
    }
}

// MARK: - Shared overview UI

struct OverviewSummaryCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            content
            Text(L10n.tr("Tap For Full Details"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .contentShape(Rectangle())
    }
}

struct ProgressRow: View {
    enum ColorStyle {
        case load
        case battery
    }

    let title: String
    let percent: Double
    let detail: String
    var colorStyle: ColorStyle = .load

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(detail)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            ProgressView(value: min(max(percent, 0), 100), total: 100)
                .tint(percentColor(percent))
        }
        .padding(.vertical, 2)
    }

    private func percentColor(_ value: Double) -> Color {
        switch colorStyle {
        case .load:
            if value >= 85 { return .red }
            if value >= 65 { return .orange }
            return .accentColor
        case .battery:
            if value <= 20 { return .red }
            if value <= 35 { return .orange }
            return .green
        }
    }
}

@ViewBuilder
func overviewRow(_ title: String, _ value: String) -> some View {
    HStack(alignment: .top) {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(width: 120, alignment: .leading)
        Text(value)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .textSelection(.enabled)
    }
    .padding(.vertical, 2)
}

@ViewBuilder
func overviewOptionalRow(_ title: String, _ value: String) -> some View {
    if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        overviewRow(title, value)
    }
}

@ViewBuilder
func row(_ title: String, _ value: String) -> some View {
    overviewRow(title, value)
}

@ViewBuilder
func optionalRow(_ title: String, _ value: String) -> some View {
    overviewOptionalRow(title, value)
}
