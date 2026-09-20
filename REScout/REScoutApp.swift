import SwiftUI

@main
struct REScoutApp: App {
    @StateObject private var store = DeviceInfoStore()
    @ObservedObject private var settings = AppSettingsStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(settings)
                .onAppear { store.start() }
                .onChange(of: scenePhase) { phase in
                    store.setSceneActive(phase == .active)
                }
        }
    }
}
