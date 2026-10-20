import Foundation

#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

enum CatalystWindowConfigurator {
    private static let widthKey = "windowFrameWidth"
    private static let heightKey = "windowFrameHeight"
    private static let defaultSize = CGSize(width: 1280, height: 860)
    private static let minimumSize = CGSize(width: 720, height: 480)

    private static var saveWorkItem: DispatchWorkItem?
    private static var didApplyRestoredSize = false

    /// Raise resize limits, restore last size (or a sensible default), and start persisting changes.
    static func configure() {
        allowResizing()
        applyStoredOrDefaultSize()
        // Size restrictions / geometry sometimes stick only after the first layout pass.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            allowResizing()
            if !didApplyRestoredSize {
                applyStoredOrDefaultSize()
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

    /// Menu bar → Open SensorPlot (works even after the window was closed).
    static func showMainWindow() {
        didApplyRestoredSize = false
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        NSLog("SensorPlot: showMainWindow — %d scene(s)", scenes.count)

        if let scene = scenes.first {
            for window in scene.windows {
                window.isHidden = false
                window.makeKeyAndVisible()
            }
            UIApplication.shared.requestSceneSessionActivation(
                scene.session,
                userActivity: nil,
                options: nil
            ) { error in
                NSLog("SensorPlot: activate existing scene failed: %@", error.localizedDescription)
            }
            configure()
            return
        }

        // Prefer SwiftUI openWindow if we still have a registrar from a prior scene.
        if let openMain = WindowOpenRegistrarStore.openMain {
            NSLog("SensorPlot: showMainWindow via openWindow(id:)")
            openMain()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: configure)
            return
        }

        let activity = NSUserActivity(activityType: "com.cayla.SensorPlot.openMainWindow")
        UIApplication.shared.requestSceneSessionActivation(
            nil,
            userActivity: activity,
            options: nil
        ) { error in
            NSLog("SensorPlot: create scene failed: %@", error.localizedDescription)
        }
        for delay in [0.15, 0.4, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if !UIApplication.shared.connectedScenes.isEmpty {
                    configure()
                }
            }
        }
    }

    static func allowResizing() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.sizeRestrictions?.minimumSize = minimumSize
            windowScene.sizeRestrictions?.maximumSize = CGSize(width: 10_000, height: 10_000)
        }
    }

    static func rememberCurrentSize() {
        guard let size = currentWindowSize() else { return }
        persist(size: size, debounce: true)
    }

    private static func applyStoredOrDefaultSize() {
        let size = storedSize() ?? defaultSize
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            let origin = windowScene.windows.first?.frame.origin ?? .zero
            let frame = CGRect(origin: origin, size: clamped(size))
            let preferences = UIWindowScene.GeometryPreferences.Mac(systemFrame: frame)
            windowScene.requestGeometryUpdate(preferences) { error in
                NSLog("SensorPlot: window geometry update failed: %@", error.localizedDescription)
            }
            didApplyRestoredSize = true
        }
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

    private static func persist(size: CGSize, debounce: Bool) {
        let clampedSize = clamped(size)
        let save = {
            UserDefaults.standard.set(clampedSize.width, forKey: widthKey)
            UserDefaults.standard.set(clampedSize.height, forKey: heightKey)
        }
        guard debounce else {
            save()
            return
        }
        saveWorkItem?.cancel()
        let work = DispatchWorkItem(block: save)
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private static func clamped(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(minimumSize.width, size.width),
            height: max(minimumSize.height, size.height)
        )
    }

    private static func currentWindowSize() -> CGSize? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  let window = windowScene.windows.first(where: \.isKeyWindow)
                    ?? windowScene.windows.first
            else { continue }
            let size = window.bounds.size
            if size.width > 1, size.height > 1 { return size }
        }
        return nil
    }
}

/// Invisible view that reports UIWindow size changes so we can persist them.
struct CatalystWindowSizeObserver: UIViewRepresentable {
    final class View: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            CatalystWindowConfigurator.rememberCurrentSize()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CatalystWindowConfigurator.rememberCurrentSize()
        }
    }

    func makeUIView(context: Context) -> View { View() }
    func updateUIView(_ uiView: View, context: Context) {}
}
#endif
