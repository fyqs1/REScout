import Foundation
import Combine

struct RECaseHistoryItem: Identifiable, Codable, Equatable {
    var id: String { bundleID + "|" + exportedAt }
    var bundleID: String
    var name: String
    var executablePath: String
    var bundlePath: String
    var cryptid: Int
    var gateBlocked: Bool
    var exportedAt: String
    var jsonFileName: String
    /// Four-piece essentials text for quick copy / preview header.
    var essentialsText: String

    enum CodingKeys: String, CodingKey {
        case bundleID, name, executablePath, bundlePath, cryptid, gateBlocked
        case exportedAt, jsonFileName, essentialsText, initCommand
    }

    init(
        bundleID: String,
        name: String,
        executablePath: String,
        bundlePath: String,
        cryptid: Int,
        gateBlocked: Bool,
        exportedAt: String,
        jsonFileName: String,
        essentialsText: String
    ) {
        self.bundleID = bundleID
        self.name = name
        self.executablePath = executablePath
        self.bundlePath = bundlePath
        self.cryptid = cryptid
        self.gateBlocked = gateBlocked
        self.exportedAt = exportedAt
        self.jsonFileName = jsonFileName
        self.essentialsText = essentialsText
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        name = try c.decode(String.self, forKey: .name)
        executablePath = try c.decode(String.self, forKey: .executablePath)
        bundlePath = try c.decode(String.self, forKey: .bundlePath)
        cryptid = try c.decode(Int.self, forKey: .cryptid)
        gateBlocked = try c.decode(Bool.self, forKey: .gateBlocked)
        exportedAt = try c.decode(String.self, forKey: .exportedAt)
        jsonFileName = try c.decode(String.self, forKey: .jsonFileName)
        essentialsText = try c.decodeIfPresent(String.self, forKey: .essentialsText)
            ?? c.decodeIfPresent(String.self, forKey: .initCommand)
            ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(name, forKey: .name)
        try c.encode(executablePath, forKey: .executablePath)
        try c.encode(bundlePath, forKey: .bundlePath)
        try c.encode(cryptid, forKey: .cryptid)
        try c.encode(gateBlocked, forKey: .gateBlocked)
        try c.encode(exportedAt, forKey: .exportedAt)
        try c.encode(jsonFileName, forKey: .jsonFileName)
        try c.encode(essentialsText, forKey: .essentialsText)
    }
}

final class RECaseHistoryStore: ObservableObject {
    static let shared = RECaseHistoryStore()

    @Published private(set) var items: [RECaseHistoryItem] = []

    private let maxItems = 30
    private var rootURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("REScoutProfiles", isDirectory: true)
    }

    private var indexURL: URL { rootURL.appendingPathComponent("index.json") }

    private init() {
        migrateLegacyFolderIfNeeded()
        reload()
    }

    func reload() {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([RECaseHistoryItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    @discardableResult
    func save(app: InstalledAppInfo, re: AppREProfile, pack: [String: Any], jsonData: Data) -> RECaseHistoryItem? {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let safe = app.bundleID.replacingOccurrences(of: "/", with: "_")
        let fileName = "\(safe)-\(stamp).json"
        let fileURL = rootURL.appendingPathComponent(fileName)
        do {
            try jsonData.write(to: fileURL, options: .atomic)
            let readme = RECaseExporter.readmeText(from: pack)
            let readmeURL = rootURL.appendingPathComponent("\(safe)-\(stamp).txt")
            try? readme.write(to: readmeURL, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }

        let item = RECaseHistoryItem(
            bundleID: app.bundleID,
            name: app.name,
            executablePath: re.executablePath,
            bundlePath: re.bundlePathResolved.isEmpty ? app.bundlePath : re.bundlePathResolved,
            cryptid: re.cryptid,
            gateBlocked: re.gateBlocked,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            jsonFileName: fileName,
            essentialsText: RECaseExporter.essentialsText(from: pack)
        )

        var next = items.filter { $0.bundleID != item.bundleID || $0.exportedAt != item.exportedAt }
        next.insert(item, at: 0)
        if next.count > maxItems {
            let dropped = Array(next.suffix(from: maxItems))
            for d in dropped {
                try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(d.jsonFileName))
                let txt = d.jsonFileName.replacingOccurrences(of: ".json", with: ".txt")
                try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(txt))
            }
            next = Array(next.prefix(maxItems))
        }
        items = next
        if let data = try? JSONEncoder().encode(next) {
            try? data.write(to: indexURL, options: .atomic)
        }
        return item
    }

    /// Backward-compatible wrapper.
    @discardableResult
    func save(app: InstalledAppInfo, re: AppREProfile, caseDict: [String: Any], jsonData: Data) -> RECaseHistoryItem? {
        save(app: app, re: re, pack: caseDict, jsonData: jsonData)
    }

    func fileURL(for item: RECaseHistoryItem) -> URL {
        rootURL.appendingPathComponent(item.jsonFileName)
    }

    func readmeURL(for item: RECaseHistoryItem) -> URL {
        rootURL.appendingPathComponent(item.jsonFileName.replacingOccurrences(of: ".json", with: ".txt"))
    }

    func loadJSON(for item: RECaseHistoryItem) -> Data? {
        try? Data(contentsOf: fileURL(for: item))
    }

    func loadPack(for item: RECaseHistoryItem) -> [String: Any]? {
        guard let data = loadJSON(for: item),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    func delete(_ item: RECaseHistoryItem) {
        try? FileManager.default.removeItem(at: fileURL(for: item))
        try? FileManager.default.removeItem(at: readmeURL(for: item))
        items.removeAll { $0.id == item.id }
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    private func migrateLegacyFolderIfNeeded() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let legacy = docs.appendingPathComponent("REScoutCases", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: rootURL.path) else { return }
        try? fm.moveItem(at: legacy, to: rootURL)
    }
}
