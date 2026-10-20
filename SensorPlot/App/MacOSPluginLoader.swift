import Foundation

#if targetEnvironment(macCatalyst)
import UIKit

/// Thin proxy so the Catalyst host can talk to the AppKit plugin without sharing a Swift
/// protocol across module boundaries (that breaks `as?` casts).
final class MacOSControllerProxy: NSObject, iOS2Mac {
    private let target: NSObject

    init?(target: NSObject) {
        let statusSel = NSSelectorFromString("macBridgeUpdateStatus:symbolName:")
        let exporterSel = NSSelectorFromString("macBridgeUpdateExporter:")
        guard target.responds(to: statusSel), target.responds(to: exporterSel) else {
            NSLog("SensorPlot: plugin missing expected selectors")
            return nil
        }
        self.target = target
        super.init()
    }

    var iOSBridge: Mac2iOS? {
        get { target.value(forKey: "iOSBridge") as? Mac2iOS }
        set { target.setValue(newValue, forKey: "iOSBridge") }
    }

    func macBridgeUpdateStatus(_ text: String, symbolName: String) {
        target.perform(
            NSSelectorFromString("macBridgeUpdateStatus:symbolName:"),
            with: text,
            with: symbolName
        )
    }

    func macBridgeUpdateExporter(_ address: String) {
        target.perform(NSSelectorFromString("macBridgeUpdateExporter:"), with: address)
    }
}

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
        NSLog("SensorPlot: loading macOSBridge from %@", bundleURL.path)
        guard let bundle = Bundle(url: bundleURL) else {
            NSLog("SensorPlot: failed to open macOSBridge.bundle")
            return nil
        }
        if !bundle.isLoaded {
            bundle.load()
        }

        let principal: AnyClass? = bundle.principalClass
            ?? NSClassFromString("MacOSController")
            ?? bundle.classNamed("MacOSController")
        guard let objectType = principal as? NSObject.Type else {
            NSLog(
                "SensorPlot: macOSBridge principalClass missing: %@",
                String(describing: bundle.principalClass)
            )
            return nil
        }
        let instance = objectType.init()
        guard let proxy = MacOSControllerProxy(target: instance) else { return nil }
        return proxy
    }
}

/// ObjC-facing host that the menu bar plugin calls into (calls hop to the main actor).
final class MacBridgeHost: NSObject, Mac2iOS {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    @objc func macBridgeForceCollect() {
        Task { @MainActor in
            guard let appState else { return }
            await appState.collector.forceCollectOnce()
            await appState.refreshUI()
            appState.pushStatusToMacBridge()
        }
    }

    @objc func macBridgeShowWindow() {
        Task { @MainActor in
            CatalystWindowConfigurator.showMainWindow()
        }
    }

    @objc func macBridgeQuit() {
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
    private(set) static var didLoad = false

    @MainActor
    @discardableResult
    static func start(appState: AppState) -> Bool {
        if controller == nil {
            guard let loaded = MacOSPluginLoader.loadController() else {
                didLoad = false
                return false
            }
            controller = loaded
            didLoad = true
            NSLog("SensorPlot: macOSBridge status item ready")
        }
        let host = MacBridgeHost(appState: appState)
        self.host = host
        controller?.iOSBridge = host
        appState.pushStatusToMacBridge()
        return didLoad
    }
}
#endif
