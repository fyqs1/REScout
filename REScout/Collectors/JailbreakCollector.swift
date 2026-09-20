import Foundation
import UIKit
import MachO

enum JailbreakCollector {
    static func collect() -> JailbreakInfo {
        #if targetEnvironment(simulator)
        return JailbreakInfo(
            isJailbroken: false,
            statusLabel: L10n.tr("JB Status No"),
            environment: L10n.tr("JB Env Simulator"),
            suspectedJailbreak: "—",
            bootstrap: "—",
            evidences: [L10n.tr("JB Evidence Simulator")]
        )
        #else
        var evidences: [String] = []
        var isJB = false
        var environment = L10n.tr("JB Env Stock")
        var suspected = L10n.tr("JB Unknown")
        var bootstrap = "—"

        let discovered = JbRootDiscovery.discover()
        for root in discovered {
            evidences.append("jbroot: \(root.path) (\(root.kind.rawValue))")
        }

        let rootlessMarkers = [
            "/var/jb",
            "/var/jb/usr/lib",
            "/var/jb/basebin",
            "/var/jb/Library/dpkg",
            "/var/jb/.installed_dopamine",
            "/var/jb/.bootstrapped"
        ]
        let rootfulMarkers = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/usr/sbin/frida-server",
            "/usr/lib/libsubstrate.dylib",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/private/var/lib/apt"
        ]
        let dopamineMarkers = [
            "/var/jb/.installed_dopamine",
            "/Applications/Dopamine.app",
            "/var/jb/basebin/launchdhook.dylib"
        ]
        let rootHideAppMarkers = [
            "/Applications/RootHide.app",
            "/var/containers/Bundle/Application/RootHide.app"
        ]
        let trollStoreMarkers = [
            "/Applications/TrollStore.app",
            "/var/containers/Bundle/Application/TrollStore.app",
            "/var/binpack",
            "/tmp/trollstorehelper"
        ]

        let hitRootless = existingPaths(rootlessMarkers, into: &evidences, prefix: "path")
        let hitRootful = existingPaths(rootfulMarkers, into: &evidences, prefix: "path")
        let hitDopamine = existingPaths(dopamineMarkers, into: &evidences, prefix: "path")
        let hitRootHideApp = existingPaths(rootHideAppMarkers, into: &evidences, prefix: "path")
        let hitTroll = existingPaths(trollStoreMarkers, into: &evidences, prefix: "path")
        let hitJBRoot = discovered.contains { $0.kind == .jbroot }
        let hitVarJB = discovered.contains { $0.kind == .varJB || $0.kind == .resolvedVarJB }

        let dyldHits = dyldSuspiciousLibraries()
        evidences.append(contentsOf: dyldHits.map { "dyld: \($0)" })
        let dyldRootHide = dyldHits.contains {
            let lower = $0.lowercased()
            return lower.contains("roothide") || lower.contains("libvroot") || lower.contains("libroothide")
        }

        evidences.append(contentsOf: schemeEvidence())

        let probe = "/private/var/mobile/REScout_jb_probe.txt"
        do {
            try "probe".write(toFile: probe, atomically: true, encoding: .utf8)
            evidences.append("write: \(probe)")
            try? FileManager.default.removeItem(atPath: probe)
        } catch {
            // expected on stock
        }

        if hitRootless || hitDopamine || hitJBRoot || hitVarJB || hitRootHideApp || dyldRootHide
            || dyldHits.contains(where: {
                let lower = $0.lowercased()
                return lower.contains("ellekit") || lower.contains("substrate") || lower.contains("libhooker")
            }) {
            isJB = true
        }
        if hitRootful {
            isJB = true
        }

        if hitJBRoot || hitRootHideApp || dyldRootHide {
            environment = L10n.tr("JB Env RootHide")
            suspected = "RootHide"
            bootstrap = discovered.first(where: { $0.kind == .jbroot })?.path
                ?? discovered.first?.path
                ?? "jbroot (randomized)"
        } else if hitDopamine || FileManager.default.fileExists(atPath: "/var/jb/.installed_dopamine") {
            environment = L10n.tr("JB Env Rootless")
            suspected = "Dopamine"
            bootstrap = discovered.first?.path ?? "/var/jb (Procursus-like)"
        } else if hitVarJB || hitRootless {
            environment = L10n.tr("JB Env Rootless")
            suspected = L10n.tr("JB Suspected Rootless")
            bootstrap = discovered.first?.path ?? "/var/jb"
        } else if hitRootful {
            environment = L10n.tr("JB Env Rootful")
            suspected = L10n.tr("JB Suspected Rootful")
            bootstrap = "/"
        } else if hitTroll && !isJB {
            environment = L10n.tr("JB Env TrollStore")
            suspected = "—"
            bootstrap = "—"
        } else if !evidences.isEmpty && evidences.contains(where: { $0.hasPrefix("scheme:") || $0.hasPrefix("dyld:") }) {
            environment = L10n.tr("JB Env Suspicious")
            suspected = L10n.tr("JB Unknown")
        }

        let unique = Array(Set(evidences)).sorted()
        let status: String
        if isJB {
            status = L10n.tr("JB Status Yes")
        } else if environment == L10n.tr("JB Env TrollStore") {
            status = L10n.tr("JB Status No")
        } else if environment == L10n.tr("JB Env Suspicious") {
            status = L10n.tr("JB Status Suspicious")
        } else {
            status = L10n.tr("JB Status No")
        }

        return JailbreakInfo(
            isJailbroken: isJB,
            statusLabel: status,
            environment: environment,
            suspectedJailbreak: suspected,
            bootstrap: bootstrap,
            evidences: unique
        )
        #endif
    }

    private static func existingPaths(_ paths: [String], into evidences: inout [String], prefix: String) -> Bool {
        var hit = false
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                evidences.append("\(prefix): \(path)")
                hit = true
            }
        }
        return hit
    }

    private static func dyldSuspiciousLibraries() -> [String] {
        let keywords = [
            "substrate", "ellekit", "libhooker", "substitute", "libcycript",
            "frida", "cephei", "rocketbootstrap", "roothide", "libvroot", "libroothide"
        ]
        var hits: [String] = []
        let count = _dyld_image_count()
        for i in 0..<count {
            guard let cName = _dyld_get_image_name(i) else { continue }
            let name = String(cString: cName)
            let lower = name.lowercased()
            if keywords.contains(where: { lower.contains($0) }) {
                hits.append(name)
            }
        }
        return hits
    }

    /// `canOpenURL` must run on the main thread.
    private static func schemeEvidence() -> [String] {
        let work: () -> [String] = {
            let schemes = ["cydia://", "sileo://", "zbra://", "filza://", "undecimus://", "activator://", "roothide://"]
            var hits: [String] = []
            for scheme in schemes {
                if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                    hits.append("scheme: \(scheme)")
                }
            }
            return hits
        }
        if Thread.isMainThread { return work() }
        return DispatchQueue.main.sync(execute: work)
    }
}
