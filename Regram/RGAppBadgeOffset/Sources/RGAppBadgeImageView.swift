import UIKit
import AppBundle
import RGSimpleSettings

// Asset-backed images are resolved again after an overlay moves between different window traits.
final class RGAppBadgeImageView: UIImageView {
    private var loadedName: String?
    private var loadedTraits: UITraitCollection?
    private var presentationStyle: UIUserInterfaceStyle?

    var artworkUserInterfaceStyle: UIUserInterfaceStyle {
        self.presentationStyle ?? self.traitCollection.userInterfaceStyle
    }

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        self.reloadArtwork()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateAppearance(isDark: Bool) {
        self.presentationStyle = isDark ? .dark : .light
        self.reloadArtwork()
    }

    func reloadArtwork() {
        let name = RGSimpleSettings.shared.customAppBadge
        // Telegram's selected theme can differ from the window's system appearance.
        let traits = UITraitCollection(traitsFrom: [self.traitCollection, UITraitCollection(userInterfaceStyle: self.artworkUserInterfaceStyle)])
        if self.loadedName == name, self.loadedTraits?.isEqual(traits) == true { return }
        self.image = UIImage(named: name, in: getAppBundle(), compatibleWith: traits)
        self.loadedName = self.image == nil ? nil : name
        self.loadedTraits = self.image == nil ? nil : traits
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        self.reloadArtwork()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.reloadArtwork()
    }
}
