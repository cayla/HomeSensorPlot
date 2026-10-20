import AppKit
import Foundation

/// Native macOS plugin entry point — owns the menu bar status item.
/// HomeKit stays in the Catalyst host; this bundle is AppKit-only (ItsyHome-style split).
@objc(MacOSController)
public final class MacOSController: NSObject, iOS2Mac, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let exporterMenuItem = NSMenuItem(title: "Exporter —", action: nil, keyEquivalent: "")

    @objc public weak var iOSBridge: Mac2iOS?

    @objc public required override init() {
        super.init()
        configureStatusItem()
        rebuildMenu()
    }

    public func macBridgeUpdateStatus(_ text: String, symbolName: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusMenuItem.title = text
            if let button = self.statusItem.button {
                let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: text)
                image?.isTemplate = true
                button.image = image
                button.toolTip = "SensorPlot — \(text)"
            }
        }
    }

    public func macBridgeUpdateExporter(_ address: String) {
        DispatchQueue.main.async { [weak self] in
            self?.exporterMenuItem.title = "Exporter \(address)"
        }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "sensor.tag.radiowaves.forward.fill",
                accessibilityDescription: "SensorPlot"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "SensorPlot"
        }
        statusItem.menu = menu
        menu.delegate = self
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        statusMenuItem.isEnabled = false
        exporterMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(exporterMenuItem)
        menu.addItem(.separator())

        menu.addItem(menuItem("Open SensorPlot", action: #selector(openWindow), key: "o"))
        menu.addItem(menuItem("Collect Now", action: #selector(collectNow), key: "r"))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit SensorPlot", action: #selector(quit), key: "q"))
    }

    private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openWindow() {
        iOSBridge?.macBridgeShowWindow()
    }

    @objc private func collectNow() {
        iOSBridge?.macBridgeForceCollect()
    }

    @objc private func quit() {
        iOSBridge?.macBridgeQuit()
    }
}
