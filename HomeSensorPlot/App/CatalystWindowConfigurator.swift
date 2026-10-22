import Foundation

#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

enum CatalystWindowConfigurator {
    private static let widthKey = "windowFrameWidth"
    private static let heightKey = "windowFrameHeight"
    private static let originXKey = "windowFrameOriginX"
    private static let originYKey = "windowFrameOriginY"
    private static let defaultSize = CGSize(width: 1280, height: 860)
    private static let minimumSize = CGSize(width: 720, height: 480)

    private static var saveWorkItem: DispatchWorkItem?
    private static var didApplyRestoredSize = false
    private static var suppressFrameCapture = false
    private static var createInFlight = false
    private static var createGeneration = 0

    /// Raise resize limits. Restore the saved size once, for a single newly placed window.
    static func configure() {
        allowResizing()
        applyStoredSizeIfAlone()
        // The first layout pass sometimes has no real frame yet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            allowResizing()
            applyStoredSizeIfAlone()
        }
    }

    /// Fully tear down Catalyst window scenes. Prefer this over `isHidden` — hiding
    /// leaves a blank chrome on Mac Catalyst (paint → empty frame).
    static func dismissMainWindows() {
        let sessions = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map(\.session)
        for session in sessions {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
        }
    }

    /// Menu bar → create a window. Called only when AppKit reports nothing on screen.
    /// A closed window still occupies a scene at its last size; discard those before
    /// creating, or SwiftUI reuses the corpse and the new window flashes away.
    static func showMainWindow() {
        guard !createInFlight else {
            NSLog("HomeSensorPlot: showMainWindow already creating a window")
            return
        }

        createInFlight = true
        let generation = createGeneration
        let stale = contentScenes()
        if stale.isEmpty {
            beginCreatingWindow(generation: generation, sceneCountBefore: UIApplication.shared.connectedScenes.count)
            return
        }

        NSLog("HomeSensorPlot: showMainWindow discarding %d closed scene(s)", stale.count)
        let staleSessions = Set(stale.map { ObjectIdentifier($0.session) })
        for scene in stale {
            let window = largestContentWindow(in: scene)
            NSLog(
                "HomeSensorPlot: closed scene state=%@ hidden=%d frame=%@",
                activationLabel(scene.activationState),
                window?.isHidden == true ? 1 : 0,
                NSCoder.string(for: window?.frame ?? .zero)
            )
            UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil) { error in
                NSLog("HomeSensorPlot: destroy closed scene failed: %@", error.localizedDescription)
            }
        }
        waitForClosedScenesToLeave(staleSessions, generation: generation, attemptsLeft: 10)
    }

    private static func waitForClosedScenesToLeave(
        _ staleSessions: Set<ObjectIdentifier>,
        generation: Int,
        attemptsLeft: Int
    ) {
        guard generation == createGeneration else { return }
        let stillConnected = UIApplication.shared.connectedScenes.contains {
            staleSessions.contains(ObjectIdentifier($0.session))
        }
        if stillConnected, attemptsLeft > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                waitForClosedScenesToLeave(
                    staleSessions,
                    generation: generation,
                    attemptsLeft: attemptsLeft - 1
                )
            }
            return
        }
        beginCreatingWindow(
            generation: generation,
            sceneCountBefore: UIApplication.shared.connectedScenes.count
        )
    }

    private static func beginCreatingWindow(generation: Int, sceneCountBefore: Int) {
        guard generation == createGeneration else { return }
        didApplyRestoredSize = false
        let canOpenViaSwiftUI = WindowOpenRegistrarStore.openMain != nil
        if canOpenViaSwiftUI {
            NSLog("HomeSensorPlot: showMainWindow via openWindow(id: main)")
            WindowOpenRegistrarStore.openMain?()
        } else {
            requestNewScene()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard generation == createGeneration else { return }
            createInFlight = false
            if visibleContentWindow() != nil { return }
            guard canOpenViaSwiftUI,
                  UIApplication.shared.connectedScenes.count == sceneCountBefore
            else { return }
            NSLog("HomeSensorPlot: openWindow produced no window, requesting a scene")
            requestNewScene()
        }
    }

    private static func requestNewScene() {
        NSLog("HomeSensorPlot: showMainWindow creating a new scene session")
        let activity = NSUserActivity(activityType: "com.cayla.HomeSensorPlot.openMainWindow")
        UIApplication.shared.requestSceneSessionActivation(
            nil,
            userActivity: activity,
            options: nil
        ) { error in
            NSLog("HomeSensorPlot: create scene failed: %@", error.localizedDescription)
        }
    }

    static func allowResizing() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.sizeRestrictions?.minimumSize = minimumSize
            windowScene.sizeRestrictions?.maximumSize = CGSize(width: 10_000, height: 10_000)
        }
    }

    static func rememberCurrentFrame() {
        guard !suppressFrameCapture else { return }
        saveWorkItem?.cancel()
        let work = DispatchWorkItem {
            guard !suppressFrameCapture, let frame = currentSystemFrame() else { return }
            let defaults = UserDefaults.standard
            defaults.set(frame.size.width, forKey: widthKey)
            defaults.set(frame.size.height, forKey: heightKey)
            defaults.set(frame.origin.x, forKey: originXKey)
            defaults.set(frame.origin.y, forKey: originYKey)
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Apply the saved frame only when there is a single content scene that has not
    /// already been restored. Extra windows keep the frame macOS gave them.
    private static func applyStoredSizeIfAlone() {
        guard !didApplyRestoredSize else { return }
        let scenes = contentScenes()
        guard scenes.count == 1,
              let windowScene = scenes.first,
              largestContentWindow(in: windowScene) != nil
        else { return }
        applyStoredSize(to: windowScene)
    }

    private static func applyStoredSize(to windowScene: UIWindowScene) {
        let size = clamped(storedSize() ?? defaultSize)
        let current = windowScene.effectiveGeometry.systemFrame
        let origin = storedOrigin() ?? current.origin
        let frame = CGRect(origin: origin, size: size)
        if !current.isNull, framesMatch(current, frame) {
            didApplyRestoredSize = true
            return
        }
        // No saved origin yet, and this window has not been given a frame. Wait for
        // the retry instead of pinning it to (0, 0).
        let unplaced = storedOrigin() == nil
            && (current.isNull || current.origin == .zero)
            && (current.width < minimumSize.width || current.height < minimumSize.height)
        guard !unplaced else { return }

        NSLog("HomeSensorPlot: restoring window frame %@", NSCoder.string(for: frame))
        suppressFrameCapture = true
        let preferences = UIWindowScene.GeometryPreferences.Mac(systemFrame: frame)
        windowScene.requestGeometryUpdate(preferences) { error in
            NSLog("HomeSensorPlot: window geometry update failed: %@", error.localizedDescription)
        }
        didApplyRestoredSize = true
        let target = frame
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            suppressFrameCapture = false
            // Don't let the new window's default top-left replace a saved origin
            // if the restore has not landed yet.
            guard let settled = currentSystemFrame(), framesMatch(settled, target) else { return }
            rememberCurrentFrame()
        }
    }

    /// Big enough to be the app window, not a keyboard or text-effects window.
    private static func isContentWindow(_ window: UIWindow) -> Bool {
        window.bounds.width >= 400 && window.bounds.height >= 300
    }

    private static func isForeground(_ scene: UIWindowScene) -> Bool {
        switch scene.activationState {
        case .foregroundActive, .foregroundInactive:
            return true
        default:
            return false
        }
    }

    /// On screen right now. A closed window stays in `connectedScenes` at its last size.
    private static func visibleContentWindow() -> UIWindow? {
        let windows = contentScenes()
            .filter(isForeground)
            .flatMap { $0.windows.filter { isContentWindow($0) && !$0.isHidden } }
        return windows.max {
            ($0.bounds.width * $0.bounds.height) < ($1.bounds.width * $1.bounds.height)
        }
    }

    private static func activationLabel(_ state: UIScene.ActivationState) -> String {
        switch state {
        case .unattached: return "unattached"
        case .foregroundActive: return "foregroundActive"
        case .foregroundInactive: return "foregroundInactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    private static func contentScenes() -> [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { scene in
            guard let windowScene = scene as? UIWindowScene else { return nil }
            return windowScene.windows.contains(where: isContentWindow) ? windowScene : nil
        }
    }

    private static func largestContentWindow(in windowScene: UIWindowScene? = nil) -> UIWindow? {
        let windows: [UIWindow]
        if let windowScene {
            windows = windowScene.windows.filter(isContentWindow)
        } else {
            windows = contentScenes().flatMap { $0.windows.filter(isContentWindow) }
        }
        return windows.max {
            ($0.bounds.width * $0.bounds.height) < ($1.bounds.width * $1.bounds.height)
        }
    }

    private static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 1
            && abs(lhs.origin.y - rhs.origin.y) < 1
            && abs(lhs.width - rhs.width) < 1
            && abs(lhs.height - rhs.height) < 1
    }

    private static func storedOrigin() -> CGPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: originXKey) != nil,
              defaults.object(forKey: originYKey) != nil
        else { return nil }
        return CGPoint(x: defaults.double(forKey: originXKey), y: defaults.double(forKey: originYKey))
    }

    /// System frame of the foreground content window. This is the coordinate space
    /// `GeometryPreferences.Mac.systemFrame` writes back into.
    private static func currentSystemFrame() -> CGRect? {
        let scenes = contentScenes().filter(isForeground)
        let scene = scenes.first { $0.windows.contains(where: \.isKeyWindow) } ?? scenes.first
        guard let scene else { return nil }
        let frame = scene.effectiveGeometry.systemFrame
        guard frame.width >= minimumSize.width, frame.height >= minimumSize.height else { return nil }
        return frame
    }

    private static func storedSize() -> CGSize? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: widthKey) != nil,
              defaults.object(forKey: heightKey) != nil
        else { return nil }
        return CGSize(
            width: defaults.double(forKey: widthKey),
            height: defaults.double(forKey: heightKey)
        )
    }

    private static func clamped(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(minimumSize.width, size.width),
            height: max(minimumSize.height, size.height)
        )
    }

}

/// Invisible view that reports UIWindow size changes so we can persist them.
struct CatalystWindowSizeObserver: UIViewRepresentable {
    final class View: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            CatalystWindowConfigurator.rememberCurrentFrame()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CatalystWindowConfigurator.rememberCurrentFrame()
        }
    }

    func makeUIView(context: Context) -> View { View() }
    func updateUIView(_ uiView: View, context: Context) {}
}
#endif
