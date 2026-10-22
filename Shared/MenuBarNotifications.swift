import Foundation

/// Cross-boundary menu actions (AppKit plugin → Catalyst host).
/// Compiled into both the app and `macOSBridge` so notification names stay in sync.
enum MenuBarNotifications {
    static let openWindow = Notification.Name("com.cayla.HomeSensorPlot.menu.openWindow")
    static let quit = Notification.Name("com.cayla.HomeSensorPlot.menu.quit")
}

/// Last window frame, shared by the AppKit plugin (writer) and the Catalyst host (reader).
/// Stored as a `UIWindowScene` system frame: origin at the top-left of the main display, y down.
enum WindowFrameStore {
    static let widthKey = "windowFrameWidth"
    static let heightKey = "windowFrameHeight"
    static let originXKey = "windowFrameOriginX"
    static let originYKey = "windowFrameOriginY"

    /// AppKit frames use the bottom-left of the primary screen, with y growing up.
    static func systemFrame(fromAppKitFrame frame: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: primaryScreenMaxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    static func save(_ frame: CGRect) {
        let defaults = UserDefaults.standard
        defaults.set(frame.size.width, forKey: widthKey)
        defaults.set(frame.size.height, forKey: heightKey)
        defaults.set(frame.origin.x, forKey: originXKey)
        defaults.set(frame.origin.y, forKey: originYKey)
    }

    static func load() -> CGRect? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: widthKey) != nil,
              defaults.object(forKey: heightKey) != nil,
              defaults.object(forKey: originXKey) != nil,
              defaults.object(forKey: originYKey) != nil
        else { return nil }
        return CGRect(
            x: defaults.double(forKey: originXKey),
            y: defaults.double(forKey: originYKey),
            width: defaults.double(forKey: widthKey),
            height: defaults.double(forKey: heightKey)
        )
    }
}
