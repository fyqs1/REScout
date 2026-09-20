import Foundation
import UIKit

struct REDataHotspot: Identifiable, Hashable {
    var id: String { path }
    var title: String
    var path: String
    var sizeBytes: UInt64
    var modified: Date?
}

struct AppREProfile {
    var executablePath: String = ""
    var cryptid: Int = -1
    var encrypted: Bool = false
    var architectures: [String] = []
    var uuid: String = ""
    var machoError: String = ""
    var entitlements: [String: Any] = [:]
    var entitlementsReadable: Bool = false
    var urlSchemes: [String] = []
    var querySchemes: [String] = []
    var backgroundModes: [String] = []
    var frameworks: [String] = []
    var plugins: [String] = []
    var dylibs: [String] = []
    var atsAllowsArbitraryLoads: Bool?
    var atsSummary: String = ""
    var signingTeam: String = ""
    var signingAppID: String = ""
    var provisionExists: Bool = false
    var provisionName: String = ""
    var provisionTeam: String = ""
    var provisionTeamID: String = ""
    var provisionExpires: String = ""
    var provisionUUID: String = ""
    var provisionPath: String = ""
    var provisionError: String = ""
    var prefsPath: String = ""
    var prefsKeys: [String] = []
    var dataHotspots: [REDataHotspot] = []
    var runningPIDs: [Int] = []

    var gateBlocked: Bool { encrypted || cryptid == 1 }

    var gateSummaryKey: String {
        if !machoError.isEmpty { return "RE Gate Error" }
        if executablePath.isEmpty { return "RE Gate Missing Binary" }
        if gateBlocked { return "RE Gate Cryptid Blocked" }
        return "RE Gate Clear"
    }

    var bundlePathResolved: String = ""

    static func load(for app: InstalledAppInfo, storage: AppStorageProfile) -> AppREProfile {
        var p = AppREProfile()
        let bundle = storage.bundlePath.isEmpty ? app.bundlePath : storage.bundlePath
        p.bundlePathResolved = bundle
        let execName = app.executable
        if !bundle.isEmpty, !execName.isEmpty {
            p.executablePath = (bundle as NSString).appendingPathComponent(execName)
        } else if !bundle.isEmpty {
            if let info = NSDictionary(contentsOfFile: (bundle as NSString).appendingPathComponent("Info.plist")),
               let name = info["CFBundleExecutable"] as? String, !name.isEmpty {
                p.executablePath = (bundle as NSString).appendingPathComponent(name)
            }
        }

        let gate = DOVCopyMachOGate(p.executablePath) as? [String: Any] ?? [:]
        p.cryptid = (gate["cryptid"] as? NSNumber)?.intValue ?? (gate["cryptid"] as? Int) ?? -1
        p.encrypted = (gate["encrypted"] as? NSNumber)?.boolValue ?? (gate["encrypted"] as? Bool) ?? false
        p.architectures = gate["architectures"] as? [String] ?? []
        p.uuid = gate["uuid"] as? String ?? ""
        p.machoError = gate["error"] as? String ?? ""

        if let ents = DOVCopyEntitlementsForApp(bundle, execName) as? [String: Any] {
            p.entitlements = ents
            p.entitlementsReadable = true
            p.signingAppID = ents["application-identifier"] as? String ?? ""
            p.signingTeam = ents["com.apple.developer.team-identifier"] as? String ?? ""
            if p.signingTeam.isEmpty, let appID = ents["application-identifier"] as? String,
               let team = appID.split(separator: ".").first {
                p.signingTeam = String(team)
            }
        }

        let infoPath = (bundle as NSString).appendingPathComponent("Info.plist")
        if let info = NSDictionary(contentsOfFile: infoPath) as? [String: Any] {
            p.urlSchemes = Self.extractURLSchemes(info)
            p.querySchemes = info["LSApplicationQueriesSchemes"] as? [String] ?? []
            p.backgroundModes = info["UIBackgroundModes"] as? [String] ?? []
            Self.fillATS(from: info, into: &p)
        }

        let fm = FileManager.default
        let fwRoot = (bundle as NSString).appendingPathComponent("Frameworks")
        if let kids = try? fm.contentsOfDirectory(atPath: fwRoot) {
            p.frameworks = kids.filter { $0.hasSuffix(".framework") || $0.hasSuffix(".dylib") }.sorted()
            p.dylibs = kids.filter { $0.hasSuffix(".dylib") }.sorted()
        }
        let plugRoot = (bundle as NSString).appendingPathComponent("PlugIns")
        if let kids = try? fm.contentsOfDirectory(atPath: plugRoot) {
            p.plugins = kids.filter { $0.hasSuffix(".appex") }.sorted()
        }

        let prov = DOVCopyMobileProvisionSummary(bundle) as? [String: Any] ?? [:]
        p.provisionExists = (prov["exists"] as? NSNumber)?.boolValue ?? false
        p.provisionPath = prov["path"] as? String ?? ""
        p.provisionName = prov["name"] as? String ?? ""
        p.provisionTeam = prov["teamName"] as? String ?? ""
        p.provisionTeamID = prov["teamIdentifier"] as? String ?? ""
        p.provisionExpires = prov["expirationDate"] as? String ?? ""
        p.provisionUUID = prov["uuid"] as? String ?? ""
        p.provisionError = prov["error"] as? String ?? ""

        Self.fillPrefs(bundleID: app.bundleID, dataPath: storage.dataPath, into: &p)
        p.dataHotspots = Self.scanHotspots(dataPath: storage.dataPath)
        p.runningPIDs = Self.runningPIDs(for: app.bundleID)

        return p
    }

