import Foundation

/// Cross-boundary menu actions (AppKit plugin → Catalyst host).
/// Compiled into both the app and `macOSBridge` so notification names stay in sync.
enum MenuBarNotifications {
    static let openWindow = Notification.Name("com.cayla.HomeSensorPlot.menu.openWindow")
    static let quit = Notification.Name("com.cayla.HomeSensorPlot.menu.quit")
}
