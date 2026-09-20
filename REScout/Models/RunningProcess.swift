import Foundation

struct RunningProcess: Identifiable, Hashable {
    var id: Int { pid }
    var pid: Int
    var name: String
    var path: String
    var bundleID: String
    var isApple: Bool

    static func loadApplications() -> [RunningProcess] {
        let raw = DOVCopyRunningApplications() as? [[String: Any]] ?? []
        return raw.compactMap { dict in
            let pid: Int
            if let n = dict["pid"] as? NSNumber { pid = n.intValue }
            else if let i = dict["pid"] as? Int { pid = i }
            else { return nil }
            return RunningProcess(
                pid: pid,
                name: dict["name"] as? String ?? "?",
                path: dict["path"] as? String ?? "",
                bundleID: dict["bundleID"] as? String ?? "",
                isApple: (dict["isApple"] as? NSNumber)?.boolValue
                    ?? (dict["isApple"] as? Bool)
                    ?? false
            )
        }
    }
}

enum ProcessKiller {
    static func kill(pid: Int) -> Result<Void, Error> {
        if let err = DOVKillPID(Int32(pid)) as String? {
            return .failure(NSError(domain: "Process", code: 1, userInfo: [NSLocalizedDescriptionKey: err]))
        }
        return .success(())
    }
}
