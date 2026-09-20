import Foundation
import Combine

@MainActor
final class InstalledAppsStore: ObservableObject {
    @Published private(set) var apps: [InstalledAppInfo] = []
    @Published private(set) var isLoading = false
    @Published var searchText = ""
    @Published var lastError: String?

    private let settings = AppSettingsStore.shared

    var filteredApps: [InstalledAppInfo] {
        let base = settings.showSystemApps ? apps : apps.filter { !$0.isSystem }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.bundleID.localizedCaseInsensitiveContains(q)
        }
    }

    func reload() {
        isLoading = true
        lastError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = InstalledAppsCollector.loadAll()
            DispatchQueue.main.async {
                self.apps = loaded
                self.isLoading = false
                if loaded.isEmpty {
                    self.lastError = L10n.tr("Apps Load Empty")
                }
            }
        }
    }
}
