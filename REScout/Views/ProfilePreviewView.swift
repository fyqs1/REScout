import SwiftUI
import UIKit

struct ProfilePreviewView: View {
    let item: RECaseHistoryItem
    @State private var pack: [String: Any] = [:]
    @State private var toast: String?

    private var identity: [String: Any] { pack["identity"] as? [String: Any] ?? [:] }
    private var macho: [String: Any] { pack["macho"] as? [String: Any] ?? [:] }
    private var entitlements: [String: Any] { pack["entitlements"] as? [String: Any] ?? [:] }
    private var paths: [String: Any] { pack["paths"] as? [String: Any] ?? [:] }
    private var signing: [String: Any] { pack["signing"] as? [String: Any] ?? [:] }
    private var infoPlist: [String: Any] { pack["info_plist"] as? [String: Any] ?? [:] }
    private var notable: [String: Any] {
        entitlements["notable"] as? [String: Any] ?? [:]
    }

    var body: some View {
        List {
            Section {
                Text(item.gateBlocked ? L10n.tr("RE Gate Cryptid Blocked") : L10n.tr("RE Gate Clear"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.gateBlocked ? .red : .primary)
                Text(item.exportedAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(essentialsBlock)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                Button(L10n.tr("RE Copy Essentials")) {
                    copy(essentialsBlock, toast: L10n.tr("RE Essentials Copied"))
                }
            } header: {
                Text(L10n.tr("Profile Essentials"))
            }

            Section(L10n.tr("Profile Identity")) {
                row(L10n.tr("App Name"), str(identity["name"], fallback: item.name))
                row("Bundle ID", str(identity["bundle_id"], fallback: item.bundleID))
                row(L10n.tr("RE Exec Path"), str(identity["executable_path"], fallback: item.executablePath))
                row(L10n.tr("Profile App Path"), str(identity["app_path"], fallback: item.bundlePath))
                row(L10n.tr("App Version"), str(identity["version"]))
            }

            Section(L10n.tr("Profile Binary")) {
                row(L10n.tr("RE Gate"), item.gateBlocked ? L10n.tr("RE Gate Cryptid Blocked") : L10n.tr("RE Gate Clear"))
                row("cryptid", "\(item.cryptid)")
                row(L10n.tr("RE Arch"), archText)
                row("UUID", str(macho["uuid"]))
            }

            Section(L10n.tr("RE Signing")) {
                row(L10n.tr("RE Signing AppID"), str(signing["application_identifier"]))
                row(L10n.tr("RE Signing Team"), str(signing["team_identifier"]))
                row(L10n.tr("RE Provision Name"), str(signing["provision_name"]))
                row(L10n.tr("RE Provision Expires"), str(signing["provision_expires"]))
            }

            Section(L10n.tr("RE Entitlements")) {
                if notable.isEmpty {
                    Text(L10n.tr("RE Entitlements Empty")).foregroundStyle(.secondary)
                } else {
                    ForEach(notable.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key).font(.caption.monospaced())
                            Text(stringify(notable[key]))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section(L10n.tr("Profile Paths")) {
                row(L10n.tr("Data Container"), str(paths["data"]))
                row(L10n.tr("RE Prefs"), str(paths["prefs"]))
                if let groups = paths["groups"] as? [String: String], !groups.isEmpty {
                    ForEach(groups.keys.sorted(), id: \.self) { key in
                        row(key, groups[key] ?? "")
                    }
                }
            }

            Section(L10n.tr("RE Info Plist")) {
                let schemes = infoPlist["url_schemes"] as? [String] ?? []
                if schemes.isEmpty {
                    Text(L10n.tr("RE No URL Schemes")).foregroundStyle(.secondary)
                } else {
                    ForEach(schemes, id: \.self) { s in
                        Text(s).font(.body.monospaced())
                    }
                }
                row(L10n.tr("RE ATS"), str(infoPlist["ats"]))
            }

            if let note = pack["note"] as? String, !note.isEmpty {
                Section(L10n.tr("Profile Note")) {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareToolbarButton(accessibilityLabel: L10n.tr("Share File")) { anchor in
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
                    .padding(.bottom, 24)
            }
        }
        .onAppear(perform: load)
    }

    private var essentialsBlock: String {
        if !item.essentialsText.isEmpty { return item.essentialsText }
        return RECaseExporter.essentialsText(from: pack)
    }

    private var archText: String {
        if let arr = macho["architectures"] as? [String], !arr.isEmpty {
            return arr.joined(separator: ", ")
        }
        return "—"
    }

    private func load() {
        if let loaded = RECaseHistoryStore.shared.loadPack(for: item) {
            pack = loaded
        } else {
            // Fallback synthetic pack from list metadata.
            pack = [
                "identity": [
                    "name": item.name,
                    "bundle_id": item.bundleID,
                    "app_path": item.bundlePath,
                    "executable_path": item.executablePath
                ],
                "macho": [
                    "cryptid": item.cryptid,
                    "encrypted": item.gateBlocked
                ],
                "essentials_text": item.essentialsText
            ]
        }
    }

    private func share(from sourceView: UIView) {
        let json = RECaseHistoryStore.shared.fileURL(for: item)
        guard FileManager.default.fileExists(atPath: json.path) else { return }
        ShareSheetPresenter.presentFileURLs([json], from: sourceView)
    }

    private func copy(_ text: String, toast message: String) {
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        withAnimation { self.toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { self.toast = nil }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func str(_ value: Any?, fallback: String = "") -> String {
        if let s = value as? String, !s.isEmpty { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return fallback
    }

    private func stringify(_ value: Any?) -> String {
        guard let value else { return "—" }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "\(value)"
    }
}

