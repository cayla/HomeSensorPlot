import Foundation

/// Catalyst host → macOS plugin (status item). Implemented by `MacOSController`.
@objc public protocol iOS2Mac: NSObjectProtocol {
    var iOSBridge: Mac2iOS? { get set }
    func macBridgeUpdateStatus(_ text: String, symbolName: String)
    func macBridgeUpdateExporter(_ address: String)
}

/// macOS plugin → Catalyst host. Implemented by `MacBridgeHost`.
@objc public protocol Mac2iOS: NSObjectProtocol {
    func macBridgeForceCollect()
    func macBridgeShowWindow()
    func macBridgeQuit()
}
