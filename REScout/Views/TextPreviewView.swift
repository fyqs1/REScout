import SwiftUI

struct TextPreviewView: View {
    let path: String
    let title: String
    var allowsEditing: Bool = false

    @State private var text: String = ""
    @State private var originalText: String = ""
    @State private var errorText: String?
    @State private var loading = true
    @State private var saving = false
    @State private var toast: String?
    @State private var saveError: String?
    @State private var showSaveFailed = false

    private var isDirty: Bool { allowsEditing && text != originalText }

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if let errorText {
                Text(errorText)
                    .foregroundStyle(.secondary)
                    .padding()
            } else if allowsEditing {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(.horizontal, 8)
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    UIPasteboard.general.string = path
                    toast = L10n.tr("Path Copied")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { toast = nil }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel(L10n.tr("Tap To Copy Path"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    save()
                } label: {
                    if saving {
                        ProgressView()
                    } else {
                        Text(L10n.tr("Save"))
                    }
                }
                .disabled(!allowsEditing || !isDirty || saving)
                .opacity(allowsEditing ? 1 : 0)
                .accessibilityHidden(!allowsEditing)
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
        .alert(L10n.tr("Operation Failed"), isPresented: $showSaveFailed) {
            Button(L10n.tr("OK"), role: .cancel) {
                showSaveFailed = false
                saveError = nil
            }
        } message: {
            Text(saveError ?? "")
        }
        .onAppear(perform: load)
    }

    private func load() {
        FileTreeLoader.ioQueue.async {
            let result = FileTreeLoader.loadTextPreview(path: path)
            DispatchQueue.main.async {
                loading = false
                switch result {
                case .success(let value):
                    text = value
                    originalText = value
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func save() {
        guard allowsEditing else { return }
        saving = true
        let snapshot = text
        FileTreeLoader.ioQueue.async {
            let result = FileTreeLoader.writeText(snapshot, to: path)
            DispatchQueue.main.async {
                saving = false
                switch result {
                case .success:
                    originalText = snapshot
                    toast = L10n.tr("Saved")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { toast = nil }
                case .failure(let error):
                    saveError = error.localizedDescription
                    showSaveFailed = true
                }
            }
        }
    }
}