    private static func fillATS(from info: [String: Any], into p: inout AppREProfile) {
        guard let ats = info["NSAppTransportSecurity"] as? [String: Any] else {
            p.atsSummary = L10n.tr("RE ATS Default")
            return
        }
        if let allows = ats["NSAllowsArbitraryLoads"] as? Bool {
            p.atsAllowsArbitraryLoads = allows
            p.atsSummary = allows ? L10n.tr("RE ATS Open") : L10n.tr("RE ATS Restricted")
        } else if let allows = ats["NSAllowsArbitraryLoads"] as? NSNumber {
            p.atsAllowsArbitraryLoads = allows.boolValue
            p.atsSummary = allows.boolValue ? L10n.tr("RE ATS Open") : L10n.tr("RE ATS Restricted")
        } else {
            p.atsSummary = L10n.tr("RE ATS Custom")
        }
        if let domains = ats["NSExceptionDomains"] as? [String: Any], !domains.isEmpty {
            p.atsSummary += " · \(domains.count) " + L10n.tr("RE ATS Exceptions")
        }
    }

    private static func fillPrefs(bundleID: String, dataPath: String, into p: inout AppREProfile) {
        guard !dataPath.isEmpty, !bundleID.isEmpty else { return }
        let prefsDir = (dataPath as NSString).appendingPathComponent("Library/Preferences")
        let path = (prefsDir as NSString).appendingPathComponent("\(bundleID).plist")
        p.prefsPath = path
        guard FileManager.default.fileExists(atPath: path),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            return
        }
        p.prefsKeys = dict.keys.sorted()
    }

    private static func scanHotspots(dataPath: String) -> [REDataHotspot] {
        guard !dataPath.isEmpty else { return [] }
        let fm = FileManager.default
        let roots: [(String, String)] = [
            (L10n.tr("Data Shortcut Documents"), "Documents"),
            (L10n.tr("Data Shortcut Preferences"), "Library/Preferences"),
            (L10n.tr("Data Shortcut Caches"), "Library/Caches"),
            (L10n.tr("Data Shortcut App Support"), "Library/Application Support"),
            (L10n.tr("Data Shortcut Tmp"), "tmp"),
        ]
        var folderStats: [REDataHotspot] = []
        var fileCandidates: [REDataHotspot] = []

        for (title, rel) in roots {
            let path = (dataPath as NSString).appendingPathComponent(rel)
            guard fm.fileExists(atPath: path) else { continue }
            let size = directorySize(path, maxDepth: 3, maxNodes: 400)
            let mtime = modificationDate(path)
            folderStats.append(REDataHotspot(title: title, path: path, sizeBytes: size, modified: mtime))

            if let kids = try? fm.contentsOfDirectory(atPath: path) {
                for name in kids.prefix(40) {
                    let child = (path as NSString).appendingPathComponent(name)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: child, isDirectory: &isDir), !isDir.boolValue else { continue }
                    let attrs = try? fm.attributesOfItem(atPath: child)
                    let sz = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
                    let mod = attrs?[.modificationDate] as? Date
                    if sz > 64 * 1024 {
                        fileCandidates.append(
                            REDataHotspot(title: name, path: child, sizeBytes: sz, modified: mod)
                        )
                    }
                }
            }
        }

        let topFiles = fileCandidates.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(8)
        return folderStats.sorted { $0.sizeBytes > $1.sizeBytes } + Array(topFiles)
    }

    private static func directorySize(_ path: String, maxDepth: Int, maxNodes: Int) -> UInt64 {
        let fm = FileManager.default
        var total: UInt64 = 0
        var nodes = 0
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        while let rel = enumerator.nextObject() as? String {
            nodes += 1
            if nodes > maxNodes { break }
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            let full = (path as NSString).appendingPathComponent(rel)
            let attrs = try? fm.attributesOfItem(atPath: full)
            if (attrs?[.type] as? FileAttributeType) == .typeRegular {
                total += (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
            }
        }
        return total
    }

    private static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private static func runningPIDs(for bundleID: String) -> [Int] {
        guard !bundleID.isEmpty else { return [] }
        let raw = DOVCopyRunningApplications() as? [[String: Any]] ?? []
        return raw.compactMap { dict in
            guard (dict["bundleID"] as? String) == bundleID else { return nil }
            if let n = dict["pid"] as? NSNumber { return n.intValue }
            return dict["pid"] as? Int
        }
    }

    private static func extractURLSchemes(_ info: [String: Any]) -> [String] {
        guard let types = info["CFBundleURLTypes"] as? [[String: Any]] else { return [] }
        var schemes: [String] = []
        for t in types {
            if let arr = t["CFBundleURLSchemes"] as? [String] {
                schemes.append(contentsOf: arr)
            }
        }
        return schemes
    }

    var notableEntitlementKeys: [String] {
        let keys = entitlements.keys.sorted()
        let interesting = [
            "get-task-allow",
            "platform-application",
            "com.apple.security.application-groups",
            "keychain-access-groups",
            "com.apple.developer.networking.networkextension",
            "com.apple.developer.networking.vpn.api",
            "com.apple.developer.team-identifier",
            "application-identifier",
            "com.apple.private.security.no-sandbox",
            "aps-environment",
            "com.apple.developer.associated-domains",
            "com.apple.security.exception.files.absolute-path.read-write",
            "com.apple.security.exception.files.absolute-path.read-only"
        ]
        let hit = keys.filter { k in interesting.contains(where: { k == $0 || k.hasPrefix($0) }) }
        return hit.isEmpty ? Array(keys.prefix(12)) : hit
    }
}

