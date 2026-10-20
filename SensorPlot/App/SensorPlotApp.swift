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
                    MacOSPluginBootstrap.start(appState: appState)
                    // Stay menu-bar first: don't leave a Dock/Mission Control window hanging around.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        CatalystWindowConfigurator.hideMainWindows()
                    }
                    #endif
                }
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1280, height: 860)
        #endif
    }
}
