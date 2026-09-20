import SwiftUI
import UIKit

/// Exported profiles list. Pushed from Apps / Settings (not a root tab).
struct CasesListView: View {
    @ObservedObject private var history = RECaseHistoryStore.shared
    @State private var toast: String?

    var body: some View {
        List {
            if history.items.isEmpty {
                Text(L10n.tr("Cases Empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(history.items) { item in
                    NavigationLink {
                        ProfilePreviewView(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.name).font(.headline)
                                Spacer()
                                Text(item.gateBlocked ? L10n.tr("RE Gate Cryptid Blocked") : L10n.tr("RE Gate Clear"))
                                    .font(.caption2)
                                    .foregroundStyle(item.gateBlocked ? .red : .secondary)
                                    .lineLimit(1)
                            }
                            Text(item.bundleID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(item.exportedAt)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            history.delete(item)
                        } label: {
                            Label(L10n.tr("Delete"), systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(L10n.tr("RE Copy Essentials")) {
                            copy(
                                item.essentialsText.isEmpty
                                    ? "bundle_id: \(item.bundleID)"
                                    : item.essentialsText,
                                toast: L10n.tr("RE Essentials Copied")
                            )
                        }
                        Button(L10n.tr("RE Copy Bundle ID")) {
                            copy(item.bundleID, toast: L10n.tr("RE Copied Bundle"))
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("Tab Cases"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { history.reload() } label: {
                    Image(systemName: "arrow.clockwise")
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
                    .padding(.bottom, 24)
            }
        }
        .onAppear { history.reload() }
    }

    private func copy(_ text: String, toast message: String) {
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        withAnimation { self.toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { self.toast = nil }
        }
    }
}
