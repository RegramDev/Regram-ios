import UIKit

// A decorative window, excluded from app presentation and keyboard window discovery.
final class RGAppBadgeWindow: UIWindow {
    override var canBecomeKey: Bool { false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return nil
    }
}

private final class RGAppBadgeRootController: UIViewController {
    private weak var hostWindow: UIWindow?

    init(hostWindow: UIWindow) {
        self.hostWindow = hostWindow
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        self.view = view
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        self.hostWindow?.rootViewController?.preferredStatusBarStyle ?? .default
    }
    override var prefersStatusBarHidden: Bool {
        self.hostWindow?.rootViewController?.prefersStatusBarHidden ?? false
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        self.hostWindow?.rootViewController?.supportedInterfaceOrientations ?? .allButUpsideDown
    }
    override var prefersHomeIndicatorAutoHidden: Bool {
        self.hostWindow?.rootViewController?.prefersHomeIndicatorAutoHidden ?? false
    }
}

/// iOS 27 compatibility path for badges drawn in the Dynamic Island screenshot area. Moving the
/// actual image view retains the existing image selector, App Lock alpha and visibility controls.
final class RGAppBadgeOverlay {
    private let badgeView: UIImageView
    private weak var hostWindow: UIWindow?
    private var window: RGAppBadgeWindow?
    private var observers: [NSObjectProtocol] = []
    private var sceneIsDeactivating = false

    init(badgeView: UIImageView) {
        self.badgeView = badgeView
        for name in [UIScene.didActivateNotification, UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification, UIScene.didDisconnectNotification] {
            self.observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self, let scene = notification.object as? UIWindowScene, scene === self.window?.windowScene else { return }
                if notification.name == UIScene.didActivateNotification {
                    self.sceneIsDeactivating = false
                    self.updateVisibility()
                } else {
                    // Hide immediately on deactivation, before the activationState necessarily changes.
                    self.sceneIsDeactivating = true
                    self.window?.isHidden = true
                }
            })
        }
    }

    deinit {
        self.observers.forEach { NotificationCenter.default.removeObserver($0) }
        self.window?.isHidden = true
        self.window?.rootViewController = nil
    }

    func update(hostWindow: UIWindow?, fallbackView: UIView, enabled: Bool) {
        guard enabled, let hostWindow, let scene = hostWindow.windowScene else {
            self.restore(to: fallbackView)
            return
        }
        self.hostWindow = hostWindow
        if self.window?.windowScene !== scene {
            self.restore(to: fallbackView)
            self.hostWindow = hostWindow
            self.sceneIsDeactivating = scene.activationState != .foregroundActive
            let window = RGAppBadgeWindow(windowScene: scene)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.accessibilityElementsHidden = true
            window.rootViewController = RGAppBadgeRootController(hostWindow: hostWindow)
            self.window = window
        }
        guard let window = self.window, let container = window.rootViewController?.view else { return }
        // zPosition only orders layers inside one window; a separate window establishes the
        // rendering boundary without changing the navigation bar's blur or the main window's level.
        window.windowLevel = UIWindow.Level(rawValue: max(UIWindow.Level.statusBar.rawValue, hostWindow.windowLevel.rawValue) + 1.0)
        window.frame = hostWindow.frame
        container.frame = window.bounds
        if self.badgeView.superview !== container {
            container.addSubview(self.badgeView)
        }
        self.updateVisibility()
    }

    private func restore(to fallbackView: UIView) {
        self.window?.isHidden = true
        if self.badgeView.superview !== fallbackView {
            fallbackView.addSubview(self.badgeView)
        }
        self.window?.rootViewController = nil
        self.window = nil
        self.hostWindow = nil
    }

    func updateVisibility() {
        guard let window = self.window else { return }
        window.isHidden = window.windowScene?.activationState != .foregroundActive
            || self.sceneIsDeactivating
            || self.hostWindow?.isHidden != false
            || self.badgeView.isHidden
            || self.badgeView.image == nil
    }
}
