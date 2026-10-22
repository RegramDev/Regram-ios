// MARK: Regram — interactive root-tab return without the normal tab-selection scale animation.
import UIKit
import Display

final class RGRootTabBackTransition {
    private weak var host: UIView?
    private weak var destination: UIView?
    private let destinationTransform: CGAffineTransform
    private let snapshot: UIView
    private let dimView = UIView()
    private let width: CGFloat
    private var frameRateLink: SharedDisplayLinkDriver.Link?
    private(set) var progress: CGFloat = 0

    init(host: UIView, destination: UIView, snapshot: UIView, frame: CGRect) {
        self.host = host
        self.destination = destination
        self.destinationTransform = destination.transform
        self.snapshot = snapshot
        self.width = max(1, frame.width)
        self.snapshot.frame = frame
        self.snapshot.isUserInteractionEnabled = false
        self.snapshot.layer.shadowColor = UIColor.black.cgColor
        self.snapshot.layer.shadowOpacity = 0.14
        self.snapshot.layer.shadowRadius = 6
        self.snapshot.layer.shadowOffset = CGSize(width: -3, height: 0)
        // MARK: Regram — the snapshot bounds stay fixed until this transition ends.
        // Avoid deriving a full-screen alpha shadow on every interactive frame.
        self.snapshot.layer.shadowPath = UIBezierPath(rect: self.snapshot.bounds).cgPath
        self.dimView.frame = host.bounds
        self.dimView.backgroundColor = .black
        self.dimView.isUserInteractionEnabled = false
        host.addSubview(self.dimView)
        host.addSubview(self.snapshot)
        update(progress: 0)
        // MARK: Regram — match navigation transitions throughout dragging and settling.
        self.frameRateLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { _ in })
    }

    deinit {
        self.frameRateLink?.invalidate()
    }

    func update(progress: CGFloat) {
        self.progress = min(1, max(0, progress))
        self.snapshot.transform = CGAffineTransform(translationX: width * self.progress, y: 0)
        self.destination?.transform = destinationTransform.translatedBy(x: -width * 0.28 * (1 - self.progress), y: 0)
        self.dimView.alpha = 0.12 * (1 - self.progress)
    }

    func finish(completed: Bool, velocity: CGFloat, completion: @escaping () -> Void) {
        let remaining = completed ? 1 - progress : progress
        let duration = min(0.32, max(0.16, Double(remaining * width / max(400, abs(velocity)))))
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction], animations: {
            self.update(progress: completed ? 1 : 0)
        }, completion: { _ in completion() })
    }

    func remove() {
        self.frameRateLink?.invalidate()
        self.frameRateLink = nil
        snapshot.layer.removeAllAnimations()
        destination?.layer.removeAllAnimations()
        dimView.layer.removeAllAnimations()
        destination?.transform = destinationTransform
        snapshot.removeFromSuperview()
        dimView.removeFromSuperview()
    }
}
