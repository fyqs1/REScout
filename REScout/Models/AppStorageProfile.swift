import Foundation
import UIKit

struct AppExtensionStorage: Identifiable, Hashable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var appexPath: String
    var dataPath: String
}

struct AppPathShortcut: Identifiable, Hashable {
    var id: String { path.isEmpty ? title : path }
    var title: String
    var path: String
    /// When false, show as informational missing row rather than browse link.
    var exists: Bool
}

struct AppStorageProfile {
    var dataPath: String = ""
    var dataNote: String = ""
    var dataShortcuts: [AppPathShortcut] = []
    var bundlePath: String = ""
    var bundleContainerPath: String = ""
    var bundleMetadataPath: String = ""
    var pluginsFolderPath: String = ""
    var groupContainers: [String: String] = [:]
    var declaredGroups: [String] = []
    var entitlementsReadable: Bool = false
    var extensions: [AppExtensionStorage] = []
    var mobileDocumentsPaths: [String] = []
    var keychainDBPath: String = "/var/Keychains/keychain-2.db"
    var keychainAccessGroups: [String] = []
    var icon: UIImage?

    var usesAppGroups: Bool {
        !declaredGroups.isEmpty || !groupContainers.isEmpty
    }

    var groupsExplicitlyUnused: Bool {
        entitlementsReadable && declaredGroups.isEmpty && groupContainers.isEmpty
    }

    static func load(for app: InstalledAppInfo) -> AppStorageProfile {
        var profile = AppStorageProfile()
        profile.bundlePath = app.bundlePath
        profile.bundleContainerPath = app.bundleContainerPath
        if profile.bundleContainerPath.isEmpty, app.bundlePath.lowercased().hasSuffix(".app") {
            profile.bundleContainerPath = (app.bundlePath as NSString).deletingLastPathComponent
        }

        var data = app.dataPath
        if data.isEmpty || !FileManager.default.fileExists(atPath: data) {
            data = DOVResolveDataContainerPath(app.bundleID, app.bundlePath) as String? ?? data
        }
        profile.dataPath = data
        if data.isEmpty {
            profile.dataNote = L10n.tr("Data Path Missing Hint")
        } else if !FileManager.default.fileExists(atPath: data) {
            profile.dataNote = L10n.tr("Data Path Unavailable Hint")
        }

        profile.dataShortcuts = Self.dataShortcuts(under: data)

        if let metaRoot = profile.bundleContainerPath.isEmpty ? nil : profile.bundleContainerPath {
            let meta = (metaRoot as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            if FileManager.default.fileExists(atPath: meta) {
                profile.bundleMetadataPath = meta
            }
        }

        let appBundle = app.bundlePath
        if !appBundle.isEmpty {
            let plugins = (appBundle as NSString).appendingPathComponent("PlugIns")
            if FileManager.default.fileExists(atPath: plugins) {
                profile.pluginsFolderPath = plugins
            }
        }

        let groupInfo = DOVResolveAppGroupInfo(app.bundleID, app.bundlePath) as? [String: Any] ?? [:]
        profile.groupContainers = groupInfo["containers"] as? [String: String] ?? [:]
        profile.declaredGroups = groupInfo["declaredGroups"] as? [String] ?? []
        if let n = groupInfo["entitlementsReadable"] as? NSNumber {
            profile.entitlementsReadable = n.boolValue
        } else if let b = groupInfo["entitlementsReadable"] as? Bool {
            profile.entitlementsReadable = b
        }

        let rawExt = DOVCopyExtensionContainersForAppBundle(app.bundlePath) as? [[String: Any]] ?? []
        profile.extensions = rawExt.compactMap { dict in
            guard let bid = dict["bundleID"] as? String, !bid.isEmpty else { return nil }
            return AppExtensionStorage(
                bundleID: bid,
                name: (dict["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? bid,
                appexPath: dict["appexPath"] as? String ?? "",
                dataPath: dict["dataPath"] as? String ?? ""
            )
        }

        profile.mobileDocumentsPaths = (DOVCopyMobileDocumentsPathsForBundleID(app.bundleID) as? [String]) ?? []
        profile.keychainAccessGroups = (DOVCopyKeychainAccessGroups(app.bundlePath, app.executable) as? [String]) ?? []

        if FileManager.default.fileExists(atPath: "/private/var/Keychains/keychain-2.db") {
            profile.keychainDBPath = "/var/Keychains/keychain-2.db"
        }

        if let icon = app.iconImage {
            profile.icon = icon
        } else if let data = DOVIconDataForBundleID(app.bundleID, app.bundlePath) as Data? {
            profile.icon = UIImage(data: data)
        }

        return profile
    }

    private static func dataShortcuts(under root: String) -> [AppPathShortcut] {
        guard !root.isEmpty else { return [] }
        let specs: [(String, String)] = [
            (L10n.tr("Data Shortcut Documents"), "Documents"),
            (L10n.tr("Data Shortcut Preferences"), "Library/Preferences"),
            (L10n.tr("Data Shortcut Caches"), "Library/Caches"),
            (L10n.tr("Data Shortcut App Support"), "Library/Application Support"),
            (L10n.tr("Data Shortcut Cookies"), "Library/Cookies"),
            (L10n.tr("Data Shortcut WebKit"), "Library/WebKit"),
            (L10n.tr("Data Shortcut Tmp"), "tmp"),
        ]
        let fm = FileManager.default
        return specs.map { title, rel in
            let path = (root as NSString).appendingPathComponent(rel)
            return AppPathShortcut(title: title, path: path, exists: fm.fileExists(atPath: path))
        }
    }
}
