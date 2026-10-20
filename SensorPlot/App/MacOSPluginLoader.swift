import Foundation

#if targetEnvironment(macCatalyst)
import UIKit

/// Loads the native AppKit `macOSBridge.bundle` (status item) into the Catalyst host.
enum MacOSPluginLoader {
    static func loadController() -> iOS2Mac? {
        let bundleFileName = "macOSBridge.bundle"
        var bundleURL: URL?

        if let pluginsURL = Bundle.main.builtInPlugInsURL {
            let path = pluginsURL.appendingPathComponent(bundleFileName)
            if FileManager.default.fileExists(atPath: path.path) {
                bundleURL = path
            }
        }
        if bundleURL == nil, let resourcesURL = Bundle.main.resourceURL {
            let path = resourcesURL.appendingPathComponent(bundleFileName)
            if FileManager.default.fileExists(atPath: path.path) {
                bundleURL = path
            }
        }

        guard let bundleURL else {
            NSLog("SensorPlot: macOSBridge.bundle not found in PlugIns or Resources")
            return nil
        }
        guard let bundle = Bundle(url: bundleURL) else {
            NSLog("SensorPlot: failed to open macOSBridge.bundle at %@", bundleURL.path)
            return nil
        }
        bundle.load()
        guard let pluginClass = bundle.principalClass as? iOS2Mac.Type else {
            NSLog(
                "SensorPlot: macOSBridge principalClass missing or wrong type: %@",
                String(describing: bundle.principalClass)
            )
            return nil
        }
        return pluginClass.init()
    }
}

/// ObjC-facing host that the menu bar plugin calls into (calls hop to the main actor).
final class MacBridgeHost: NSObject, Mac2iOS {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func macBridgeForceCollect() {
        Task { @MainActor in
            guard let appState else { return }
            await appState.collector.forceCollectOnce()
            await appState.refreshUI()
            appState.pushStatusToMacBridge()
        }
    }

    func macBridgeShowWindow() {
        Task { @MainActor in
            CatalystWindowConfigurator.showMainWindow()
        }
    }

    func macBridgeQuit() {
        Task { @MainActor in
            appState?.stop()
            exit(0)
        }
    }
}

/// Owns the loaded plugin for the life of the process.
enum MacOSPluginBootstrap {
    private(set) static var controller: iOS2Mac?
    private static var host: MacBridgeHost?

    @MainActor
    static func start(appState: AppState) {
        if controller == nil {
            guard let loaded = MacOSPluginLoader.loadController() else { return }
            controller = loaded
            NSLog("SensorPlot: macOSBridge status item ready")
        }
        let host = MacBridgeHost(appState: appState)
        self.host = host
        controller?.iOSBridge = host
        appState.pushStatusToMacBridge()
    }
}
#endif
