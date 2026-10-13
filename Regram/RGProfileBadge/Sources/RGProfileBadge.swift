// MARK: Regram
// Badge control adapted from NextAlone/Nagram-iOS; see the repository GPL license.
import Foundation
import UIKit
import Display
import RGStrings

public enum RGProfileBadge: String, Equatable {
    case developer
    case coreTester
    case sponsor
    public func title(language: String) -> String { return "ProfileBadge.\(self.rawValue)".i18n(language) }
    public func info(language: String) -> String { return "ProfileBadge.\(self.rawValue).Info".i18n(language) }
}

public func rgProfileBadge(userId: Int64) -> RGProfileBadge? {
    switch userId {
    case 6860249: return .developer
    case 5602240478: return .coreTester
    case 7086851861: return .sponsor
    default: return nil
    }
}

public final class RGProfileBadgeView: UIControl {
    private let backgroundView = UIView()
    private let titleLabel = UILabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)

        self.isHidden = true
        self.isUserInteractionEnabled = true
        self.addSubview(self.backgroundView)
        self.addSubview(self.titleLabel)

        self.titleLabel.font = Font.medium(11.0)
        self.titleLabel.textAlignment = .center
        self.isAccessibilityElement = true
        self.accessibilityTraits = .button
        self.titleLabel.isUserInteractionEnabled = false
        self.backgroundView.isUserInteractionEnabled = false
    }

    public required init?(coder: NSCoder) {
        preconditionFailure()
    }

    public override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.55 : 1.0
        }
    }

    public func update(title: String?, fillColor: UIColor, foregroundColor: UIColor) -> CGSize {
        guard let title, !title.isEmpty else {
            self.isHidden = true
            self.frame = CGRect(origin: self.frame.origin, size: CGSize())
            return CGSize()
        }

        self.isHidden = false
        self.backgroundView.backgroundColor = fillColor
        self.titleLabel.textColor = foregroundColor
        self.titleLabel.text = title
        self.accessibilityLabel = title

        let textSize = self.titleLabel.sizeThatFits(CGSize(width: 120.0, height: 18.0))
        let size = CGSize(width: ceil(textSize.width) + 12.0, height: 18.0)
        self.backgroundView.frame = CGRect(origin: CGPoint(), size: size)
        self.backgroundView.layer.cornerRadius = size.height * 0.5
        self.titleLabel.frame = CGRect(origin: CGPoint(x: 6.0, y: floor((size.height - textSize.height) / 2.0)), size: textSize)
        return size
    }
}
