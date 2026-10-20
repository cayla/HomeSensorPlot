import Foundation

/// Catalyst host → macOS plugin (status item). Implemented by `MacOSController`.
@objc public protocol iOS2Mac: NSObjectProtocol {
    var iOSBridge: Mac2iOS? { get set }
    func macBridgeUpdateStatus(_ text: String, symbolName: String)
    func macBridgeUpdateExporter(_ address: String)
}

/// Kept for status push typing; menu actions use `MenuBarNotifications` now.
@objc public protocol Mac2iOS: NSObjectProtocol {}
