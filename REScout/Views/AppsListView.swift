import SwiftUI

struct AppsListView: View {
    @EnvironmentObject private var appsStore: InstalledAppsStore
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        NavigationView {
            Group {
                if appsStore.isLoading && appsStore.apps.isEmpty {
                    ProgressView(L10n.tr("Loading Apps"))
                } else {
                    List {
                        Section {
                            Toggle(L10n.tr("Show System Apps"), isOn: $settings.showSystemApps)
                        } footer: {
                            Text(L10n.tr("Show System Apps Footer"))
                        }

                        if let err = appsStore.lastError, appsStore.filteredApps.isEmpty {
                            Text(err)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(appsStore.filteredApps) { app in
                            NavigationLink(destination: AppDetailView(app: app)) {
                                HStack(spacing: 12) {
                                    LazyAppIcon(bundleID: app.bundleID, bundlePath: app.bundlePath)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(app.name)
                                                .font(.headline)
                                                .lineLimit(1)
                                            Text(L10n.tr(app.role.badgeKey))
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.18))
                                                .clipShape(Capsule())
                                        }
                                        Text(app.bundleID)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        if !app.version.isEmpty {
                                            Text("v\(app.version)" + (app.build.isEmpty ? "" : " (\(app.build))"))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(L10n.tr("Tab Apps"))
            .searchable(text: $appsStore.searchText, prompt: L10n.tr("Search Apps"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        CasesListView()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel(L10n.tr("Tab Cases"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { appsStore.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                if appsStore.apps.isEmpty { appsStore.reload() }
            }
            .id("\(settings.localizationEpoch)-\(settings.showSystemApps)")
        }
        .navigationViewStyle(.stack)
    }
}
