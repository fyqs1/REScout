import SwiftUI

enum AppTab: Hashable {
    case apps
    case overview
    case settings
}

struct RootTabView: View {
    @EnvironmentObject private var deviceStore: DeviceInfoStore
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var appsStore = InstalledAppsStore()

    @State private var selectedTab: AppTab = .apps
    @State private var overviewNavID = UUID()
    @State private var appsNavID = UUID()
    @State private var settingsNavID = UUID()

    var body: some View {
        TabView(selection: tabBinding) {
            AppsListView()
                .environmentObject(appsStore)
                .id(appsNavID)
                .tabItem {
                    Label(L10n.tr("Tab Apps"), systemImage: "app.badge")
                }
                .tag(AppTab.apps)

            OverviewView()
                .id(overviewNavID)
                .tabItem {
                    Label(L10n.tr("Tab Device"), systemImage: "iphone")
                }
                .tag(AppTab.overview)

            SettingsView()
                .id(settingsNavID)
                .tabItem {
                    Label(L10n.tr("Tab Settings"), systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .id(settings.localizationEpoch)
        .onAppear {
            deviceStore.setAutoRefresh(interval: settings.overviewRefreshInterval.timeInterval)
            deviceStore.setOverviewVisible(selectedTab == .overview)
        }
        .onChange(of: selectedTab) { tab in
            deviceStore.setOverviewVisible(tab == .overview)
        }
        .onChange(of: settings.overviewRefreshInterval) { interval in
            deviceStore.setAutoRefresh(interval: interval.timeInterval)
        }
    }

    private var tabBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    popToRoot(newValue)
                }
                selectedTab = newValue
            }
        )
    }

    private func popToRoot(_ tab: AppTab) {
        switch tab {
        case .overview:
            overviewNavID = UUID()
        case .apps:
            appsNavID = UUID()
        case .settings:
            settingsNavID = UUID()
        }
    }
}
