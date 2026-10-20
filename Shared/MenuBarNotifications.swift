import Foundation

/// Cross-boundary menu actions (AppKit plugin → Catalyst host).
/// Use raw strings so both targets can post/observe without sharing Swift types.
enum MenuBarNotifications {
    static let openWindow = Notification.Name("com.cayla.HomeSensorPlot.menu.openWindow")
    static let collectNow = Notification.Name("com.cayla.HomeSensorPlot.menu.collectNow")
    static let quit = Notification.Name("com.cayla.HomeSensorPlot.menu.quit")
}
