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
                    #endif
                }
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1280, height: 860)
        #endif
    }
}
