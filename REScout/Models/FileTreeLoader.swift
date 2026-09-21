import Foundation

struct FileNode: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let fileSize: UInt64?
    let modificationDate: Date?
    let isHidden: Bool
}

enum FileListOutcome {
    case listed([FileNode])
    case unreadable(String)
    case missing
}

/// Sort within directory/file groups. Directories always stay above files.
enum FileSortMode: String, CaseIterable, Identifiable {
    case nameAsc
    case nameDesc
    case dateNewest
    case dateOldest
    case sizeLargest
    case sizeSmallest

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .nameAsc: return "File Sort Name Asc"
        case .nameDesc: return "File Sort Name Desc"
        case .dateNewest: return "File Sort Date Newest"
        case .dateOldest: return "File Sort Date Oldest"
        case .sizeLargest: return "File Sort Size Largest"
        case .sizeSmallest: return "File Sort Size Smallest"
        }
    }

    private static let storageKey = "rescout.fileSortMode"

    static var stored: FileSortMode {
        get {
            let raw = UserDefaults.standard.string(forKey: storageKey) ?? FileSortMode.nameAsc.rawValue
            return FileSortMode(rawValue: raw) ?? .nameAsc
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    static func sort(_ nodes: inout [FileNode], mode: FileSortMode) {
        nodes.sort { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            switch mode {
            case .nameAsc:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .nameDesc:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending
            case .dateNewest:
                let da = a.modificationDate ?? .distantPast
                let db = b.modificationDate ?? .distantPast
                if da != db { return da > db }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .dateOldest:
                let da = a.modificationDate ?? .distantFuture
                let db = b.modificationDate ?? .distantFuture
                if da != db { return da < db }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .sizeLargest:
                let sa = a.isDirectory ? 0 : (a.fileSize ?? 0)
                let sb = b.isDirectory ? 0 : (b.fileSize ?? 0)
                if sa != sb { return sa > sb }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .sizeSmallest:
                let sa = a.isDirectory ? 0 : (a.fileSize ?? 0)
                let sb = b.isDirectory ? 0 : (b.fileSize ?? 0)
                if sa != sb { return sa < sb }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }
}

enum FileTreeLoader {
    static let textExtensions: Set<String> = [
        "txt", "text", "log", "md", "markdown", "json", "xml", "plist", "strings",
        "js", "ts", "css", "html", "htm", "csv", "yml", "yaml", "ini", "conf",
        "cfg", "swift", "h", "m", "mm", "c", "cpp", "py", "sh", "sql", "entitlements",
        "pem", "crt", "key", "gitignore", "editorconfig", "toml"
    ]

    static let packageExtensions: Set<String> = [
        "ipa", "tipa", "deb", "zip", "tar", "gz", "tgz", "xz", "bz2", "7z", "dylib"
    ]

    static let maxPreviewBytes: UInt64 = 2 * 1024 * 1024
    static let ioQueue = DispatchQueue(label: "com.fyqs.REScout.fileio", qos: .userInitiated)

    static func pathExtension(of path: String) -> String {
        (path as NSString).pathExtension.lowercased()
    }

    static func isPackageFile(_ path: String) -> Bool {
        packageExtensions.contains(pathExtension(of: path))
    }

    static func typeIdentifier(for path: String) -> String {
        switch pathExtension(of: path) {
        case "ipa", "tipa":
            return "com.apple.itunes.ipa"
        case "deb":
            return "org.debian.deb-archive"
        case "zip":
            return "public.zip-archive"
        case "dylib":
            return "public.data"
        default:
            return "public.data"
        }
    }

    static func systemImage(for path: String) -> String {
        switch pathExtension(of: path) {
        case "ipa", "tipa":
            return "app.gift"
        case "deb":
            return "shippingbox.fill"
        case "zip", "tar", "gz", "tgz", "xz", "bz2", "7z":
            return "doc.zipper"
        case "dylib":
            return "gearshape"
        default:
            return "doc"
        }
    }

    static func typeDisplayName(for path: String) -> String {
        let ext = pathExtension(of: path)
        if ext.isEmpty { return L10n.tr("Binary Or Encrypted") }
        switch ext {
        case "ipa": return "IPA"
        case "tipa": return "TIPA"
        case "deb": return "DEB"
        default: return ext.uppercased()
        }
    }

    /// Resolve directory path for browsing.
    /// Critical on Dopamine rootless: `/var/jb` is a symlink to
    /// `/private/preboot/.../procursus`. NSFileManager often reports the
    /// symlink itself as "not a directory", which previously aborted listing.
    static func resolveDirectoryPath(_ path: String) -> String {
        let fm = FileManager.default
        let standardized = (path as NSString).standardizingPath

        // Prefer full symlink resolution (follows /var/jb → procursus).
        let resolved = (standardized as NSString).resolvingSymlinksInPath
        if pathLooksLikeBrowsableDirectory(resolved) {
            return resolved
        }

        // Destination of a final-component symlink (destination may not exist yet → keep original).
        if let dest = try? fm.destinationOfSymbolicLink(atPath: standardized) {
            let absolute: String
            if dest.hasPrefix("/") {
                absolute = (dest as NSString).standardizingPath
            } else {
                let parent = (standardized as NSString).deletingLastPathComponent
                absolute = ((parent as NSString).appendingPathComponent(dest) as NSString).standardizingPath
            }
            let destResolved = (absolute as NSString).resolvingSymlinksInPath
            if pathLooksLikeBrowsableDirectory(destResolved) {
                return destResolved
            }
            if pathLooksLikeBrowsableDirectory(absolute) {
                return absolute
            }
        }

        return standardized
    }

    private static func pathLooksLikeBrowsableDirectory(_ path: String) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return true
        }
        // Symlink-to-directory: existence check may say "not a directory".
        // Probe with a shallow list (follows directory symlinks).
        if fm.fileExists(atPath: path) || (try? fm.destinationOfSymbolicLink(atPath: path)) != nil {
            if (try? fm.contentsOfDirectory(atPath: path)) != nil {
                return true
            }
        }
        return false
    }

    /// Full listing (including hidden names). Sort: directories first, then name.
    static func listChildren(at path: String, includeHidden: Bool = true) -> FileListOutcome {
        let fm = FileManager.default
        let browsePath = resolveDirectoryPath(path)

        // Existence: accept symlink-to-dir after resolution.
        if !fm.fileExists(atPath: browsePath),
           (try? fm.destinationOfSymbolicLink(atPath: path)) == nil,
           (try? fm.destinationOfSymbolicLink(atPath: browsePath)) == nil {
            return .missing
        }

        do {
            // atPath API follows directory symlinks (works for /var/jb).
            let names = try fm.contentsOfDirectory(atPath: browsePath)
            var nodes: [FileNode] = []
            nodes.reserveCapacity(names.count)

            for name in names {
                if name == "." || name == ".." { continue }
                let full = (browsePath as NSString).appendingPathComponent(name)
                let hidden = name.hasPrefix(".")
                if !includeHidden && hidden { continue }

                let attrs = try? fm.attributesOfItem(atPath: full)
                let type = attrs?[.type] as? FileAttributeType
                let isSymlink = type == .typeSymbolicLink

                var isDirectory = type == .typeDirectory
                if isSymlink || !isDirectory {
                    var destDir: ObjCBool = false
                    // fileExists follows the symlink for the destination type.
                    if fm.fileExists(atPath: full, isDirectory: &destDir), destDir.boolValue {
                        isDirectory = true
                    } else if isSymlink,
                              let dest = try? fm.destinationOfSymbolicLink(atPath: full) {
                        let destPath: String
                        if dest.hasPrefix("/") {
                            destPath = dest
                        } else {
                            destPath = (browsePath as NSString).appendingPathComponent(dest)
                        }
                        var d: ObjCBool = false
                        if fm.fileExists(atPath: destPath, isDirectory: &d), d.boolValue {
                            isDirectory = true
                        }
                    }
                }

                let size: UInt64? = {
                    guard !isDirectory,
                          let n = attrs?[.size] as? NSNumber else { return nil }
                    return n.uint64Value
                }()
                let modified = attrs?[.modificationDate] as? Date

                nodes.append(FileNode(
                    id: full,
                    name: name,
                    path: full,
                    isDirectory: isDirectory,
                    fileSize: size,
                    modificationDate: modified,
                    isHidden: hidden
                ))
            }

            return .listed(nodes)
        } catch {
            // Fallback: URL enumerator on resolved path.
            do {
                let url = URL(fileURLWithPath: browsePath, isDirectory: true)
                let keys: Set<URLResourceKey> = [
                    .isDirectoryKey, .fileSizeKey, .isHiddenKey, .isSymbolicLinkKey,
                    .nameKey, .contentModificationDateKey
                ]
                let urls = try fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: Array(keys),
                    options: []
                )
                var nodes: [FileNode] = []
                for itemURL in urls {
                    let values = try? itemURL.resourceValues(forKeys: keys)
                    let name = values?.name ?? itemURL.lastPathComponent
                    if name == "." || name == ".." { continue }
                    let hidden = values?.isHidden == true || name.hasPrefix(".")
                    if !includeHidden && hidden { continue }
                    var isDirectory = values?.isDirectory == true
                    if values?.isSymbolicLink == true {
                        var destDir: ObjCBool = false
                        if fm.fileExists(atPath: itemURL.path, isDirectory: &destDir) {
                            isDirectory = destDir.boolValue
                        }
                    }
                    let size: UInt64? = {
                        guard !isDirectory, let s = values?.fileSize else { return nil }
                        return UInt64(s)
                    }()
                    nodes.append(FileNode(
                        id: itemURL.path,
                        name: name,
                        path: itemURL.path,
                        isDirectory: isDirectory,
                        fileSize: size,
                        modificationDate: values?.contentModificationDate,
                        isHidden: hidden
                    ))
                }
                return .listed(nodes)
            } catch {
                let message = error.localizedDescription
                return .unreadable(message.isEmpty ? L10n.tr("Folder Unreadable") : message)
            }
        }
    }

    static func isLikelyTextFile(path: String, size: UInt64?) -> Bool {
        let ext = pathExtension(of: path)
        if textExtensions.contains(ext) { return true }
        if ext.isEmpty, let size, size > 0, size <= 64 * 1024 { return true }
        return false
    }

    struct FileDetailMeta {
        var exists: Bool
        var size: UInt64?
        var modified: Date?
        var isReadable: Bool
        var isWritable: Bool
    }

    static func loadDetailMeta(at path: String) -> FileDetailMeta {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: path)
        let attrs = try? fm.attributesOfItem(atPath: path)
        return FileDetailMeta(
            exists: exists,
            size: (attrs?[.size] as? NSNumber)?.uint64Value,
            modified: attrs?[.modificationDate] as? Date,
            isReadable: fm.isReadableFile(atPath: path),
            isWritable: fm.isWritableFile(atPath: path)
        )
    }

    /// Copy (or clone) into tmp so AirDrop / Notes / TrollStore can read the file.
    /// Keeps the original filename so `.ipa` / `.deb` UTIs stay intact.
    static func copyForSharing(path: String) -> Result<URL, Error> {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return .failure(fileError(1, L10n.tr("File Missing")))
        }
        let src = URL(fileURLWithPath: path)
        let folder = fm.temporaryDirectory.appendingPathComponent(
            "rescout-share-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let dest = folder.appendingPathComponent(src.lastPathComponent)
            do {
                try fm.linkItem(at: src, to: dest)
            } catch {
                try fm.copyItem(at: src, to: dest)
            }
            ActivityLogStore.log(
                .info,
                category: L10n.tr("Log Category File"),
                message: String(format: L10n.tr("Log File Shared Format"), path)
            )
            return .success(dest)
        } catch {
            try? fm.removeItem(at: folder)
            ActivityLogStore.log(
                .error,
                category: L10n.tr("Log Category File"),
                message: String(format: L10n.tr("Log File Failed Format"), path, error.localizedDescription)
            )
            return .failure(error)
        }
    }

    static func removeShareStaging(around fileURL: URL) {
        let folder = fileURL.deletingLastPathComponent()
        guard folder.lastPathComponent.hasPrefix("rescout-share-") else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    static func isSensitivePath(_ path: String) -> Bool {
        let p = (path as NSString).standardizingPath
        if p == "/" { return true }
        // Protect core OS; allow browsing jailbreak bootstrap under preboot/procursus.
        let prefixes = [
            "/System", "/sbin", "/bin", "/usr/libexec", "/usr/sbin",
            "/dev", "/private/var/db", "/cores"
        ]
        for prefix in prefixes {
            if p == prefix || p.hasPrefix(prefix + "/") { return true }
        }
        // preboot root is sensitive; dopamine/procursus trees are normal jb content.
        if p == "/private/preboot" || p.hasPrefix("/private/preboot/") {
            if p.contains("/procursus") || p.contains("/dopamine") {
                return false
            }
            return true
        }
        return false
    }

    static func loadTextPreview(path: String) -> Result<String, Error> {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return .failure(fileError(1, L10n.tr("File Missing")))
        }
        let attrs = try? fm.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        if size > maxPreviewBytes {
            return .failure(fileError(2, L10n.tr("File Too Large")))
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
            if let text = String(data: data, encoding: .utf8) {
                return .success(text)
            }
            if let text = String(data: data, encoding: .ascii) {
                return .success(text)
            }
            let sample = data.prefix(512)
            let nonPrintable = sample.filter { b in
                (b < 9) || (b > 13 && b < 32) || b == 0xFF
            }.count
            if nonPrintable > sample.count / 8 {
                return .failure(fileError(3, L10n.tr("File Not Text")))
            }
            return .success(String(decoding: data, as: UTF8.self))
        } catch {
            return .failure(error)
        }
    }

    static func writeText(_ text: String, to path: String) -> Result<Void, Error> {
        do {
            let data = Data(text.utf8)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            ActivityLogStore.log(.info, category: L10n.tr("Log Category File"), message: String(format: L10n.tr("Log File Saved Format"), path))
            return .success(())
        } catch {
            ActivityLogStore.log(.error, category: L10n.tr("Log Category File"), message: String(format: L10n.tr("Log File Failed Format"), path, error.localizedDescription))
            return .failure(error)
        }
    }

    static func createDirectory(named name: String, in parent: String) -> Result<String, Error> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            return .failure(fileError(10, L10n.tr("Invalid File Name")))
        }
        let full = (parent as NSString).appendingPathComponent(trimmed)
        do {
            try FileManager.default.createDirectory(atPath: full, withIntermediateDirectories: false)
            ActivityLogStore.log(.info, category: L10n.tr("Log Category File"), message: String(format: L10n.tr("Log File Created Format"), full))
            return .success(full)
        } catch {
            ActivityLogStore.log(.error, category: L10n.tr("Log Category File"), message: String(format: L10n.tr("Log File Failed Format"), full, error.localizedDescription))
            return .failure(error)
        }
    }

    static func createTextFile(named name: String, in parent: String, contents: String = "") -> Result<String, Error> {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            return .failure(fileError(10, L10n.tr("Invalid File Name")))
        }
        if (trimmed as NSString).pathExtension.isEmpty {
            trimmed += ".txt"
        }
        let full = (parent as NSString).appendingPathComponent(trimmed)
        let fm = FileManager.default
        if fm.fileExists(atPath: full) {
            return .failure(fileError(11, L10n.tr("File Already Exists")))
        }
        let ok = fm.createFile(atPath: full, contents: Data(contents.utf8), attributes: nil)
        if ok {
            ActivityLogStore.log(.info, category: L10n.tr("Log Category File"), message: String(format: L10n.tr("Log File Created Format"), full))
            return .success(full)
        }
        ActivityLogStore.log(.error, category: L10n.tr("Log Category File"), message: String(format: L10n.tr("Log File Failed Format"), full, L10n.tr("File Write Failed")))
        return .failure(fileError(12, L10n.tr("File Write Failed")))
    }

    static func renameItem(at path: String, to newName: String) -> Result<String, Error> {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            return .failure(fileError(10, L10n.tr("Invalid File Name")))
        }
        let parent = (path as NSString).deletingLastPathComponent
        let dest = (parent as NSString).appendingPathComponent(trimmed)
        do {
            try FileManager.default.moveItem(atPath: path, toPath: dest)
            ActivityLogStore.log(.info, category: L10n.tr("Log Category File"), message: String(format: L10n.tr("Log File Renamed Format"), path, dest))
            return .success(dest)
        } catch {
            ActivityLogStore.log(.error, category: L10n.tr("Log Category File"), message: String(format: L10n.tr("Log File Failed Format"), path, error.localizedDescription))
            return .failure(error)
        }
    }

    static func removeItem(at path: String) -> Result<Void, Error> {
        do {
            try FileManager.default.removeItem(atPath: path)
            ActivityLogStore.log(.warn, category: L10n.tr("Log Category File"), message: String(format: L10n.tr("Log File Deleted Format"), path))
            return .success(())
        } catch {
            ActivityLogStore.log(.error, category: L10n.tr("Log Category File"), message: String(format: L10n.tr("Log File Failed Format"), path, error.localizedDescription))
            return .failure(error)
        }
    }

    private static func fileError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "FileTree", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
