import SwiftUI

/// One-folder-per-screen browser. Supports list / create / rename / delete when `allowsMutation` is true.
struct FileBrowserView: View {
    let rootTitle: String
    let rootPath: String
    var allowsMutation: Bool = true

    @State private var browsePath: String = ""
    @State private var nodes: [FileNode] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var emptyHint: String?
    @State private var toast: String?
    @State private var showHidden = true
    @State private var loadToken = UUID()

    @State private var pendingDelete: FileNode?
    @State private var showDeleteConfirm = false
    @State private var renameTarget: FileNode?
    @State private var renameText = ""
    @State private var showRename = false
    @State private var showNewFolder = false
    @State private var showNewFile = false
    @State private var newNameText = ""
    @State private var actionError: String?
    @State private var showActionError = false

    private var activePath: String {
        browsePath.isEmpty ? rootPath : browsePath
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let errorText {
                List {
                    Section { pathHeader }
                    if parentPath != nil {
                        Section { parentDirectoryLink }
                    }
                    Section {
                        Text(errorText)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.insetGrouped)
            } else if nodes.isEmpty {
                List {
                    Section { pathHeader }
                    if parentPath != nil {
                        Section { parentDirectoryLink }
                    }
                    Section {
                        Text(emptyHint ?? L10n.tr("Folder Empty"))
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                List {
                    Section { pathHeader }
                    Section {
                        if parentPath != nil {
                            parentDirectoryLink
                        }
                        ForEach(nodes) { node in
                            fileRow(node)
                        }
                    } header: {
                        Text(String(format: L10n.tr("Item Count Format"), nodes.count))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(rootTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        copyPath(activePath)
                    } label: {
                        Label(L10n.tr("Tap To Copy Path"), systemImage: "doc.on.doc")
                    }
                    Button {
                        showHidden.toggle()
                    } label: {
                        Label(
                            showHidden ? L10n.tr("Hide Hidden Files") : L10n.tr("Show Hidden Files"),
                            systemImage: showHidden ? "eye.slash" : "eye"
                        )
                    }
                    if allowsMutation {
                        Divider()
                        Button {
                            newNameText = ""
                            showNewFolder = true
                        } label: {
                            Label(L10n.tr("New Folder"), systemImage: "folder.badge.plus")
                        }
                        Button {
                            newNameText = "untitled.txt"
                            showNewFile = true
                        } label: {
                            Label(L10n.tr("New Text File"), systemImage: "doc.badge.plus")
                        }
                    }
                    Button {
                        load()
                    } label: {
                        Label(L10n.tr("Refresh"), systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 20)
            }
        }
        .alert(L10n.tr("Confirm Delete Title"), isPresented: $showDeleteConfirm, presenting: pendingDelete) { node in
            Button(L10n.tr("Cancel"), role: .cancel) {}
            Button(L10n.tr("Delete"), role: .destructive) {
                performDelete(node)
            }
        } message: { node in
            Text(deleteMessage(for: node))
        }
        .alert(L10n.tr("Rename"), isPresented: $showRename) {
            TextField(L10n.tr("File Name"), text: $renameText)
            Button(L10n.tr("Cancel"), role: .cancel) {}
            Button(L10n.tr("Save")) { performRename() }
        } message: {
            Text(renameTarget?.path ?? "")
        }
        .alert(L10n.tr("New Folder"), isPresented: $showNewFolder) {
            TextField(L10n.tr("File Name"), text: $newNameText)
            Button(L10n.tr("Cancel"), role: .cancel) {}
            Button(L10n.tr("Create")) { performCreateFolder() }
        }
        .alert(L10n.tr("New Text File"), isPresented: $showNewFile) {
            TextField(L10n.tr("File Name"), text: $newNameText)
            Button(L10n.tr("Cancel"), role: .cancel) {}
            Button(L10n.tr("Create")) { performCreateFile() }
        }
        .alert(L10n.tr("Operation Failed"), isPresented: $showActionError) {
            Button(L10n.tr("OK"), role: .cancel) {
                showActionError = false
                actionError = nil
            }
        } message: {
            Text(actionError ?? "")
        }
        .onAppear { load() }
        .onChange(of: showHidden) { _ in load() }
    }

    private var parentPath: String? {
        let path = activePath
        guard path != "/", !path.isEmpty else { return nil }
        let parent = (path as NSString).deletingLastPathComponent
        if parent.isEmpty { return "/" }
        return parent
    }

    @ViewBuilder
    private var parentDirectoryLink: some View {
        if let parent = parentPath {
            let title = parent == "/" ? "/" : (parent as NSString).lastPathComponent
            NavigationLink {
                FileBrowserView(
                    rootTitle: title,
                    rootPath: parent,
                    allowsMutation: allowsMutation
                )
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.left.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("Parent Directory"))
                            .font(.body)
                        Text(parent)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var pathHeader: some View {
        Button {
            copyPath(activePath)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("Current Directory"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(activePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if activePath != rootPath && !rootPath.isEmpty
                    && (activePath.hasPrefix(rootPath + "/") || rootPath == "/") {
                    Text(String(format: L10n.tr("Resolved From Format"), rootPath))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(L10n.tr("Tap To Copy Path"))
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func fileRow(_ node: FileNode) -> some View {
        Group {
            if node.isDirectory {
                NavigationLink {
                    FileBrowserView(
                        rootTitle: node.name,
                        rootPath: node.path,
                        allowsMutation: allowsMutation
                    )
                } label: {
                    rowLabel(
                        node,
                        systemImage: "folder.fill",
                        tint: true,
                        detail: L10n.tr("Enter Directory")
                    )
                }
            } else if FileTreeLoader.isLikelyTextFile(path: node.path, size: node.fileSize) {
                NavigationLink {
                    TextPreviewView(path: node.path, title: node.name, allowsEditing: allowsMutation)
                } label: {
                    rowLabel(node, systemImage: "doc.text", tint: false, detail: L10n.tr("Open Text"))
                }
            } else {
                rowLabel(node, systemImage: "doc", tint: false, detail: L10n.tr("Binary Or Encrypted"))
            }
        }
        .contextMenu { contextMenu(for: node) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if allowsMutation {
                Button(role: .destructive) {
                    pendingDelete = node
                    showDeleteConfirm = true
                } label: {
                    Label(L10n.tr("Delete"), systemImage: "trash")
                }
                Button {
                    renameTarget = node
                    renameText = node.name
                    showRename = true
                } label: {
                    Label(L10n.tr("Rename"), systemImage: "pencil")
                }
                .tint(.orange)
            }
            Button {
                copyPath(node.path)
            } label: {
                Label(L10n.tr("Tap To Copy Path"), systemImage: "doc.on.doc")
            }
            .tint(.accentColor)
        }
    }

    @ViewBuilder
    private func contextMenu(for node: FileNode) -> some View {
        Button {
            copyPath(node.path)
        } label: {
            Label(L10n.tr("Tap To Copy Path"), systemImage: "doc.on.doc")
        }
        if allowsMutation {
            Button {
                renameTarget = node
                renameText = node.name
                showRename = true
            } label: {
                Label(L10n.tr("Rename"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingDelete = node
                showDeleteConfirm = true
            } label: {
                Label(L10n.tr("Delete"), systemImage: "trash")
            }
        }
    }

    private func rowLabel(_ node: FileNode, systemImage: String, tint: Bool, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint ? Color.accentColor : Color.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(node.name)
                        .font(.body)
                        .lineLimit(2)
                    if node.isHidden {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    if let size = node.fileSize {
                        Text(Formatters.bytes(size))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func load() {
        let token = UUID()
        loadToken = token
        isLoading = true
        errorText = nil
        emptyHint = nil
        let requested = rootPath
        let hidden = showHidden
        FileTreeLoader.ioQueue.async {
            let resolved = FileTreeLoader.resolveDirectoryPath(requested)
            let outcome = FileTreeLoader.listChildren(at: resolved, includeHidden: hidden)
            DispatchQueue.main.async {
                guard loadToken == token else { return }
                browsePath = resolved
                isLoading = false
                switch outcome {
                case .listed(let listed):
                    nodes = listed
                    if listed.isEmpty {
                        emptyHint = L10n.tr("Folder Empty")
                    }
                case .unreadable(let message):
                    nodes = []
                    errorText = String(format: L10n.tr("Folder Unreadable Format"), message)
                case .missing:
                    nodes = []
                    errorText = L10n.tr("Path Unavailable")
                }
            }
        }
    }

    private func copyPath(_ path: String) {
        UIPasteboard.general.string = path
        withAnimation { toast = L10n.tr("Path Copied") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { toast = nil }
        }
    }

    private func deleteMessage(for node: FileNode) -> String {
        var msg = String(format: L10n.tr("Confirm Delete Message"), node.path)
        if FileTreeLoader.isSensitivePath(node.path) {
            msg += "\n\n" + L10n.tr("Sensitive Path Warning")
        }
        return msg
    }

    private func performDelete(_ node: FileNode) {
        FileTreeLoader.ioQueue.async {
            let result = FileTreeLoader.removeItem(at: node.path)
            DispatchQueue.main.async {
                switch result {
                case .success:
                    toast = L10n.tr("Deleted")
                    load()
                case .failure(let error):
                    actionError = error.localizedDescription
                    showActionError = true
                }
            }
        }
    }

    private func performRename() {
        guard let target = renameTarget else { return }
        let name = renameText
        FileTreeLoader.ioQueue.async {
            let result = FileTreeLoader.renameItem(at: target.path, to: name)
            DispatchQueue.main.async {
                switch result {
                case .success:
                    toast = L10n.tr("Renamed")
                    load()
                case .failure(let error):
                    actionError = error.localizedDescription
                    showActionError = true
                }
            }
        }
    }

    private func performCreateFolder() {
        let name = newNameText
        let parent = activePath
        FileTreeLoader.ioQueue.async {
            let result = FileTreeLoader.createDirectory(named: name, in: parent)
            DispatchQueue.main.async {
                switch result {
                case .success:
                    toast = L10n.tr("Created")
                    load()
                case .failure(let error):
                    actionError = error.localizedDescription
                    showActionError = true
                }
            }
        }
    }

    private func performCreateFile() {
        let name = newNameText
        let parent = activePath
        FileTreeLoader.ioQueue.async {
            let result = FileTreeLoader.createTextFile(named: name, in: parent)
            DispatchQueue.main.async {
                switch result {
                case .success:
                    toast = L10n.tr("Created")
                    load()
                case .failure(let error):
                    actionError = error.localizedDescription
                    showActionError = true
                }
            }
        }
    }
}
