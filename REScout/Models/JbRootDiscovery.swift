import Foundation

/// Discovers jailbreak bootstrap roots across Dopamine-style `/var/jb`
/// and RootHide-style randomized `.jbroot-*` directories.
enum JbRootDiscovery {
    enum Kind: String {
        case varJB
        case resolvedVarJB
        case jbroot
    }

    struct Root: Equatable, Identifiable {
        let path: String
        let kind: Kind

        var id: String { path }

        var mobilePath: String {
            (path as NSString).appendingPathComponent("var/mobile")
        }

        var displayKindKey: String {
            switch kind {
            case .varJB:
                return "Browse Jailbreak"
            case .resolvedVarJB:
                return "Browse Jailbreak Resolved"
            case .jbroot:
                return "Browse JBRoot"
            }
        }

        var mobileTitleKey: String {
            switch kind {
            case .varJB, .resolvedVarJB:
                return "Browse JB Mobile"
            case .jbroot:
                return "Browse JBRoot Mobile"
            }
        }
    }

    private static let scanParents = [
        "/var/containers/Bundle/Application",
        "/private/var/containers/Bundle/Application",
        "/var/containers/Bundle",
        "/private/var/containers/Bundle",
    ]

    private static let bootstrapMarkers = [
        "usr/lib",
        "usr/bin",
        "Library/dpkg",
        "basebin",
        ".bootstrapped",
        ".installed_dopamine",
        "etc/apt",
        "var/lib/dpkg",
    ]

    /// Ordered unique bootstrap roots (fixed `/var/jb` first when present).
    static func discover() -> [Root] {
        var roots: [Root] = []
        var seen = Set<String>()

        func append(_ path: String, kind: Kind) {
            let normalized = normalize(path)
            guard !normalized.isEmpty else { return }
            guard !seen.contains(normalized) else { return }
            guard looksLikeBootstrap(normalized) || kind == .varJB || kind == .resolvedVarJB else { return }
            // For /var/jb always accept if the path exists (symlink or dir).
            if kind == .varJB || kind == .resolvedVarJB {
                guard pathExists(normalized) else { return }
            } else {
                guard looksLikeBootstrap(normalized) else { return }
            }
            seen.insert(normalized)
            roots.append(Root(path: normalized, kind: kind))
        }

        if pathExists("/var/jb") {
            append("/var/jb", kind: .varJB)
            let resolved = FileTreeLoader.resolveDirectoryPath("/var/jb")
            if resolved != "/var/jb", pathExists(resolved) {
                append(resolved, kind: .resolvedVarJB)
            }
        }

        let fm = FileManager.default
        for parent in scanParents {
            guard let names = try? fm.contentsOfDirectory(atPath: parent) else { continue }
            for name in names where isJBRootName(name) {
                let full = (parent as NSString).appendingPathComponent(name)
                append(full, kind: .jbroot)
            }
        }

        return roots
    }

    static var primaryRoot: Root? { discover().first }

    static var hasRootHideStyleRoot: Bool {
        discover().contains { $0.kind == .jbroot }
    }

    static var hasVarJB: Bool {
        pathExists("/var/jb")
    }

    private static func isJBRootName(_ name: String) -> Bool {
        name == ".jbroot" || name.hasPrefix(".jbroot-") || name.hasPrefix(".jbroot_")
    }

    private static func looksLikeBootstrap(_ path: String) -> Bool {
        let fm = FileManager.default
        guard pathExists(path) else { return false }
        for marker in bootstrapMarkers {
            let candidate = (path as NSString).appendingPathComponent(marker)
            if fm.fileExists(atPath: candidate) { return true }
        }
        // Some jbroot dirs expose rootfs symlink — still treat as bootstrap if directory is non-empty.
        if let names = try? fm.contentsOfDirectory(atPath: path), names.count >= 3 {
            let interesting = names.contains { name in
                ["usr", "Library", "basebin", "Applications", "var", "etc", "rootfs"].contains(name)
            }
            return interesting
        }
        return false
    }

    private static func pathExists(_ path: String) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) { return true }
        if (try? fm.destinationOfSymbolicLink(atPath: path)) != nil { return true }
        let resolved = FileTreeLoader.resolveDirectoryPath(path)
        return resolved != path && fm.fileExists(atPath: resolved)
    }

    private static func normalize(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == "/" { return "/" }
        return "/" + trimmed
            .split(separator: "/")
            .map(String.init)
            .joined(separator: "/")
    }
}
