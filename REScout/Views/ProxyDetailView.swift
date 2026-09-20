import SwiftUI
import NetworkExtension

struct ProxyDetailView: View {
    @State private var host = ""
    @State private var portText = "8080"
    @State private var mirrorHTTPS = true
    @State private var vpnStatus: ProxyVPNStatus = .disconnected
    @State private var manager: NETunnelProviderManager?
    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var savedHost = ""
    @State private var savedPort = 8080
    @EnvironmentObject private var store: DeviceInfoStore

    var body: some View {
        Form {
            Section {
                row(L10n.tr("Proxy VPN Status"), L10n.tr(vpnStatus.titleKey))
                if !savedHost.isEmpty {
                    row(L10n.tr("Proxy Summary"), "\(savedHost):\(savedPort)")
                }
            } header: {
                Text(L10n.tr("Proxy Current"))
            } footer: {
                Text(L10n.tr("Proxy VPN Hint"))
                    .font(.footnote)
            }

            Section {
                TextField(L10n.tr("Proxy Host"), text: $host)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                TextField(L10n.tr("Proxy Port"), text: $portText)
                    .keyboardType(.numberPad)
                Toggle(L10n.tr("Proxy Mirror HTTPS"), isOn: $mirrorHTTPS)
            } header: {
                Text(L10n.tr("Proxy Configure"))
            }

            Section {
                Button {
                    connect()
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text(L10n.tr("Proxy VPN Connect"))
                    }
                }
                .disabled(isWorking || vpnStatus == .connected || vpnStatus == .connecting)

                Button(role: .destructive) {
                    disconnect()
                } label: {
                    Text(L10n.tr("Proxy VPN Disconnect"))
                }
                .disabled(isWorking || vpnStatus == .disconnected || vpnStatus == .invalid)

                Button {
                    refreshManager()
                } label: {
                    Text(L10n.tr("Refresh"))
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(L10n.tr("Proxy Detail"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ProxyVPNManager.startObserving()
            refreshManager()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)) { _ in
            syncStatusFromManager()
        }
    }

    private func refreshManager() {
        ProxyVPNManager.loadManager { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let m):
                    manager = m
                    applySavedConfig(from: m)
                    syncStatusFromManager()
                case .failure(let error):
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func applySavedConfig(from m: NETunnelProviderManager) {
        guard let proto = m.protocolConfiguration as? NETunnelProviderProtocol,
              let conf = proto.providerConfiguration else { return }
        if let h = conf["proxyHost"] as? String, !h.isEmpty {
            savedHost = h
            if host.isEmpty { host = h }
        }
        if let p = conf["proxyPort"] as? Int {
            savedPort = p
            portText = "\(p)"
        } else if let n = conf["proxyPort"] as? NSNumber {
            savedPort = n.intValue
            portText = "\(n.intValue)"
        }
        if let mirr = conf["mirrorHTTPS"] as? Bool {
            mirrorHTTPS = mirr
        } else if let n = conf["mirrorHTTPS"] as? NSNumber {
            mirrorHTTPS = n.boolValue
        }
    }

    private func syncStatusFromManager() {
        if let m = manager {
            ProxyVPNManager.updateCache(from: m)
            vpnStatus = ProxyVPNStatus.from(m.connection.status)
        } else {
            ProxyVPNManager.loadManager { result in
                DispatchQueue.main.async {
                    if case .success(let m) = result {
                        manager = m
                        ProxyVPNManager.updateCache(from: m)
                        vpnStatus = ProxyVPNStatus.from(m.connection.status)
                        applySavedConfig(from: m)
                    }
                }
            }
        }
        store.refresh(forcePublicIP: false, mode: .light)
    }

    private func connect() {
        let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        isWorking = true
        statusMessage = nil
        ProxyVPNManager.connect(host: host, port: port, mirrorHTTPS: mirrorHTTPS) { result in
            DispatchQueue.main.async {
                isWorking = false
                switch result {
                case .success:
                    savedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
                    savedPort = port
                    statusMessage = L10n.tr("Proxy VPN Connect OK")
                    ActivityLogStore.shared.append(
                        level: .info,
                        category: L10n.tr("Log Category Proxy"),
                        message: statusMessage ?? "VPN connect"
                    )
                    refreshManager()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        syncStatusFromManager()
                    }
                case .failure(let error):
                    statusMessage = error.localizedDescription
                    ActivityLogStore.shared.append(
                        level: .error,
                        category: L10n.tr("Log Category Proxy"),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func disconnect() {
        isWorking = true
        ProxyVPNManager.disconnect { result in
            DispatchQueue.main.async {
                isWorking = false
                switch result {
                case .success:
                    statusMessage = L10n.tr("Proxy VPN Disconnect OK")
                    refreshManager()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        syncStatusFromManager()
                    }
                case .failure(let error):
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
