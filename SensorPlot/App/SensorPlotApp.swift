import SwiftUI

@main
struct SensorPlotApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("SensorPlot") {
            ContentView()
                .environmentObject(appState)
                #if targetEnvironment(macCatalyst)
                .background(CatalystWindowSizeObserver())
                #endif
                .onAppear {
                    appState.start()
                    #if targetEnvironment(macCatalyst)
                    CatalystWindowConfigurator.configure()
                    let pluginOK = MacOSPluginBootstrap.start(appState: appState)
                    if pluginOK {
                        // Only tuck the window away when the menu bar handle exists.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            CatalystWindowConfigurator.hideMainWindows()
                        }
                    } else {
                        appState.lastRefreshError =
                            "Menu bar plugin failed to load — window kept visible for debugging."
                    }
                    #endif
                }
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1280, height: 860)
        #endif
    }
}
