import Foundation

/// Locates Files.app "On My iPhone" → File Provider Storage.
enum OnMyiPhoneLocator {
    static let appGroupBase = "/var/mobile/Containers/Shared/AppGroup"
    static let localStorageID = "group.com.apple.FileProvider.LocalStorage"

    /// Returns the directory that maps to Files → 我的 iPhone, if found.
    static func resolvePath() -> String? {
        let fm = FileManager.default
        guard let uuids = try? fm.contentsOfDirectory(atPath: appGroupBase) else {
            return nil
        }

        var fallback: String?
        for uuid in uuids {
            let groupDir = (appGroupBase as NSString).appendingPathComponent(uuid)
            let storage = (groupDir as NSString).appendingPathComponent("File Provider Storage")
            guard pathLooksUsable(storage) else { continue }

            if matchesLocalStorage(groupDir: groupDir) {
                return storage
            }
            if fallback == nil {
                fallback = storage
            }
        }
        return fallback
    }

    private static func matchesLocalStorage(groupDir: String) -> Bool {
        let candidates = [
            (groupDir as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist"),
            (groupDir as NSString).appendingPathComponent("Library/Preferences/group.com.apple.FileProvider.LocalStorage.plist")
        ]
        for plistPath in candidates {
            guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else { continue }
            let keys = ["MCMMetadataIdentifier", "MCMMetadataInfoIdentifier", "Identifier"]
            for key in keys {
                if let value = dict[key] as? String, value.contains("FileProvider.LocalStorage") {
                    return true
                }
            }
        }
        let storage = (groupDir as NSString).appendingPathComponent("File Provider Storage")
        for name in ["Downloads", ".Trash"] {
            let p = (storage as NSString).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: p) {
                return true
            }
        }
        return false
    }

    private static func pathLooksUsable(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return true
        }
        return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }
}