enum RECaseExporter {
    /// Neutral profile pack (identity / macho / entitlements / paths) — not tied to any Mac toolchain.
    static func makeNeutralPack(
        app: InstalledAppInfo,
        storage: AppStorageProfile,
        re: AppREProfile
    ) -> [String: Any] {
        let iso = ISO8601DateFormatter().string(from: Date())
        let bundlePath = re.bundlePathResolved.isEmpty
            ? (storage.bundlePath.isEmpty ? app.bundlePath : storage.bundlePath)
            : re.bundlePathResolved
        let execName = app.executable.isEmpty
            ? (re.executablePath as NSString).lastPathComponent
            : app.executable

        var entsSummary: [String: Any] = [:]
        for k in re.notableEntitlementKeys {
            entsSummary[k] = stringify(re.entitlements[k])
        }

        let encryptionLabel = re.gateBlocked ? "encrypted" : "clear"
        let essentials = essentialsText(
            name: app.name,
            bundleID: app.bundleID,
            appPath: bundlePath,
            executablePath: re.executablePath,
            cryptid: re.cryptid,
            encrypted: re.gateBlocked
        )

        return [
            "format": "rescout-profile-1",
            "tool": "REScout",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1.0",
            "exportedAt": iso,
            "essentials_text": essentials,
            "identity": [
                "name": app.name,
                "bundle_id": app.bundleID,
                "executable": execName,
                "app_path": bundlePath,
                "executable_path": re.executablePath,
                "version": app.version,
                "build": app.build,
                "team_id": app.teamID,
                "minimum_os": app.minimumOS,
                "role": app.role.rawValue,
                "running_pids": re.runningPIDs
            ],
            "macho": [
                "cryptid": re.cryptid,
                "encryption": encryptionLabel,
                "encrypted": re.gateBlocked,
                "architectures": re.architectures,
                "uuid": re.uuid,
                "error": re.machoError
            ],
            "entitlements": [
                "readable": re.entitlementsReadable,
                "notable": entsSummary
            ],
            "paths": [
                "data": storage.dataPath,
                "groups": storage.groupContainers,
                "prefs": re.prefsPath,
                "plugins_folder": storage.pluginsFolderPath,
                "mobile_documents": storage.mobileDocumentsPaths
            ],
            "signing": [
                "application_identifier": re.signingAppID,
                "team_identifier": re.signingTeam.isEmpty ? re.provisionTeamID : re.signingTeam,
                "provision_name": re.provisionName,
                "provision_expires": re.provisionExpires
            ],
            "info_plist": [
                "url_schemes": re.urlSchemes,
                "queries_schemes": re.querySchemes,
                "background_modes": re.backgroundModes,
                "ats": re.atsSummary
            ],
            "bundle_contents": [
                "frameworks": re.frameworks,
                "plugins": re.plugins
            ],
            "note": re.gateBlocked
                ? "Main binary appears encrypted; prefer inventory only."
                : "Main binary does not appear encrypted."
        ]
    }

