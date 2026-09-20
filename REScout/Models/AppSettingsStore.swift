import Foundation
import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case chinese

    var id: String { rawValue }

    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .chinese: return "zh-Hans"
        }
    }

    var titleKey: String {
        switch self {
        case .system: return "Language System"
        case .english: return "Language English"
        case .chinese: return "Language Chinese"
        }
    }
}

enum OverviewSectionID: String, CaseIterable, Identifiable, Codable {
    case system
    case cpu
    case memory
    case storage
    case battery
    case network
    case jailbreak
    case activityLog

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .system: return "Section System"
        case .cpu: return "Section CPU"
        case .memory: return "Section Memory"
        case .storage: return "Section Storage"
        case .battery: return "Section Battery"
        case .network: return "Section Network"
        case .jailbreak: return "Section Jailbreak"
        case .activityLog: return "Section Activity Log"
        }
    }

    var icon: String {
        switch self {
        case .system: return "iphone"
        case .cpu: return "cpu"
        case .memory: return "cube"
        case .storage: return "internaldrive"
        case .battery: return "battery.100"
        case .network: return "wifi"
        case .jailbreak: return "lock.open"
        case .activityLog: return "list.bullet.rectangle"
        }
    }

    static var defaultOrder: [OverviewSectionID] { Array(allCases) }
}

@MainActor
final class AppSettingsStore: ObservableObject {
    static let shared = AppSettingsStore()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var showSystemApps: Bool {
        didSet { UserDefaults.standard.set(showSystemApps, forKey: Keys.showSystemApps) }
    }

    /// When false (default), overview only refreshes on open / manual pull.
    @Published var autoRefreshOverview: Bool {
        didSet { UserDefaults.standard.set(autoRefreshOverview, forKey: Keys.autoRefreshOverview) }
    }

    @Published var overviewOrder: [OverviewSectionID] {
        didSet {
            let raw = overviewOrder.map(\.rawValue)
            UserDefaults.standard.set(raw, forKey: Keys.overviewOrder)
        }
    }

    /// Bumps when language changes so views re-resolve strings.
    @Published private(set) var localizationEpoch: Int = 0

    private enum Keys {
        static let language = "settings.language"
        static let showSystemApps = "settings.showSystemApps"
        static let overviewOrder = "settings.overviewOrder"
        static let autoRefreshOverview = "settings.autoRefreshOverview"
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Keys.language) ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: raw) ?? .system
        showSystemApps = UserDefaults.standard.object(forKey: Keys.showSystemApps) as? Bool ?? false
        // Default: manual refresh for smoother scrolling.
        if UserDefaults.standard.object(forKey: Keys.autoRefreshOverview) == nil {
            autoRefreshOverview = false
        } else {
            autoRefreshOverview = UserDefaults.standard.bool(forKey: Keys.autoRefreshOverview)
        }
        overviewOrder = Self.loadOrder()
    }

    private static func loadOrder() -> [OverviewSectionID] {
        let stored = UserDefaults.standard.stringArray(forKey: Keys.overviewOrder) ?? []
        var order = stored.compactMap(OverviewSectionID.init(rawValue:))
        for id in OverviewSectionID.defaultOrder where !order.contains(id) {
            order.append(id)
        }
        // Drop unknown / duplicates already handled
        return order.isEmpty ? OverviewSectionID.defaultOrder : order
    }

    func setLanguage(_ value: AppLanguage) {
        language = value
        localizationEpoch &+= 1
    }

    func moveOverview(from source: IndexSet, to destination: Int) {
        overviewOrder.move(fromOffsets: source, toOffset: destination)
    }

    func resetOverviewOrder() {
        overviewOrder = OverviewSectionID.defaultOrder
    }

    var resolvedLocale: Locale {
        if let id = language.localeIdentifier {
            return Locale(identifier: id)
        }
        return Locale.current
    }

    var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
