import Foundation
import UIKit

enum AppRole: String {
    case user
    case system

    var badgeKey: String {
        switch self {
        case .user: return "Role User"
        case .system: return "Role System"
        }
    }
}

struct InstalledAppInfo: Identifiable, Hashable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var version: String
    var build: String
    var bundlePath: String
    /// Parent of `.app` (UUID install folder) when available.
    var bundleContainerPath: String
    var dataPath: String
    var type: String
    var role: AppRole
    var isSystem: Bool { role == .system }
    var executable: String
    var minimumOS: String
    var teamID: String
    var groupContainers: [String: String]
    var iconData: Data?

    var iconImage: UIImage? {
        AppIconCache.cached(for: bundleID.isEmpty ? bundlePath : bundleID)
    }

    static func from(dict: [String: Any]) -> InstalledAppInfo? {
        guard let bundleID = dict["bundleID"] as? String, !bundleID.isEmpty else { return nil }
        let groups = dict["groupContainers"] as? [String: String] ?? [:]
        let roleRaw = (dict["role"] as? String)?.lowercased()
        let role: AppRole = {
            if roleRaw == "system" { return .system }
            if roleRaw == "user" { return .user }
            if let b = dict["isSystem"] as? Bool { return b ? .system : .user }
            if let n = dict["isSystem"] as? NSNumber { return n.boolValue ? .system : .user }
            return .user
        }()

        let dataPath = dict["dataPath"] as? String ?? ""
        let bundlePath = dict["bundlePath"] as? String ?? ""
        var bundleContainer = dict["bundleContainerPath"] as? String ?? ""
        if bundleContainer.isEmpty, bundlePath.lowercased().hasSuffix(".app") {
            bundleContainer = (bundlePath as NSString).deletingLastPathComponent
        }

        return InstalledAppInfo(
            bundleID: bundleID,
            name: (dict["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? bundleID,
            version: dict["version"] as? String ?? "",
            build: dict["build"] as? String ?? "",
            bundlePath: bundlePath,
            bundleContainerPath: bundleContainer,
            dataPath: dataPath,
            type: dict["type"] as? String ?? "",
            role: role,
            executable: dict["executable"] as? String ?? "",
            minimumOS: dict["minimumOS"] as? String ?? "",
            teamID: dict["teamID"] as? String ?? "",
            groupContainers: groups,
            iconData: dict["iconData"] as? Data
        )
    }
}

enum InstalledAppsCollector {
    static func loadAll() -> [InstalledAppInfo] {
        let raw = DOVCopyInstalledApplications() as? [[String: Any]] ?? []
        return raw.compactMap(InstalledAppInfo.from(dict:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
