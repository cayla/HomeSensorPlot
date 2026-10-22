import Foundation

#if targetEnvironment(macCatalyst)
import UIKit

enum CatalystWindowConfigurator {
    private static let defaultSize = CGSize(width: 1280, height: 860)
    private static let minimumSize = CGSize(width: 720, height: 480)

    private static var didApplyRestoredFrame = false
    private static var restoreAttempts = 0
    /// Captured before the new window exists, so its default placement cannot overwrite the saved origin.
    private static var pendingRestoreFrame: CGRect?
    private static var createInFlight = false
    private static var createGeneration = 0

    /// Raise resize limits and put a new window back where it was last closed.
    /// The system's own placement lands after the first layout, so this retries briefly.
    static func configure() {
        allowResizing()
        applyStoredFrameIfNeeded()
        for delay in [0.25, 0.6, 1.1] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                allowResizing()
                applyStoredFrameIfNeeded()
            }
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
        didApplyRestoredFrame = false
        restoreAttempts = 0
        pendingRestoreFrame = WindowFrameStore.load()
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

    /// Apply the saved frame only while there is a single content scene.
    /// Extra windows keep the frame macOS gave them.
    private static func applyStoredFrameIfNeeded() {
        guard !didApplyRestoredFrame else { return }
        let scenes = contentScenes()
        guard scenes.count == 1,
              let windowScene = scenes.first,
              let window = largestContentWindow(in: windowScene)
        else { return }
        window.isHidden = false
        window.makeKeyAndVisible()

        let saved = pendingRestoreFrame ?? WindowFrameStore.load()
        let size = clamped(saved?.size ?? defaultSize)
        let current = windowScene.effectiveGeometry.systemFrame
        let origin = saved?.origin ?? current.origin
        let frame = CGRect(origin: origin, size: size)
        if !current.isNull, framesMatch(current, frame) {
            didApplyRestoredFrame = true
            NSLog("HomeSensorPlot: window frame already %@", NSCoder.string(for: current))
            return
        }
        guard restoreAttempts < 4 else {
            didApplyRestoredFrame = true
            NSLog("HomeSensorPlot: giving up window frame restore at %@", NSCoder.string(for: current))
            return
        }
        let unplaced = saved == nil
            && (current.isNull || current.width < minimumSize.width || current.height < minimumSize.height)
        guard !unplaced else { return }

        restoreAttempts += 1
        NSLog(
            "HomeSensorPlot: restoring window frame %@ (currently %@)",
            NSCoder.string(for: frame),
            NSCoder.string(for: current)
        )
        let preferences = UIWindowScene.GeometryPreferences.Mac(systemFrame: frame)
        windowScene.requestGeometryUpdate(preferences) { error in
            NSLog("HomeSensorPlot: window geometry update failed: %@", error.localizedDescription)
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

    private static func clamped(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(minimumSize.width, size.width),
            height: max(minimumSize.height, size.height)
        )
    }

}
#endif
