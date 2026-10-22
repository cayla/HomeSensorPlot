import Foundation

#if targetEnvironment(macCatalyst)
import UIKit

/// Thin proxy so the Catalyst host can push status into the AppKit plugin.
final class MacOSControllerProxy: NSObject, iOS2Mac {
    private let target: NSObject

    init?(target: NSObject) {
        let statusSel = NSSelectorFromString("macBridgeUpdateStatus:symbolName:")
        let exporterSel = NSSelectorFromString("macBridgeUpdateExporter:")
        guard target.responds(to: statusSel), target.responds(to: exporterSel) else {
            NSLog("HomeSensorPlot: plugin missing expected selectors")
            return nil
        }
        self.target = target
        super.init()
    }

    /// Unused — menu actions use NotificationCenter now.
    var iOSBridge: Mac2iOS? {
        get { nil }
        set {}
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
            NSLog("HomeSensorPlot: macOSBridge.bundle not found in PlugIns or Resources")
            return nil
        }
        NSLog("HomeSensorPlot: loading macOSBridge from %@", bundleURL.path)
        guard let bundle = Bundle(url: bundleURL) else {
            NSLog("HomeSensorPlot: failed to open macOSBridge.bundle")
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
                "HomeSensorPlot: macOSBridge principalClass missing: %@",
                String(describing: bundle.principalClass)
            )
            return nil
        }
        let instance = objectType.init()
        return MacOSControllerProxy(target: instance)
    }
}

/// Owns the loaded plugin and menu-bar notification observers.
enum MacOSPluginBootstrap {
    private(set) static var controller: iOS2Mac?
    private(set) static var didLoad = false
    private static var observers: [NSObjectProtocol] = []
    private static weak var appState: AppState?

    @MainActor
    @discardableResult
    static func start(appState: AppState) -> Bool {
        self.appState = appState

        if controller == nil {
            guard let loaded = MacOSPluginLoader.loadController() else {
                didLoad = false
                return false
            }
            controller = loaded
            didLoad = true
            installMenuObservers()
            NSLog("HomeSensorPlot: macOSBridge status item ready")
        }

        appState.pushStatusToMacBridge()
        return didLoad
    }

    @MainActor
    private static func installMenuObservers() {
        guard observers.isEmpty else { return }

        observers.append(
            NotificationCenter.default.addObserver(
                forName: MenuBarNotifications.openWindow,
                object: nil,
                queue: .main
            ) { _ in
                NSLog("HomeSensorPlot: menu Open HomeSensorPlot")
                CatalystWindowConfigurator.showMainWindow()
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: MenuBarNotifications.quit,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    appState?.stop()
                    exit(0)
                }
            }
        )
    }
}
#endif
