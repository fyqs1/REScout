import Foundation

enum L10n {
    static var systemRestricted: String { tr("System Restricted") }

    static func tr(_ key: String) -> String {
        let lang = UserDefaults.standard.string(forKey: "settings.language") ?? AppLanguage.system.rawValue
        let mode = AppLanguage(rawValue: lang) ?? .system
        if let id = mode.localeIdentifier,
           let path = Bundle.main.path(forResource: id, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
        }
        return NSLocalizedString(key, comment: "")
    }
}

enum Formatters {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
    }

    static func percent(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", value)
    }

    static func bitsPerSecond(_ value: Double) -> String {
        if value < 1024 { return String(format: "%.0f B/s", value) }
        if value < 1024 * 1024 { return String(format: "%.1f KB/s", value / 1024) }
        if value < 1024 * 1024 * 1024 { return String(format: "%.2f MB/s", value / 1024 / 1024) }
        return String(format: "%.2f GB/s", value / 1024 / 1024 / 1024)
    }

    static func uptime(seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if days > 0 {
            return String(format: "%dd %dh %dm %ds", days, hours, minutes, secs)
        }
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, secs)
        }
        if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        }
        return String(format: "%ds", secs)
    }
}
