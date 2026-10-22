import SwiftUI

@main
struct HomeSensorPlotApp: App {
    @StateObject private var appState: AppState

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        Task { @MainActor in
            state.start()
            #if targetEnvironment(macCatalyst)
            if !MacOSPluginBootstrap.start(appState: state) {
                state.lastRefreshError =
                    "Menu bar plugin failed to load — check that macOSBridge.bundle is embedded."
            }
            #endif
        }
    }

    var body: some Scene {
        // Named id so we can re-open after the user closes the window.
        WindowGroup("HomeSensorPlot", id: "main") {
            ContentView()
                .environmentObject(appState)
                #if targetEnvironment(macCatalyst)
                .background(CatalystWindowSizeObserver())
                .background(WindowOpenRegistrar())
                .onAppear {
                    CatalystWindowConfigurator.configure()
                }
                #endif
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1280, height: 860)
        #endif
    }
}

#if targetEnvironment(macCatalyst)
/// Captures SwiftUI `openWindow` while a scene exists.
/// Used only to recreate the window after the last one was closed.
enum WindowOpenRegistrarStore {
    nonisolated(unsafe) static var openMain: (() -> Void)?
}

private struct WindowOpenRegistrar: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                WindowOpenRegistrarStore.openMain = {
                    openWindow(id: "main")
                }
            }
    }
}
#endif
