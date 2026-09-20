import Foundation
import UIKit

enum BatteryCollector {
    static func collect() -> BatteryInfo {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        let percent: Int? = level < 0 ? nil : Int((level * 100).rounded())
        let state: String = {
            switch device.batteryState {
            case .charging: return L10n.tr("Battery Charging")
            case .full: return L10n.tr("Battery Full")
            case .unplugged: return L10n.tr("Battery Unplugged")
            case .unknown: return L10n.tr("Battery Unknown")
            @unknown default: return L10n.tr("Battery Unknown")
            }
        }()

        var extras = DOVBatteryExtras()
        let enhanced = DOVCopyBatteryExtras(&extras) == 1

        let health: String = {
            if enhanced, extras.has_health != 0 {
                return "\(extras.health_percent)%"
            }
            return ""
        }()
        let voltage: String = {
            if enhanced, extras.has_voltage != 0 {
                return String(format: "%.3f V", Double(extras.voltage_mV) / 1000.0)
            }
            return ""
        }()
        let amperage: String = {
            if enhanced, extras.has_amperage != 0 {
                return "\(extras.amperage_mA) mA"
            }
            return ""
        }()
        let temperature: String = {
            if enhanced, extras.has_temperature != 0 {
                return String(format: "%.1f ℃", extras.temperature_C)
            }
            return ""
        }()
        let capacity: String = {
            if enhanced, extras.has_design_capacity != 0, extras.has_max_capacity != 0 {
                return "\(extras.max_capacity_mAh) / \(extras.design_capacity_mAh) mAh"
            }
            if enhanced, extras.has_design_capacity != 0 {
                return "\(extras.design_capacity_mAh) mAh"
            }
            if enhanced, extras.has_max_capacity != 0 {
                return "\(extras.max_capacity_mAh) mAh"
            }
            return ""
        }()
        let cycles: String = {
            if enhanced, extras.has_cycle_count != 0 {
                return "\(extras.cycle_count)"
            }
            return ""
        }()
        let serial: String = {
            if enhanced, extras.has_serial != 0 {
                return withUnsafePointer(to: extras.serial) {
                    $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: extras.serial)) {
                        String(cString: $0)
                    }
                }
            }
            return ""
        }()

        return BatteryInfo(
            levelPercent: percent,
            state: state,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            health: health,
            voltage: voltage,
            amperage: amperage,
            temperature: temperature,
            capacity: capacity,
            cycleCount: cycles,
            serial: serial
        )
    }
}
