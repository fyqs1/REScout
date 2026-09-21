import SwiftUI

struct FullFileBrowserHubView: View {
    private struct Shortcut: Identifiable {
        let id: String
        let title: String
        let path: String
        let subtitle: String?
        var available: Bool = true
    }

    @State private var onMyiPhonePath: String?
    @State private var didResolve = false

    private var shortcuts: [Shortcut] {
        var items: [Shortcut] = [
            Shortcut(
                id: "root",
                title: "/",
                path: "/",
                subtitle: L10n.tr("Shortcut Root Subtitle")
            ),
            Shortcut(
                id: "jb-mobile",
                title: "/var/jb/var/mobile",
                path: "/var/jb/var/mobile",
                subtitle: L10n.tr("Shortcut JB Mobile Subtitle")
            ),
            Shortcut(
                id: "app-data",
                title: L10n.tr("Browse App Data"),
                path: "/var/mobile/Containers/Data/Application",
                subtitle: L10n.tr("Shortcut App Data Subtitle")
            ),
            Shortcut(
                id: "app-bundle",
                title: L10n.tr("Browse App Bundle"),
                path: "/var/containers/Bundle/Application",
                subtitle: L10n.tr("Shortcut App Bundle Subtitle")
            )
        ]
        if let path = onMyiPhonePath {
            items.append(
                Shortcut(
                    id: "on-my-iphone",
                    title: L10n.tr("On My iPhone"),
                    path: path,
                    subtitle: L10n.tr("On My iPhone Subtitle")
                )
            )
        } else if didResolve {
            items.append(
                Shortcut(
                    id: "on-my-iphone-missing",
                    title: L10n.tr("On My iPhone"),
                    path: OnMyiPhoneLocator.appGroupBase,
                    subtitle: L10n.tr("On My iPhone Missing"),
                    available: false
                )
            )
        }
        return items
    }

    var body: some View {
        List {
            Section {
                ForEach(shortcuts) { item in
                    let openPath = FileTreeLoader.resolveDirectoryPath(item.path)
                    let available = item.available && pathAvailable(item.path, openPath: openPath)

                    if available {
                        NavigationLink {
                            FileBrowserView(
                                rootTitle: item.title,
                                rootPath: item.path,
                                allowsMutation: true
                            )
                        } label: {
                            shortcutLabel(item, unavailable: false)
                        }
                    } else {
                        shortcutLabel(item, unavailable: true)
                    }
                }
            } header: {
                Text(L10n.tr("Browse Shortcuts"))
            } footer: {
                Text(L10n.tr("Full File Browser Intro"))
            }
        }
        .navigationTitle(L10n.tr("File Browser"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didResolve else { return }
            onMyiPhonePath = OnMyiPhoneLocator.resolvePath()
            didResolve = true
        }
    }

    private func pathAvailable(_ path: String, openPath: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
            || FileManager.default.fileExists(atPath: openPath)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }

    private func shortcutLabel(_ item: Shortcut, unavailable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.body)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if item.title != item.path {
                Text(item.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if unavailable {
                Text(L10n.tr("Path Unavailable"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
