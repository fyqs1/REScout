import SwiftUI

struct FullFileBrowserHubView: View {
    private struct Shortcut: Identifiable {
        let id: String
        let title: String
        let path: String
    }

    private var shortcuts: [Shortcut] {
        [
            Shortcut(id: "root", title: "/", path: "/"),
            Shortcut(id: "jb-mobile", title: "/var/jb/var/mobile", path: "/var/jb/var/mobile"),
            Shortcut(
                id: "app-data",
                title: L10n.tr("Browse App Data"),
                path: "/var/mobile/Containers/Data/Application"
            ),
            Shortcut(
                id: "app-bundle",
                title: L10n.tr("Browse App Bundle"),
                path: "/var/containers/Bundle/Application"
            ),
        ]
    }

    var body: some View {
        List {
            Section {
                ForEach(shortcuts) { item in
                    let openPath = FileTreeLoader.resolveDirectoryPath(item.path)
                    let available = FileManager.default.fileExists(atPath: item.path)
                        || FileManager.default.fileExists(atPath: openPath)
                        || (try? FileManager.default.destinationOfSymbolicLink(atPath: item.path)) != nil

                    if available {
                        NavigationLink {
                            FileBrowserView(
                                rootTitle: item.title,
                                rootPath: item.path,
                                allowsMutation: true
                            )
                        } label: {
                            shortcutLabel(title: item.title, path: item.path)
                        }
                    } else {
                        shortcutLabel(title: item.title, path: item.path, unavailable: true)
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("Full File Browser"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shortcutLabel(title: String, path: String, unavailable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
            if title != path {
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
