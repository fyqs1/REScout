import Foundation
import Combine

@MainActor
final class DeviceInfoStore: ObservableObject {
    @Published private(set) var snapshot: DeviceSnapshot = .placeholder
    @Published private(set) var isRefreshing = false

    private var timer: Timer?
    private var tickCount = 0
    private var sceneActive = false
    private var overviewVisible = false
    private var pauseDepth = 0
    private var refreshGeneration = 0
    private var autoRefreshEnabled = false

    /// Only used when Settings → Auto Refresh is on.
    private let lightInterval: TimeInterval = 30.0
    private let heavyEveryNTicks = 4 // ~2 minutes

    private var shouldPoll: Bool {
        sceneActive && overviewVisible && pauseDepth == 0 && autoRefreshEnabled
    }

    func start() {
        sceneActive = true
        // Light only: do not prompt for location / ATT / VPN / microphone at launch.
        refresh(forcePublicIP: false, mode: .light)
        syncTimer()
    }

    func stop() {
        sceneActive = false
        invalidateTimer()
    }

    func setAutoRefreshEnabled(_ enabled: Bool) {
        autoRefreshEnabled = enabled
        syncTimer()
    }

    func setSceneActive(_ active: Bool) {
        sceneActive = active
        syncTimer()
    }

    func setOverviewVisible(_ visible: Bool) {
        let was = overviewVisible
        overviewVisible = visible
        // First visit to Device tab: storage / jailbreak / system (no permission prompts).
        if visible && !was {
            refresh(forcePublicIP: true, mode: .full)
        }
        syncTimer()
    }

    func pushLivePause() {
        pauseDepth += 1
        syncTimer()
    }

    func popLivePause() {
        pauseDepth = max(0, pauseDepth - 1)
        syncTimer()
    }

    func refresh(forcePublicIP: Bool = false, mode: RefreshMode = .full) {
        let showSpinner = (mode == .full)
        if showSpinner {
            isRefreshing = true
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        let includeHeavy = (mode == .full)
        let previous = snapshot

        Task.detached(priority: .utility) {
            let cpu = CPUCollector.collect().quantized()
            let memory = MemoryCollector.collect().quantized()
            let battery = BatteryCollector.collect()
            let network = NetworkCollector.shared.collect(
                fetchPublicIP: forcePublicIP || includeHeavy
            ).quantized()

            let system: SystemInfo
            let storage: StorageInfo
            let jailbreak: JailbreakInfo
            if includeHeavy {
                storage = StorageCollector.collect()
                jailbreak = JailbreakCollector.collect()
                system = await MainActor.run { SystemCollector.collect() }
            } else {
                system = previous.system
                storage = previous.storage
                jailbreak = previous.jailbreak
            }

            let next = DeviceSnapshot(
                system: system,
                cpu: cpu,
                memory: memory,
                storage: storage,
                battery: battery,
                network: network,
                jailbreak: jailbreak,
                updatedAt: Date()
            )

            await MainActor.run {
                guard generation == self.refreshGeneration else { return }
                let changed =
                    next.system != previous.system
                    || next.cpu != previous.cpu
                    || next.memory != previous.memory
                    || next.storage != previous.storage
                    || next.battery != previous.battery
                    || next.network != previous.network
                    || next.jailbreak != previous.jailbreak
                if changed || includeHeavy {
                    self.snapshot = next
                }
                if showSpinner {
                    self.isRefreshing = false
                }
            }
        }
    }

    private func syncTimer() {
        if shouldPoll {
            guard timer == nil else { return }
            tickCount = 0
            let t = Timer(timeInterval: lightInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.onTimerFire()
                }
            }
            RunLoop.main.add(t, forMode: .default)
            timer = t
        } else {
            invalidateTimer()
        }
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func onTimerFire() {
        guard shouldPoll else {
            invalidateTimer()
            return
        }
        tickCount += 1
        let mode: RefreshMode = (tickCount % heavyEveryNTicks == 0) ? .full : .light
        refresh(forcePublicIP: false, mode: mode)
    }
}

enum RefreshMode {
    case light
    case full
}

private extension CPUInfo {
    func quantized() -> CPUInfo {
        var copy = self
        copy.usagePercent = (usagePercent * 10).rounded() / 10
        copy.idlePercent = (idlePercent * 10).rounded() / 10
        return copy
    }
}

private extension MemoryInfo {
    func quantized() -> MemoryInfo {
        var copy = self
        copy.usagePercent = usagePercent.rounded()
        let mb: UInt64 = 1_048_576
        func r(_ v: UInt64) -> UInt64 { (v / mb) * mb }
        copy.usedBytes = r(usedBytes)
        copy.freeBytes = r(freeBytes)
        copy.activeBytes = r(activeBytes)
        copy.inactiveBytes = r(inactiveBytes)
        copy.wiredBytes = r(wiredBytes)
        copy.compressedBytes = r(compressedBytes)
        return copy
    }
}

private extension NetworkInfo {
    func quantized() -> NetworkInfo {
        var copy = self
        func r(_ v: Double) -> Double { (v / 1024).rounded() * 1024 }
        copy.wifiUpBps = r(wifiUpBps)
        copy.wifiDownBps = r(wifiDownBps)
        copy.cellularUpBps = r(cellularUpBps)
        copy.cellularDownBps = r(cellularDownBps)
        return copy
    }
}
