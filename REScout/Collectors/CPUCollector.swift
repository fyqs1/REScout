import Foundation
import Darwin

enum CPUCollector {
    private static var previous: processor_info_array_t?
    private static var previousCount: mach_msg_type_number_t = 0
    private static var previousCoreCount: natural_t = 0

    static func collect() -> CPUInfo {
        let machine = machineIdentifier()
        let usage = cpuUsage()
        let cores = ProcessInfo.processInfo.processorCount
        let active = ProcessInfo.processInfo.activeProcessorCount
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif

        let freq = cpuFrequencies()

        return CPUInfo(
            usagePercent: usage.used,
            idlePercent: usage.idle,
            coreCount: cores,
            activeCoreCount: active,
            architecture: arch,
            cpuName: DeviceModelMap.cpuName(for: machine),
            currentFrequency: freq.current,
            maxFrequency: freq.max
        )
    }

    private static func machineIdentifier() -> String {
        var uts = utsname()
        uname(&uts)
        return withUnsafePointer(to: &uts.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    private static func cpuFrequencies() -> (current: String, max: String) {
        let currentHz = sysctlUInt64("hw.cpufrequency")
            ?? sysctlUInt64("hw.cpufrequency_min")
        let maxHz = sysctlUInt64("hw.cpufrequency_max")
            ?? sysctlUInt64("hw.cpufrequency")

        func format(_ hz: UInt64?) -> String {
            guard let hz, hz > 0 else { return "" }
            let mhz = Double(hz) / 1_000_000.0
            if mhz >= 1000 {
                return String(format: "%.2f GHz", mhz / 1000.0)
            }
            return String(format: "%.0f MHz", mhz)
        }
        return (format(currentHz), format(maxHz))
    }

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var size = MemoryLayout<UInt64>.size
        var value: UInt64 = 0
        let result = sysctlbyname(name, &value, &size, nil, 0)
        return result == 0 ? value : nil
    }

    private static func cpuUsage() -> (used: Double, idle: Double) {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else {
            return (0, 100)
        }

        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        var totalUser: Double = 0
        var totalSystem: Double = 0
        var totalIdle: Double = 0
        var totalNice: Double = 0

        if let previous, previousCoreCount == cpuCount {
            for i in 0..<Int(cpuCount) {
                let offset = Int(CPU_STATE_MAX) * i
                let user = Double(cpuInfo[offset + Int(CPU_STATE_USER)] - previous[offset + Int(CPU_STATE_USER)])
                let system = Double(cpuInfo[offset + Int(CPU_STATE_SYSTEM)] - previous[offset + Int(CPU_STATE_SYSTEM)])
                let idle = Double(cpuInfo[offset + Int(CPU_STATE_IDLE)] - previous[offset + Int(CPU_STATE_IDLE)])
                let nice = Double(cpuInfo[offset + Int(CPU_STATE_NICE)] - previous[offset + Int(CPU_STATE_NICE)])
                totalUser += user
                totalSystem += system
                totalIdle += idle
                totalNice += nice
            }
        }

        let copySize = Int(cpuInfoCount)
        let copy = UnsafeMutablePointer<integer_t>.allocate(capacity: copySize)
        copy.initialize(from: cpuInfo, count: copySize)
        if let previous {
            previous.deallocate()
        }
        previous = copy
        previousCount = cpuInfoCount
        previousCoreCount = cpuCount

        let total = totalUser + totalSystem + totalIdle + totalNice
        guard total > 0 else { return (0, 100) }
        let used = ((totalUser + totalSystem + totalNice) / total) * 100
        let idle = (totalIdle / total) * 100
        return (min(max(used, 0), 100), min(max(idle, 0), 100))
    }
}
