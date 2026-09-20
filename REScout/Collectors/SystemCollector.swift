import Foundation
import UIKit
import AVFoundation
import CoreTelephony
import AdSupport
import AppTrackingTransparency

enum DeviceModelMap {
    /// Common marketing names. Unknown identifiers fall back to the raw machine id.
    static let map: [String: String] = [
        "iPhone8,1": "iPhone 6s", "iPhone8,2": "iPhone 6s Plus", "iPhone8,4": "iPhone SE (1st)",
        "iPhone9,1": "iPhone 7", "iPhone9,3": "iPhone 7", "iPhone9,2": "iPhone 7 Plus", "iPhone9,4": "iPhone 7 Plus",
        "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8", "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
        "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
        "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2nd)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3rd)",
        "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,5": "iPhone 16e",
        "iPad13,1": "iPad Air (5th)", "iPad13,2": "iPad Air (5th)",
        "iPad13,16": "iPad Air (5th)", "iPad13,17": "iPad Air (5th)",
        "iPad14,1": "iPad mini (6th)", "iPad14,2": "iPad mini (6th)",
        "iPad14,3": "iPad Pro 11 (4th)", "iPad14,4": "iPad Pro 11 (4th)",
        "iPad14,5": "iPad Pro 12.9 (6th)", "iPad14,6": "iPad Pro 12.9 (6th)",
        "iPad16,3": "iPad Pro 11 (M4)", "iPad16,4": "iPad Pro 11 (M4)",
        "iPad16,5": "iPad Pro 13 (M4)", "iPad16,6": "iPad Pro 13 (M4)",
        "arm64": "Simulator"
    ]

    static func marketingName(for machine: String) -> String {
        map[machine] ?? machine
    }

    static func cpuName(for machine: String) -> String {
        switch machine {
        case "iPhone8,1", "iPhone8,2", "iPhone8,4": return "Apple A9"
        case "iPhone9,1", "iPhone9,2", "iPhone9,3", "iPhone9,4": return "Apple A10 Fusion"
        case "iPhone10,1", "iPhone10,2", "iPhone10,3", "iPhone10,4", "iPhone10,5", "iPhone10,6": return "Apple A11 Bionic"
        case "iPhone11,2", "iPhone11,4", "iPhone11,6", "iPhone11,8": return "Apple A12 Bionic"
        case "iPhone12,1", "iPhone12,3", "iPhone12,5", "iPhone12,8": return "Apple A13 Bionic"
        case "iPhone13,1", "iPhone13,2", "iPhone13,3", "iPhone13,4": return "Apple A14 Bionic"
        case "iPhone14,2", "iPhone14,3", "iPhone14,4", "iPhone14,5", "iPhone14,6": return "Apple A15 Bionic"
        case "iPhone14,7", "iPhone14,8": return "Apple A15 Bionic"
        case "iPhone15,2", "iPhone15,3": return "Apple A16 Bionic"
        case "iPhone15,4", "iPhone15,5": return "Apple A16 Bionic"
        case "iPhone16,1", "iPhone16,2": return "Apple A17 Pro"
        case "iPhone17,1", "iPhone17,2": return "Apple A18 Pro"
        case "iPhone17,3", "iPhone17,4", "iPhone17,5": return "Apple A18"
        case "iPad16,3", "iPad16,4", "iPad16,5", "iPad16,6": return "Apple M4"
        case "iPad14,3", "iPad14,4", "iPad14,5", "iPad14,6": return "Apple M2"
        default: return machine
        }
    }
}

enum SystemCollector {
    static func collect() -> SystemInfo {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let machine = machineIdentifier()
        let screen = UIScreen.main
        let native = screen.nativeBounds.size
        let brightness = String(format: "%.0f%%", screen.brightness * 100)
        let volume: String = {
            // Do not activate the audio session — that prompts for microphone.
            let session = AVAudioSession.sharedInstance()
            return String(format: "%.0f%%", session.outputVolume * 100)
        }()

        return SystemInfo(
            deviceName: device.name,
            marketingModel: DeviceModelMap.marketingName(for: machine),
            machineIdentifier: machine,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            buildNumber: buildNumber(),
            uptimeDescription: Formatters.uptime(seconds: ProcessInfo.processInfo.systemUptime),
            thermalState: thermalLabel(ProcessInfo.processInfo.thermalState),
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            screenResolution: String(format: "%.0f × %.0f", native.width, native.height),
            screenScale: String(format: "@%.0fx", screen.scale),
            brightness: brightness,
            volume: volume,
            carrier: carrierName(),
            idfv: device.identifierForVendor?.uuidString ?? "—",
            idfa: idfaValue(),
            trackingStatus: trackingStatusLabel()
        )
    }

    static func requestTrackingAuthorizationIfNeeded() {
        if #available(iOS 14, *) {
            let status = ATTrackingManager.trackingAuthorizationStatus
            guard status == .notDetermined else { return }
            DispatchQueue.main.async {
                ActivityLogStore.log(
                    .info,
                    category: L10n.tr("Log Category Permission"),
                    message: L10n.tr("Log Request Tracking")
                )
                ATTrackingManager.requestTrackingAuthorization { newStatus in
                    ActivityLogStore.log(
                        .info,
                        category: L10n.tr("Log Category Permission"),
                        message: String(format: L10n.tr("Log Tracking Status Format"), "\(newStatus.rawValue)")
                    )
                }
            }
        }
    }

    private static func trackingStatusLabel() -> String {
        if #available(iOS 14, *) {
            switch ATTrackingManager.trackingAuthorizationStatus {
            case .notDetermined: return L10n.tr("Tracking Not Determined")
            case .restricted: return L10n.tr("Tracking Restricted")
            case .denied: return L10n.tr("Tracking Denied")
            case .authorized: return L10n.tr("Tracking Authorized")
            @unknown default: return "—"
            }
        }
        return L10n.tr("Tracking Authorized")
    }

    private static func idfaValue() -> String {
        if #available(iOS 14, *) {
            let status = ATTrackingManager.trackingAuthorizationStatus
            guard status == .authorized else {
                return ""
            }
        }
        let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        if idfa == "00000000-0000-0000-0000-000000000000" {
            return ""
        }
        return idfa
    }

    private static func carrierName() -> String {
        let info = CTTelephonyNetworkInfo()
        if let providers = info.serviceSubscriberCellularProviders {
            let names = providers.values.compactMap { $0.carrierName }.filter { !$0.isEmpty }
            if !names.isEmpty {
                return Array(Set(names)).sorted().joined(separator: ", ")
            }
        }
        if let name = info.subscriberCellularProvider?.carrierName, !name.isEmpty {
            return name
        }
        return ""
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

    private static func buildNumber() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        let value = String(cString: buffer)
        return value.isEmpty ? "—" : value
    }

    private static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return L10n.tr("Thermal Nominal")
        case .fair: return L10n.tr("Thermal Fair")
        case .serious: return L10n.tr("Thermal Serious")
        case .critical: return L10n.tr("Thermal Critical")
        @unknown default: return "—"
        }
    }
}