    static func essentialsText(
        name: String,
        bundleID: String,
        appPath: String,
        executablePath: String,
        cryptid: Int,
        encrypted: Bool
    ) -> String {
        let status = encrypted ? "encrypted" : "clear"
        let crypt = cryptid >= 0 ? "\(cryptid)" : "?"
        return """
        name: \(name)
        bundle_id: \(bundleID)
        app_path: \(appPath.isEmpty ? "—" : appPath)
        executable_path: \(executablePath.isEmpty ? "—" : executablePath)
        encryption: \(status) (cryptid: \(crypt))
        """
    }

    static func essentialsText(from pack: [String: Any]) -> String {
        if let s = pack["essentials_text"] as? String, !s.isEmpty { return s }
        let id = pack["identity"] as? [String: Any] ?? [:]
        let macho = pack["macho"] as? [String: Any] ?? [:]
        let cryptid = (macho["cryptid"] as? NSNumber)?.intValue ?? (macho["cryptid"] as? Int) ?? -1
        let encrypted = (macho["encrypted"] as? Bool)
            ?? ((macho["encrypted"] as? NSNumber)?.boolValue ?? false)
        return essentialsText(
            name: id["name"] as? String ?? "",
            bundleID: id["bundle_id"] as? String ?? "",
            appPath: id["app_path"] as? String ?? "",
            executablePath: id["executable_path"] as? String ?? "",
            cryptid: cryptid,
            encrypted: encrypted
        )
    }

    static func readmeText(from pack: [String: Any]) -> String {
        let essentials = essentialsText(from: pack)
        let note = pack["note"] as? String ?? ""
        return """
        REScout App Profile
        -------------------
        \(essentials)

        \(note)

        This file is a neutral inventory export (identity, binary status, entitlements, paths).
        """
    }

    static func jsonData(from pack: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: pack, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Legacy helpers kept for older saved files

    static func makeCase(
        app: InstalledAppInfo,
        storage: AppStorageProfile,
        re: AppREProfile,
        note: String = "",
        jailbreak: String = "rootless"
    ) -> [String: Any] {
        _ = note
        _ = jailbreak
        return makeNeutralPack(app: app, storage: storage, re: re)
    }

    static func summaryText(from caseDict: [String: Any]) -> String {
        readmeText(from: caseDict)
    }

    static func initCommand(from caseDict: [String: Any]) -> String {
        essentialsText(from: caseDict)
    }

    private static func stringify(_ value: Any?) -> Any {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n
        case let a as [Any]: return a.map { stringify($0) }
        case let d as [String: Any]: return d.mapValues { stringify($0) }
        case let a as NSArray: return a.map { stringify($0) }
        case let d as NSDictionary:
            var out: [String: Any] = [:]
            d.enumerateKeysAndObjects { k, v, _ in
                if let ks = k as? String { out[ks] = stringify(v) }
            }
            return out
        default:
            if let value { return "\(value)" }
            return NSNull()
        }
    }
}
