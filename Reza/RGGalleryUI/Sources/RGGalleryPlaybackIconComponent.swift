// MARK: Regram — compact icons inside the gallery's shared bottom glass capsule.
import ComponentFlow
import Display
import Foundation
import UIKit

public final class RGGalleryPlaybackIconComponent: Component {
    public enum Icon: Equatable { case play, pause, backward, forward }
    private let icon: Icon
    public init(_ icon: Icon) { self.icon = icon }
    public static func == (lhs: RGGalleryPlaybackIconComponent, rhs: RGGalleryPlaybackIconComponent) -> Bool { lhs.icon == rhs.icon }
    public final class View: UIView {
        private let imageView = UIImageView()
        private var icon: Icon?
        public override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            imageView.contentMode = .scaleAspectFit
            imageView.tintColor = .white
            addSubview(imageView)
        }
        public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func update(_ component: RGGalleryPlaybackIconComponent, transition: ComponentTransition) -> CGSize {
            let size = CGSize(width: 32, height: 32)
            if icon != component.icon {
                let symbol: String
                switch component.icon {
                case .play: symbol = "play.fill"
                case .pause: symbol = "pause.fill"
                case .backward: symbol = "gobackward.15"
                case .forward: symbol = "goforward.15"
                }
                imageView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 25, weight: .regular))
                icon = component.icon
            }
            let inset: CGFloat = component.icon == .play || component.icon == .pause ? 3 : 0
            transition.setFrame(view: imageView, frame: CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset))
            return size
        }
    }
    public func makeView() -> View { View(frame: .zero) }
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        view.update(self, transition: transition)
    }
}
