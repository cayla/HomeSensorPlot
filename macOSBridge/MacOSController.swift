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
    private var frameSaveWorkItem: DispatchWorkItem?

    @objc public required override init() {
        super.init()
        configureStatusItem()
        rebuildMenu()
        observeContentWindowFrames()
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
        // UIKit keeps a closed Catalyst window in `connectedScenes` at its last size.
        // Ordering that forward flickers. AppKit's window list is the one that matches
        // what is actually on screen.
        if let window = contentWindows().first(where: { $0.isVisible || $0.isMiniaturized }) {
            NSLog(
                "HomeSensorPlot macOSBridge: ordering existing window front %@",
                NSStringFromRect(window.frame)
            )
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }
        NSLog("HomeSensorPlot macOSBridge: no visible window, asking the host to create one")
        NotificationCenter.default.post(name: MenuBarNotifications.openWindow, object: nil)
        // The window is created after this returns, and the frame restore can land
        // it behind whatever was already frontmost. Keep pulling it forward until then.
        orderFrontWhileOpening(attemptsLeft: 14)
    }

    private func orderFrontWhileOpening(attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            if let window = self.contentWindows().first(where: { $0.isVisible || $0.isMiniaturized }) {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
            }
            if attemptsLeft > 0 {
                self.orderFrontWhileOpening(attemptsLeft: attemptsLeft - 1)
            }
        }
    }

    private func contentWindows() -> [NSWindow] {
        NSApp.windows.filter { window in
            window.frame.width >= 400
                && window.frame.height >= 300
                && window.level == .normal
                && !window.isSheet
        }
    }

    @objc private func quit() {
        NotificationCenter.default.post(name: MenuBarNotifications.quit, object: nil)
    }

    /// UIKit does not relayout when a window is dragged, so the host never saw the new origin.
    /// AppKit posts move/resize/close for the real `NSWindow`.
    private func observeContentWindowFrames() {
        let center = NotificationCenter.default
        for name in [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.willCloseNotification,
        ] {
            center.addObserver(self, selector: #selector(contentWindowFrameChanged(_:)), name: name, object: nil)
        }
    }

    @objc private func contentWindowFrameChanged(_ note: Notification) {
        guard let window = note.object as? NSWindow, isContentWindow(window) else { return }
        if note.name == NSWindow.willCloseNotification {
            frameSaveWorkItem?.cancel()
            saveContentFrame(of: window)
            return
        }
        frameSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self, weak window] in
            guard let self, let window else { return }
            self.saveContentFrame(of: window)
        }
        frameSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func isContentWindow(_ window: NSWindow) -> Bool {
        contentWindows().contains { $0 === window }
    }

    private func saveContentFrame(of window: NSWindow) {
        guard let primary = NSScreen.screens.first else { return }
        let system = WindowFrameStore.systemFrame(
            fromAppKitFrame: window.frame,
            primaryScreenMaxY: primary.frame.maxY
        )
        guard system.width >= 720, system.height >= 480 else { return }
        WindowFrameStore.save(system)
        NSLog(
            "HomeSensorPlot macOSBridge: saved window frame %@ (appkit %@)",
            NSStringFromRect(system),
            NSStringFromRect(window.frame)
        )
    }
}
