import SwiftUI
import UIKit
import CoreLocation
import AppTrackingTransparency
import AVFoundation
import Photos
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @ObservedObject private var permissions = PermissionCatalogStore.shared
    @State private var cleanableCacheText = "—"

    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink {
                        LanguageSettingsView()
                    } label: {
                        HStack {
                            Text(L10n.tr("Settings Language"))
                            Spacer()
                            Text(L10n.tr(settings.language.titleKey))
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        PermissionsSettingsView()
                    } label: {
                        HStack {
                            Text(L10n.tr("Settings Permissions"))
                            Spacer()
                            Text(String(format: L10n.tr("Permissions Summary Format"), permissions.grantedCount, permissions.totalCount))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Section(L10n.tr("Settings Tools")) {
                    NavigationLink {
                        CasesListView()
                    } label: {
                        Label(L10n.tr("Tab Cases"), systemImage: "doc.text")
                    }
                    NavigationLink {
                        FullFileBrowserHubView()
                    } label: {
                        Label(L10n.tr("File Browser"), systemImage: "folder")
                    }
                }

                Section {
                    NavigationLink {
                        AutoRefreshSettingsView()
                    } label: {
                        HStack {
                            Text(L10n.tr("Settings Auto Refresh"))
                            Spacer()
                            Text(L10n.tr(settings.overviewRefreshInterval.titleKey))
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(L10n.tr("Settings Auto Refresh Footer"))
                }

                Section(L10n.tr("Settings Cache")) {
                    HStack {
                        Text(L10n.tr("Cleanable Cache"))
                        Spacer()
                        Text(cleanableCacheText)
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink(L10n.tr("Cache Details")) {
                        CacheSettingsView()
                    }
                }

                Section(L10n.tr("Settings About")) {
                    HStack {
                        Text(L10n.tr("App Version"))
                        Spacer()
                        Text(settings.appVersion)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Text("Bundle ID")
                        Spacer()
                        Text(Bundle.main.bundleIdentifier ?? "—")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(L10n.tr("Tab Settings"))
            .onAppear {
                refreshCleanable()
                permissions.refresh()
            }
            .id(settings.localizationEpoch)
        }
        .navigationViewStyle(.stack)
    }

    private func refreshCleanable() {
        DispatchQueue.global(qos: .utility).async {
            let report = CacheAnalyzer.analyze()
            DispatchQueue.main.async {
                cleanableCacheText = Formatters.bytes(report.cleanableBytes)
            }
        }
    }
}

struct LanguageSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        List {
            ForEach(Array(AppLanguage.allCases), id: \.rawValue) { lang in
                Button {
                    settings.setLanguage(lang)
                } label: {
                    HStack {
                        Text(L10n.tr(lang.titleKey)).foregroundStyle(.primary)
                        Spacer()
                        if settings.language == lang {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("Settings Language"))
        .navigationBarTitleDisplayMode(.inline)
        .id(settings.localizationEpoch)
    }
}

struct AutoRefreshSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        List {
            ForEach(Array(OverviewRefreshInterval.allCases), id: \.rawValue) { interval in
                Button {
                    settings.overviewRefreshInterval = interval
                } label: {
                    HStack {
                        Text(L10n.tr(interval.titleKey)).foregroundStyle(.primary)
                        Spacer()
                        if settings.overviewRefreshInterval == interval {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("Settings Auto Refresh"))
        .navigationBarTitleDisplayMode(.inline)
        .id(settings.localizationEpoch)
    }
}

struct PermissionsSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @ObservedObject private var permissions = PermissionCatalogStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var refreshToken = UUID()

    var body: some View {
        List {
            Section {
                ForEach(permissions.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.title)
                            Spacer()
                            Text(item.statusText)
                                .foregroundStyle(item.isGranted ? Color.accentColor : .secondary)
                        }
                        Text(item.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if item.canRequest {
                            Button(L10n.tr("Request Permission")) {
                                item.request?()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    permissions.refresh()
                                    refreshToken = UUID()
                                }
                            }
                            .font(.footnote)
                        } else if item.needsSettings {
                            Text(L10n.tr("Permission Denied Hint"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button(L10n.tr("Open System Settings")) {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.footnote)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(L10n.tr("Permission Runtime"))
            } footer: {
                Text(L10n.tr("Permission Runtime Footer"))
            }

            Section(L10n.tr("Permission Entitlements")) {
                ForEach(PermissionCatalog.entitlements(), id: \.0) { row in
                    HStack {
                        Text(row.0)
                        Spacer()
                        Text(row.1)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button(L10n.tr("Open System Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("Settings Permissions"))
        .navigationBarTitleDisplayMode(.inline)
        .id("\(settings.localizationEpoch)-\(refreshToken)")
        .onAppear { permissions.refresh() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                permissions.refresh()
                refreshToken = UUID()
            }
        }
    }
}

struct CacheSettingsView: View {
    @State private var report = CacheAnalyzer.Report.empty
    @State private var message: String?

    var body: some View {
        List {
            Section(L10n.tr("Cache Breakdown")) {
                row(L10n.tr("Cache URLCache"), Formatters.bytes(report.urlCacheBytes))
                row(L10n.tr("Cache Caches Dir"), Formatters.bytes(report.cachesDirBytes))
                row(L10n.tr("Cache Tmp Dir"), Formatters.bytes(report.tmpDirBytes))
                row(L10n.tr("Cleanable Cache"), Formatters.bytes(report.cleanableBytes))
                row(L10n.tr("Cache Total Measured"), Formatters.bytes(report.totalMeasuredBytes))
            }
            Section {
                Text(L10n.tr("Cache Explain"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button(role: .destructive) {
                    clear()
                } label: {
                    Text(L10n.tr("Clear Cleanable Cache"))
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(L10n.tr("Cache Details"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { report = CacheAnalyzer.analyze() }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func clear() {
        DispatchQueue.global(qos: .utility).async {
            CacheAnalyzer.clearCleanable()
            let newReport = CacheAnalyzer.analyze()
            DispatchQueue.main.async {
                report = newReport
                message = L10n.tr("Cache Cleared")
            }
        }
    }
}

// MARK: - Cache helpers

enum CacheAnalyzer {
    struct Report {
        var urlCacheBytes: UInt64
        var cachesDirBytes: UInt64
        var tmpDirBytes: UInt64
        var cleanableBytes: UInt64
        var totalMeasuredBytes: UInt64

        static let empty = Report(urlCacheBytes: 0, cachesDirBytes: 0, tmpDirBytes: 0, cleanableBytes: 0, totalMeasuredBytes: 0)
    }

    static func analyze() -> Report {
        let urlCache = UInt64(URLCache.shared.currentMemoryUsage + URLCache.shared.currentDiskUsage)
        let caches = directorySize(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let tmp = directorySize(URL(fileURLWithPath: NSTemporaryDirectory()))
        // Cleanable = URLCache + tmp + caches (app-owned). Show breakdown so user understands.
        let cleanable = urlCache + tmp + caches
        return Report(
            urlCacheBytes: urlCache,
            cachesDirBytes: caches,
            tmpDirBytes: tmp,
            cleanableBytes: cleanable,
            totalMeasuredBytes: cleanable
        )
    }

    static func clearCleanable() {
        URLCache.shared.removeAllCachedResponses()
        clearContents(of: URL(fileURLWithPath: NSTemporaryDirectory()))
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            clearContents(of: caches)
        }
    }

    private static func directorySize(_ url: URL?) -> UInt64 {
        guard let url else { return 0 }
        let fm = FileManager.default
        // Only measure immediate app sandbox cache/tmp — skip symlinks escaping sandbox if any
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: UInt64 = 0
        var fileCount = 0
        for case let fileURL as URL in enumerator {
            fileCount += 1
            if fileCount > 50_000 { break } // safety cap
            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true { continue }
            total += UInt64(values.fileSize ?? 0)
        }
        return total
    }

    private static func clearContents(of url: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        for item in items {
            try? fm.removeItem(at: item)
        }
    }
}
