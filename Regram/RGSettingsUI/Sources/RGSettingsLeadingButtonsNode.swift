import UIKit
import AsyncDisplayKit
import Display

/// Retains the settings page's Back + QR controls when the configurable tab bar is hidden.
public final class RGSettingsLeadingButtonsNode: HighlightableButtonNode {
    private let backButton = HighlightableButtonNode()
    private let qrButton = HighlightableButtonNode()
    public var back: (() -> Void)?
    public var openQR: (() -> Void)?

    public override init(pointerStyle: PointerStyle? = nil) {
        super.init(pointerStyle: pointerStyle)
        self.isAccessibilityElement = false
        self.addSubnode(self.backButton)
        self.addSubnode(self.qrButton)
        self.backButton.addTarget(self, action: #selector(self.backPressed), forControlEvents: .touchUpInside)
        self.qrButton.addTarget(self, action: #selector(self.qrPressed), forControlEvents: .touchUpInside)
        for button in [self.backButton, self.qrButton] {
            button.isAccessibilityElement = true
            button.accessibilityTraits = .button
        }
        self.backButton.frame = CGRect(x: 0.0, y: 0.0, width: 44.0, height: 44.0)
        self.qrButton.frame = CGRect(x: 44.0, y: 0.0, width: 44.0, height: 44.0)
    }

    public func update(backImage: UIImage?, qrImage: UIImage?, color: UIColor, backTitle: String, qrTitle: String) {
        // ASImageNode displays CGImage pixels directly, so UIKit's UIImage tint metadata is not applied.
        self.backButton.setImage(generateTintedImage(image: backImage, color: color), for: .normal)
        self.qrButton.setImage(generateTintedImage(image: qrImage, color: color), for: .normal)
        self.backButton.accessibilityLabel = backTitle
        self.qrButton.accessibilityLabel = qrTitle
    }

    public override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: 88.0, height: 44.0)
    }

    @objc private func backPressed() { self.back?() }
    @objc private func qrPressed() { self.openQR?() }
}
