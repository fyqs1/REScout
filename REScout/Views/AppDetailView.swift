import SwiftUI
import UIKit

struct AppDetailView: View {
    let app: InstalledAppInfo
    @State private var copiedToast: String?
    @State private var profile = AppStorageProfile()
    @State private var re = AppREProfile()
    @State private var loading = true

    private var bundleRoot: String {
        profile.bundleContainerPath.isEmpty ? app.bundleContainerPath : profile.bundleContainerPath
    }

    private var execPath: String {
        if !re.executablePath.isEmpty { return re.executablePath }
        return app.executable
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Group {
                        if let ui = profile.icon {
                            Image(uiImage: ui)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            LazyAppIcon(
                                bundleID: app.bundleID,
                                bundlePath: app.bundlePath,
                                size: 64,
                                cornerRadius: 14
                            )
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.title3.weight(.semibold))
                        Text(app.bundleID).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(L10n.tr(app.role.badgeKey))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)
            }

            if re.gateBlocked {
                Section {
                    Text(L10n.tr("RE Gate Banner Blocked"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(L10n.tr("RE Gate Cryptid Footer"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            // 概况：身份已在顶栏；此处不再重复 name / Bundle ID
            Section {
                infoRow(L10n.tr("RE Gate"), L10n.tr(re.gateSummaryKey))
                    .foregroundStyle(re.gateBlocked ? Color.red : Color.primary)
                infoRow(L10n.tr("App Version"), display(app.version))
                infoRow(L10n.tr("App Build"), display(app.build))
                infoRow(L10n.tr("App Type"), app.type.isEmpty ? L10n.tr(app.role.badgeKey) : app.type)
                infoRow(L10n.tr("App Minimum OS"), display(app.minimumOS))
                infoRow(L10n.tr("App Team ID"), display(app.teamID))
                infoRow(L10n.tr("RE Exec Path"), display(execPath))
                infoRow("cryptid", re.cryptid >= 0 ? "\(re.cryptid)" : "—")
                infoRow(L10n.tr("RE Arch"), re.architectures.isEmpty ? "—" : re.architectures.joined(separator: ", "))
                infoRow(L10n.tr("RE MachO UUID"), display(re.uuid))
                if re.runningPIDs.isEmpty {
                    infoRow(L10n.tr("RE Running State"), L10n.tr("RE Not Running"))
                } else {
                    infoRow(L10n.tr("RE Running State"), re.runningPIDs.map(String.init).joined(separator: ", "))
                }
                if !re.machoError.isEmpty {
                    Text(re.machoError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text(L10n.tr("RE Profile"))
            } footer: {
                if !re.gateBlocked {
                    Text(L10n.tr("RE Gate Clear Footer"))
                }
            }

            Section {
                NavigationLink {
                    AppDetailMoreView(app: app, re: re)
                } label: {
                    Text(L10n.tr("RE More Details"))
                }
            }

            Section {
                browseRoot(
                    title: L10n.tr("Bundle Container"),
                    path: bundleRoot,
                    missingHint: L10n.tr("Bundle Container Missing")
                )
                browseRoot(
                    title: L10n.tr("Data Container"),
                    path: profile.dataPath,
                    missingHint: profile.dataNote.isEmpty ? L10n.tr("Data Container Missing") : profile.dataNote
                )

                if profile.groupsExplicitlyUnused {
                    Text(L10n.tr("App Groups Unused"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if profile.usesAppGroups {
                    let keys = Set(profile.declaredGroups).union(profile.groupContainers.keys).sorted()
                    ForEach(keys, id: \.self) { key in
                        browseRoot(
                            title: "\(L10n.tr("Group Container")) · \(key)",
                            path: profile.groupContainers[key] ?? "",
                            missingHint: L10n.tr("Group Container Missing")
                        )
                    }
                } else {
                    Text(L10n.tr("No App Groups"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if profile.extensions.isEmpty {
                    Text(L10n.tr("No Extensions"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profile.extensions) { ext in
                        browseRoot(
                            title: "\(L10n.tr("Extension Data")) · \(ext.name)",
                            path: ext.dataPath,
                            missingHint: L10n.tr("Extension Data Missing")
                        )
                    }
                }
            } header: {
                Text(L10n.tr("App Section Containers"))
            } footer: {
                Text(L10n.tr("App Section Containers Footer Slim"))
            }

            Section {
                NavigationLink {
                    RunningAppsView(bundleFilter: app.bundleID)
                } label: {
                    Text(L10n.tr("RE Running Processes"))
                }
            } header: {
                Text(L10n.tr("RE Actions"))
            }

            Section {
                Button {
                    copyEssentials()
                } label: {
                    Text(L10n.tr("RE Copy Essentials"))
                }
                Button {
                    exportProfile()
                } label: {
                    Text(L10n.tr("RE Export Case"))
                }
            } header: {
                Text(L10n.tr("RE Export"))
            } footer: {
                Text(L10n.tr("RE Export Footer"))
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let copiedToast {
                Text(copiedToast)
                    .font(.footnote)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 24)
            }
        }
        .overlay {
            if loading { ProgressView() }
        }
        .onAppear(perform: enrich)
    }

    @ViewBuilder
    private func browseRoot(title: String, path: String, missingHint: String) -> some View {
        if path.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(missingHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } else if !FileManager.default.fileExists(atPath: path) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(L10n.tr("Container Path Unavailable"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .contextMenu {
                Button(L10n.tr("Tap To Copy Path")) { copyPath(path) }
            }
        } else {
            NavigationLink {
                FileBrowserView(rootTitle: title, rootPath: path)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 2)
            }
            .contextMenu {
                Button(L10n.tr("Tap To Copy Path")) { copyPath(path) }
            }
        }
    }

    private func enrich() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = AppStorageProfile.load(for: app)
            let reLoaded = AppREProfile.load(for: app, storage: loaded)
            DispatchQueue.main.async {
                profile = loaded
                re = reLoaded
                loading = false
            }
        }
    }

    private func copyEssentials() {
        let bundlePath = re.bundlePathResolved.isEmpty
            ? (profile.bundlePath.isEmpty ? app.bundlePath : profile.bundlePath)
            : re.bundlePathResolved
        let text = RECaseExporter.essentialsText(
            name: app.name,
            bundleID: app.bundleID,
            appPath: bundlePath,
            executablePath: execPath,
            cryptid: re.cryptid,
            encrypted: re.gateBlocked
        )
        copyText(text, toast: L10n.tr("RE Essentials Copied"))
    }

    private func exportProfile() {
        let pack = RECaseExporter.makeNeutralPack(app: app, storage: profile, re: re)
        do {
            let data = try RECaseExporter.jsonData(from: pack)
            _ = RECaseHistoryStore.shared.save(app: app, re: re, pack: pack, jsonData: data)
            let safe = app.bundleID.replacingOccurrences(of: "/", with: "_")
            let jsonURL = FileManager.default.temporaryDirectory.appendingPathComponent("REScout-\(safe).json")
            try data.write(to: jsonURL, options: .atomic)
            ShareSheetPresenter.presentFileURLs([jsonURL], from: nil)
            ActivityLogStore.shared.append(
                level: .info,
                category: L10n.tr("Log Category RE"),
                message: "Exported profile \(app.bundleID)"
            )
        } catch {
            copiedToast = error.localizedDescription
        }
    }

    private func display(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }

    private func copyPath(_ path: String) {
        copyText(path, toast: L10n.tr("Path Copied"))
    }

    private func copyText(_ text: String, toast: String) {
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        withAnimation { copiedToast = toast }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { copiedToast = nil }
        }
    }
}

/// Secondary detail: signing / entitlements / plist / prefs / hotspots / frameworks.
struct AppDetailMoreView: View {
    let app: InstalledAppInfo
    let re: AppREProfile

    var body: some View {
        List {
            Section {
                infoRow(L10n.tr("RE Signing AppID"), display(re.signingAppID))
                infoRow(L10n.tr("RE Signing Team"), display(re.signingTeam.isEmpty ? re.provisionTeamID : re.signingTeam))
                if re.provisionExists {
                    infoRow(L10n.tr("RE Provision Name"), display(re.provisionName))
                    infoRow(L10n.tr("RE Provision Team"), display(re.provisionTeam))
                    infoRow(L10n.tr("RE Provision Expires"), display(re.provisionExpires))
                    infoRow(L10n.tr("RE Provision UUID"), display(re.provisionUUID))
                } else {
                    Text(re.provisionError.isEmpty ? L10n.tr("RE Provision Missing") : re.provisionError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.tr("RE Signing"))
            }

            Section {
                if !re.entitlementsReadable {
                    Text(L10n.tr("RE Entitlements Unreadable")).foregroundStyle(.secondary)
                } else if re.notableEntitlementKeys.isEmpty {
                    Text(L10n.tr("RE Entitlements Empty")).foregroundStyle(.secondary)
                } else {
                    ForEach(re.notableEntitlementKeys, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key).font(.caption.monospaced())
                            Text(entitleValue(re.entitlements[key]))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text(L10n.tr("RE Entitlements"))
            }

            Section {
                if re.urlSchemes.isEmpty {
                    Text(L10n.tr("RE No URL Schemes")).foregroundStyle(.secondary)
                } else {
                    ForEach(re.urlSchemes, id: \.self) { s in
                        Text(s).font(.body.monospaced())
                    }
                }
                if !re.querySchemes.isEmpty {
                    Text(L10n.tr("RE Query Schemes"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(re.querySchemes.prefix(20), id: \.self) { s in
                        Text(s).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                if !re.backgroundModes.isEmpty {
                    infoRow(L10n.tr("RE Background"), re.backgroundModes.joined(separator: ", "))
                }
                infoRow(L10n.tr("RE ATS"), display(re.atsSummary))
            } header: {
                Text(L10n.tr("RE Info Plist"))
            }

            Section {
                if re.prefsKeys.isEmpty {
                    Text(L10n.tr("RE Prefs Empty")).foregroundStyle(.secondary)
                    if !re.prefsPath.isEmpty {
                        Text(re.prefsPath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    infoRow(L10n.tr("RE Prefs Count"), "\(re.prefsKeys.count)")
                    ForEach(re.prefsKeys.prefix(40), id: \.self) { key in
                        Text(key).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    if re.prefsKeys.count > 40 {
                        Text(String(format: L10n.tr("RE Prefs More Format"), re.prefsKeys.count - 40))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text(L10n.tr("RE Prefs"))
            } footer: {
                Text(L10n.tr("RE Prefs Footer"))
            }

            Section {
                if re.dataHotspots.isEmpty {
                    Text(L10n.tr("RE Hotspots Empty")).foregroundStyle(.secondary)
                } else {
                    ForEach(re.dataHotspots.prefix(12)) { spot in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(spot.title).font(.subheadline)
                                Spacer()
                                Text(Formatters.bytes(spot.sizeBytes))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(spot.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button(L10n.tr("Tap To Copy Path")) {
                                UIPasteboard.general.string = spot.path
                            }
                        }
                    }
                }
            } header: {
                Text(L10n.tr("RE Data Hotspots"))
            }

            Section {
                if re.frameworks.isEmpty && re.plugins.isEmpty {
                    Text(L10n.tr("RE No Bundle Extras")).foregroundStyle(.secondary)
                } else {
                    if !re.frameworks.isEmpty {
                        infoRow("Frameworks", "\(re.frameworks.count)")
                        ForEach(re.frameworks.prefix(30), id: \.self) { name in
                            Text(name).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    if !re.plugins.isEmpty {
                        infoRow("PlugIns", "\(re.plugins.count)")
                        ForEach(re.plugins, id: \.self) { name in
                            Text(name).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(L10n.tr("RE Bundle Contents"))
            }
        }
        .navigationTitle(L10n.tr("RE More Details"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func display(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }

    private func entitleValue(_ value: Any?) -> String {
        guard let value else { return "—" }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let a = value as? [Any] { return a.map { "\($0)" }.joined(separator: ", ") }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "\(value)"
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
}

