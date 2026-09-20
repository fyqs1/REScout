import Foundation
import Darwin

enum MemoryCollector {
    static func collect() -> MemoryInfo {
        let total = ProcessInfo.processInfo.physicalMemory
        let stats = vmStatistics()
        let pageSize = UInt64(vm_kernel_page_size)

        let free = UInt64(stats.free_count) * pageSize
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        // App-style "used": exclude inactive/speculative (reclaimable file cache).
        // Counting them made usage look artificially high after killing apps.
        let used = min(active + wired + compressed, total)
        let available = min(free + inactive + speculative, total)
        let usage = total == 0 ? 0 : (Double(used) / Double(total)) * 100

        return MemoryInfo(
            totalBytes: total,
            usedBytes: used,
            freeBytes: available,
            activeBytes: active,
            inactiveBytes: inactive,
            wiredBytes: wired,
            compressedBytes: compressed,
            pressure: pressureLabel(usage),
            usagePercent: usage
        )
    }

    private static func vmStatistics() -> vm_statistics64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        return stats
    }

    private static func pressureLabel(_ usage: Double) -> String {
        if usage >= 85 { return L10n.tr("Memory Pressure High") }
        if usage >= 70 { return L10n.tr("Memory Pressure Medium") }
        return L10n.tr("Memory Pressure Low")
    }
}
