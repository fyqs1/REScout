import Foundation

struct FileNode: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let fileSize: UInt64?
    let isHidden: Bool
}

enum FileListOutcome {
    case listed([FileNode])
    case unreadable(String)
    case missing
}

enum FileTreeLoader {
    static let textExtensions: Set<String> = [
        "txt", "text", "log", "md", "markdown", "json", "xml", "plist", "strings",
        "js", "ts", "css", "html", "htm", "csv", "yml", "yaml", "ini", "conf",
        "cfg", "swift", "h", "m", "mm", "c", "cpp", "py", "sh", "sql", "entitlements",
        "pem", "crt", "key", "gitignore", "editorconfig", "toml"
    ]

    static let maxPreviewBytes: UInt64 = 2 * 1024 * 1024
    static let ioQueue = DispatchQueue(label: "com.fyqs.REScout.fileio", qos: .userInitiated)

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

                nodes.append(FileNode(
                    id: full,
                    name: name,
                    path: full,
                    isDirectory: isDirectory,
                    fileSize: size,
                    isHidden: hidden
                ))
            }

            nodes.sort { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return .listed(nodes)
        } catch {
            // Fallback: URL enumerator on resolved path.
            do {
                let url = URL(fileURLWithPath: browsePath, isDirectory: true)
                let keys: Set<URLResourceKey> = [
                    .isDirectoryKey, .fileSizeKey, .isHiddenKey, .isSymbolicLinkKey, .nameKey
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
                        isHidden: hidden
                    ))
                }
                nodes.sort { a, b in
                    if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
                return .listed(nodes)
            } catch {
                let message = error.localizedDescription
                return .unreadable(message.isEmpty ? L10n.tr("Folder Unreadable") : message)
            }
        }
    }

    static func isLikelyTextFile(path: String, size: UInt64?) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        if textExtensions.contains(ext) { return true }
        if ext.isEmpty, let size, size > 0, size <= 64 * 1024 { return true }
        return false
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
