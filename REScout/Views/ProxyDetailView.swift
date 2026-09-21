import SwiftUI

struct ProxyDetailView: View {
    @State private var host = ""
    @State private var portText = "8080"
    @State private var mirrorHTTPS = true
    @State private var vpnStatus: ProxyVPNStatus = ProxyVPNManager.currentStatus()
    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var statusReady = ProxyVPNManager.hasResolvedSession()
    @State private var savedHost = ""
    @State private var savedPort = 8080
    @EnvironmentObject private var store: DeviceInfoStore

    private var connectDisabled: Bool {
        !statusReady || isWorking || vpnStatus.blocksConnect
    }

    private var disconnectDisabled: Bool {
        !statusReady || isWorking || (!vpnStatus.allowsDisconnect && !ProxyVPNManager.sessionExpected)
    }

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
                    .disabled(connectDisabled && vpnStatus.blocksConnect)
                TextField(L10n.tr("Proxy Port"), text: $portText)
                    .keyboardType(.numberPad)
                    .disabled(connectDisabled && vpnStatus.blocksConnect)
                Toggle(L10n.tr("Proxy Mirror HTTPS"), isOn: $mirrorHTTPS)
                    .disabled(connectDisabled && vpnStatus.blocksConnect)
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
                .disabled(connectDisabled)

                Button(role: .destructive) {
                    disconnect()
                } label: {
                    Text(L10n.tr("Proxy VPN Disconnect"))
                }
                .disabled(disconnectDisabled)

                Button {
                    ProxyVPNManager.refreshCache()
                } label: {
                    Text(L10n.tr("Refresh"))
                }
                .disabled(isWorking)
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
            applyCachedEndpoint()
            vpnStatus = ProxyVPNManager.currentStatus()
            statusReady = ProxyVPNManager.hasResolvedSession()
            ProxyVPNManager.refreshCache()
        }
        .onReceive(NotificationCenter.default.publisher(for: .proxyVPNStatusDidUpdate)) { _ in
            applyCachedEndpoint()
            vpnStatus = ProxyVPNManager.currentStatus()
            statusReady = true
        }
    }

    private func applyCachedEndpoint() {
        let endpoint = ProxyVPNManager.currentEndpoint()
        if !endpoint.host.isEmpty {
            savedHost = endpoint.host
            savedPort = endpoint.port
            if host.isEmpty { host = endpoint.host }
            if portText == "8080" || portText.isEmpty {
                portText = "\(endpoint.port)"
            }
            mirrorHTTPS = endpoint.mirrorHTTPS
        }
    }

    private func connect() {
        guard !connectDisabled else { return }
        let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        isWorking = true
        statusMessage = nil
        vpnStatus = .connecting
        ProxyVPNManager.connect(host: host, port: port, mirrorHTTPS: mirrorHTTPS) { result in
            DispatchQueue.main.async {
                isWorking = false
                vpnStatus = ProxyVPNManager.currentStatus()
                applyCachedEndpoint()
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
                    store.refresh(forcePublicIP: false, mode: .light)
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
        guard !disconnectDisabled else { return }
        isWorking = true
        vpnStatus = .disconnecting
        ProxyVPNManager.disconnect { result in
            DispatchQueue.main.async {
                isWorking = false
                vpnStatus = ProxyVPNManager.currentStatus()
                applyCachedEndpoint()
                switch result {
                case .success:
                    statusMessage = L10n.tr("Proxy VPN Disconnect OK")
                    store.refresh(forcePublicIP: false, mode: .light)
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
