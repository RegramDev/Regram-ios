import UIKit
import AppBundle
import RGSimpleSettings

// Asset-backed images are resolved again after an overlay moves between different window traits.
final class RGAppBadgeImageView: UIImageView {
    private var loadedName: String?
    private var loadedTraits: UITraitCollection?

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        self.reloadArtwork()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reloadArtwork() {
        let name = RGSimpleSettings.shared.customAppBadge
        let traits = self.traitCollection
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
