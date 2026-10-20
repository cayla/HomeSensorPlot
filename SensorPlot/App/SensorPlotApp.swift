import SwiftUI

@main
struct SensorPlotApp: App {
    @StateObject private var appState: AppState

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        // Kick collection/menu bar immediately; window lifecycle is separate.
        Task { @MainActor in
            state.start()
            #if targetEnvironment(macCatalyst)
            _ = MacOSPluginBootstrap.start(appState: state)
            #endif
        }
    }

    var body: some Scene {
        WindowGroup("SensorPlot") {
            ContentView()
                .environmentObject(appState)
                #if targetEnvironment(macCatalyst)
                .background(CatalystWindowSizeObserver())
                .onAppear {
                    Task { @MainActor in
                        appState.start()
                        let pluginOK = MacOSPluginBootstrap.start(appState: appState)
                        if pluginOK {
                            // Destroy the scene — do not isHidden (that leaves blank chrome).
                            CatalystWindowConfigurator.dismissMainWindows()
                        } else {
                            appState.lastRefreshError =
                                "Menu bar plugin failed to load — window kept visible for debugging."
                            CatalystWindowConfigurator.configure()
                        }
                    }
                }
                #endif
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1280, height: 860)
        #endif
    }
}
