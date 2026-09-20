import SwiftUI

struct RunningAppsView: View {
    var bundleFilter: String? = nil

    @EnvironmentObject private var store: DeviceInfoStore

    @State private var processes: [RunningProcess] = []
    @State private var query = ""
    @State private var includeApple = false
    @State private var loading = false
    @State private var status: String?
    @State private var pendingKill: RunningProcess?
    @State private var editMode: EditMode = .inactive
    @State private var selectedPIDs: Set<Int> = []
    @State private var confirmBatchKill = false

    private var filtered: [RunningProcess] {
        processes.filter { proc in
            if let filter = bundleFilter, !filter.isEmpty {
                if proc.bundleID != filter { return false }
            } else if !includeApple && proc.isApple {
                return false
            }
            if query.isEmpty { return true }
            let q = query.lowercased()
            return proc.name.lowercased().contains(q)
                || proc.bundleID.lowercased().contains(q)
                || "\(proc.pid)".contains(q)
        }
    }

    private var isEditing: Bool { editMode == .active }

    var body: some View {
        Group {
            if isEditing {
                List(selection: $selectedPIDs) { listSections }
            } else {
                List { listSections }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .navigationTitle(L10n.tr("Processes Title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: L10n.tr("Processes Search"))
        .refreshable { reload() }
        .safeAreaInset(edge: .bottom) {
            if isEditing {
                batchBar
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isEditing {
                    Button(L10n.tr("Process Select All")) {
                        selectedPIDs = Set(filtered.map(\.pid))
                    }
                    .disabled(filtered.isEmpty)
                    Button(L10n.tr("Done")) {
                        finishEditing()
                    }
                } else {
                    Button {
                        reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    Button(L10n.tr("Process Select")) {
                        withAnimation { editMode = .active }
                    }
                }
            }
        }
        .onAppear {
            store.pushLivePause()
            reload()
        }
        .onDisappear {
            store.popLivePause()
        }
        .onChange(of: editMode) { mode in
            if mode == .inactive {
                selectedPIDs.removeAll()
            }
        }
        .confirmationDialog(
            L10n.tr("Process Force Quit Confirm"),
            isPresented: Binding(
                get: { pendingKill != nil },
                set: { if !$0 { pendingKill = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let proc = pendingKill {
                Button(L10n.tr("Process Force Quit"), role: .destructive) {
                    kill(proc)
                    pendingKill = nil
                }
                Button(L10n.tr("Cancel"), role: .cancel) {
                    pendingKill = nil
                }
            }
        } message: {
            if let proc = pendingKill {
                Text("\(proc.name) (pid \(proc.pid))")
            }
        }
        .confirmationDialog(
            L10n.tr("Process Kill Selected Confirm"),
            isPresented: $confirmBatchKill,
            titleVisibility: .visible
        ) {
            Button(L10n.tr("Process Kill Selected"), role: .destructive) {
                killSelected()
            }
            Button(L10n.tr("Cancel"), role: .cancel) {}
        } message: {
            Text(String(format: L10n.tr("Process Kill Selected Message"), selectedPIDs.count))
        }
    }

    @ViewBuilder
    private var listSections: some View {
        Section {
            filterHeader
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        Section {
            if loading && processes.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 24)
            } else if filtered.isEmpty {
                Text(L10n.tr("Processes Empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
            } else {
                ForEach(filtered) { proc in
                    processRow(proc)
                        .tag(proc.pid)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !isEditing {
                                Button(role: .destructive) {
                                    pendingKill = proc
                                } label: {
                                    Label(L10n.tr("Process Kill"), systemImage: "xmark")
                                }
                            }
                        }
                        .contextMenu {
                            if !isEditing {
                                Button(role: .destructive) {
                                    pendingKill = proc
                                } label: {
                                    Label(L10n.tr("Process Kill"), systemImage: "xmark")
                                }
                                if !proc.path.isEmpty {
                                    Button {
                                        UIPasteboard.general.string = proc.path
                                        status = L10n.tr("Path Copied")
                                    } label: {
                                        Label(L10n.tr("Tap To Copy Path"), systemImage: "doc.on.doc")
                                    }
                                }
                                if !proc.bundleID.isEmpty {
                                    Button {
                                        UIPasteboard.general.string = proc.bundleID
                                        status = L10n.tr("Path Copied")
                                    } label: {
                                        Label(L10n.tr("Copy Bundle ID"), systemImage: "number")
                                    }
                                }
                            }
                        }
                }
            }
        } header: {
            HStack {
                Text(String(format: L10n.tr("Processes Count Format"), filtered.count))
                if loading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }

        if let status {
            Section {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func finishEditing() {
        withAnimation {
            editMode = .inactive
            selectedPIDs.removeAll()
        }
    }

    @ViewBuilder
    private var filterHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let filter = bundleFilter, !filter.isEmpty {
                Text(L10n.tr("RE Process Filter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(filter)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Toggle(isOn: $includeApple) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("Processes Show Apple"))
                        Text(L10n.tr("Processes Hint"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var batchBar: some View {
        HStack(spacing: 12) {
            Text(String(format: L10n.tr("Process Selected Count"), selectedPIDs.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                confirmBatchKill = true
            } label: {
                Label(L10n.tr("Process Kill Selected"), systemImage: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selectedPIDs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func processRow(_ proc: RunningProcess) -> some View {
        HStack(spacing: 12) {
            ProcessAppIcon(process: proc)
            VStack(alignment: .leading, spacing: 3) {
                Text(proc.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if !proc.bundleID.isEmpty {
                    Text(proc.bundleID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text("\(proc.pid)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func reload() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let list = RunningProcess.loadApplications()
            DispatchQueue.main.async {
                processes = list
                loading = false
                selectedPIDs = selectedPIDs.intersection(Set(list.map(\.pid)))
            }
        }
    }

    private func kill(_ proc: RunningProcess) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ProcessKiller.kill(pid: proc.pid)
            DispatchQueue.main.async {
                switch result {
                case .success:
                    status = String(format: L10n.tr("Process Killed Format"), proc.name, proc.pid)
                    ActivityLogStore.shared.append(
                        level: .info,
                        category: L10n.tr("Log Category Process"),
                        message: status ?? ""
                    )
                    reload()
                case .failure(let error):
                    status = error.localizedDescription
                    ActivityLogStore.shared.append(
                        level: .error,
                        category: L10n.tr("Log Category Process"),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func killSelected() {
        let targets = filtered.filter { selectedPIDs.contains($0.pid) }
        guard !targets.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var ok = 0
            var fail = 0
            for proc in targets {
                switch ProcessKiller.kill(pid: proc.pid) {
                case .success: ok += 1
                case .failure: fail += 1
                }
            }
            DispatchQueue.main.async {
                status = String(format: L10n.tr("Process Kill Batch Format"), ok, fail)
                ActivityLogStore.shared.append(
                    level: fail == 0 ? .info : .error,
                    category: L10n.tr("Log Category Process"),
                    message: status ?? ""
                )
                selectedPIDs.removeAll()
                editMode = .inactive
                reload()
            }
        }
    }
}

private struct ProcessAppIcon: View {
    let process: RunningProcess
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(fallbackColor)
                    Text(fallbackLetter)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear(perform: load)
    }

    private var cacheKey: String {
        process.bundleID.isEmpty ? process.path : process.bundleID
    }

    private var fallbackLetter: String {
        let trimmed = process.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private var fallbackColor: Color {
        var hash: UInt64 = 5381
        for byte in cacheKey.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let hues: [Double] = [0.58, 0.62, 0.48, 0.08, 0.72, 0.35, 0.90]
        let hue = hues[Int(hash % UInt64(hues.count))]
        return Color(hue: hue, saturation: 0.45, brightness: 0.72)
    }

    private func load() {
        if let cached = AppIconCache.cached(for: cacheKey) {
            image = cached
            return
        }
        let appPath = AppIconCache.appBundlePath(fromExecutablePath: process.path)
        AppIconCache.load(bundleID: process.bundleID, appBundlePath: appPath) { img in
            image = img
        }
    }
}
