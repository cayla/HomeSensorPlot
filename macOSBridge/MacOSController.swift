import AppKit
import Foundation

/// Native macOS plugin entry point — owns the menu bar status item.
/// Speaks to the Catalyst host via NotificationCenter (reliable across the bundle boundary).
@objc(MacOSController)
public final class MacOSController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let exporterMenuItem = NSMenuItem(title: "Exporter —", action: nil, keyEquivalent: "")

    @objc public required override init() {
        super.init()
        configureStatusItem()
        rebuildMenu()
        NSLog("HomeSensorPlot macOSBridge: status item created")
    }

    @objc public func macBridgeUpdateStatus(_ text: String, symbolName: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusMenuItem.title = text
            if let button = self.statusItem.button {
                let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: text)
                image?.isTemplate = true
                button.image = image
                button.toolTip = "HomeSensorPlot — \(text)"
            }
        }
    }

    @objc public func macBridgeUpdateExporter(_ address: String) {
        DispatchQueue.main.async { [weak self] in
            self?.exporterMenuItem.title = "Exporter \(address)"
        }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "sensor.tag.radiowaves.forward.fill",
                accessibilityDescription: "HomeSensorPlot"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "HomeSensorPlot"
        }
        statusItem.menu = menu
        menu.delegate = self
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        statusMenuItem.isEnabled = false
        exporterMenuItem.isEnabled = false

        menu.addItem(menuItem("Open HomeSensorPlot", action: #selector(openWindow), key: "o"))
        menu.addItem(.separator())
        menu.addItem(statusMenuItem)
        menu.addItem(exporterMenuItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit HomeSensorPlot", action: #selector(quit), key: "q"))
    }

    private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: MenuBarNotifications.openWindow, object: nil)
    }

    @objc private func quit() {
        NotificationCenter.default.post(name: MenuBarNotifications.quit, object: nil)
    }
}
