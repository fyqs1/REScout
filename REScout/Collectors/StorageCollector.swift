import Foundation

enum StorageCollector {
    static func collect() -> StorageInfo {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ])
        let total = UInt64(values?.volumeTotalCapacity ?? 0)
        let free = UInt64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        let used = total > free ? total - free : 0
        let usage = total == 0 ? 0 : (Double(used) / Double(total)) * 100
        return StorageInfo(totalBytes: total, usedBytes: used, freeBytes: free, usagePercent: usage)
    }
}
