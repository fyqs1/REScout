import SwiftUI
import UIKit

struct FileDetailView: View {
    let path: String
    let name: String
    var fileSize: UInt64?

    @State private var meta = FileTreeLoader.FileDetailMeta(
        exists: true,
        size: nil,
        modified: nil,
        isReadable: false,
        isWritable: false
    )
    @State private var toast: String?
    @State private var preparingShare = false
    @State private var actionError: String?
    @State private var showActionError = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: FileTreeLoader.systemImage(for: path))
                        .font(.largeTitle)
                        .foregroundStyle(FileTreeLoader.isPackageFile(path) ? Color.accentColor : Color.secondary)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                        Text(FileTreeLoader.typeDisplayName(for: path))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }

            Section {
                infoRow(L10n.tr("File Size"), sizeText)
                infoRow(L10n.tr("File Type"), FileTreeLoader.typeDisplayName(for: path))
                infoRow(L10n.tr("File Modified"), modifiedText)
                infoRow(L10n.tr("File Readable"), meta.isReadable ? L10n.tr("Yes") : L10n.tr("No"))
                infoRow(L10n.tr("File Writable"), meta.isWritable ? L10n.tr("Yes") : L10n.tr("No"))
            }

            Section {
                Button {
                    copyPath()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("Root Path"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(L10n.tr("Tap To Copy Path"))
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.tr("File Detail"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareToolbarButton(
                    accessibilityLabel: L10n.tr("Share File"),
                    isEnabled: !preparingShare && meta.exists
                ) { anchor in
                    share(from: anchor)
                }
                .frame(width: 36, height: 44)
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
        .overlay {
            if preparingShare {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView(L10n.tr("Sharing File"))
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .alert(L10n.tr("Share File Failed"), isPresented: $showActionError) {
            Button(L10n.tr("OK"), role: .cancel) {
                showActionError = false
                actionError = nil
            }
        } message: {
            Text(actionError ?? "")
        }
        .onAppear {
            meta = FileTreeLoader.loadDetailMeta(at: path)
        }
    }

    private var sizeText: String {
        if let size = meta.size ?? fileSize {
            return Formatters.bytes(size)
        }
        return "—"
    }

    private var modifiedText: String {
        guard let date = meta.modified else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }

    private func copyPath() {
        UIPasteboard.general.string = path
        withAnimation { toast = L10n.tr("Path Copied") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { toast = nil }
        }
    }

    private func share(from sourceView: UIView) {
        FileShareCoordinator.prepare(path: path) { preparingShare = $0 } completion: { result in
            switch result {
            case .success(let payload):
                ShareSheetPresenter.present(items: payload.items, from: sourceView) {
                    payload.cleanup()
                }
            case .failure(let error):
                actionError = error.localizedDescription
                showActionError = true
            }
        }
    }
}

enum FileShareCoordinator {
    static func prepare(
        path: String,
        preparing: @escaping (Bool) -> Void,
        completion: @escaping (Result<FileSharePayload, Error>) -> Void
    ) {
        preparing(true)
        FileTreeLoader.ioQueue.async {
            let result = FileTreeLoader.copyForSharing(path: path).map { url -> FileSharePayload in
                FileSharePayload(
                    items: [FileActivityItem(url: url, typeIdentifier: FileTreeLoader.typeIdentifier(for: path))],
                    cleanupURL: url
                )
            }
            DispatchQueue.main.async {
                preparing(false)
                completion(result)
            }
        }
    }
}

struct FileSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
    let cleanupURL: URL?

    func cleanup() {
        guard let cleanupURL else { return }
        FileTreeLoader.removeShareStaging(around: cleanupURL)
    }
}

