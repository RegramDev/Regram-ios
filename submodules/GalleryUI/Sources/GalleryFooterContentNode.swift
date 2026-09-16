import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import ComponentFlow
import ComponentDisplayAdapters

public final class GalleryControllerInteraction {
    public let presentController: (ViewController, ViewControllerPresentationArguments?) -> Void
    public let pushController: (ViewController) -> Void
    public let dismissController: () -> Void
    public let replaceRootController: (ViewController, Promise<Bool>?) -> Void
    public let editMedia: (EngineMessage.Id) -> Void
    public let controller: () -> ViewController?
    public let currentItemNode: () -> GalleryItemNode?
    
    public init(presentController: @escaping (ViewController, ViewControllerPresentationArguments?) -> Void, pushController: @escaping (ViewController) -> Void, dismissController: @escaping () -> Void, replaceRootController: @escaping (ViewController, Promise<Bool>?) -> Void, editMedia: @escaping (EngineMessage.Id) -> Void, controller: @escaping () -> ViewController?, currentItemNode: @escaping () -> GalleryItemNode?) {
        self.presentController = presentController
        self.pushController = pushController
        self.dismissController = dismissController
        self.replaceRootController = replaceRootController
        self.editMedia = editMedia
        self.controller = controller
        self.currentItemNode = currentItemNode
    }
}

open class GalleryFooterContentNode: ASDisplayNode {
    public struct LayoutInfo {
        let height: CGFloat
        let needsShadow: Bool
        
        public init(height: CGFloat, needsShadow: Bool) {
            self.height = height
            self.needsShadow = needsShadow
        }
    }
    
    public var requestLayout: ((ContainedViewLayoutTransition) -> Void)?
    public var controllerInteraction: GalleryControllerInteraction?
    
    var visibilityAlpha: CGFloat = 1.0
    open func setVisibilityAlpha(_ alpha: CGFloat, animated: Bool) {
        self.visibilityAlpha = alpha
        self.alpha = alpha
    }
    
    open func updateLayout(size: CGSize, metrics: LayoutMetrics, leftInset: CGFloat, rightInset: CGFloat, bottomInset: CGFloat, contentInset: CGFloat, transition: ContainedViewLayoutTransition) -> LayoutInfo {
        return LayoutInfo(height: 0.0, needsShadow: false)
    }

    // MARK: Regram — a content node may want a strip of controls under the navigation bar rather than
    // in the bottom panel. It cannot place one itself: this node is bottom-anchored and sized to the
    // panel, so anything at the top would have to be pushed out through a negative offset derived
    // from a top inset it is never given. `GalleryFooterNode` spans the whole screen and does know
    // the navigation bar height, so it hosts the view and this pair of hooks hands it over.
    /// The view to host at the top of the screen, or nil to have none.
    open var galleryTopPanelView: UIView? {
        return nil
    }

    /// Lays the top panel out for `width` and returns the frame it wants, in a coordinate space whose
    /// origin is the top of the area below the navigation bar. The footer applies the vertical offset
    /// and sets the frame; returning an empty rect means "nothing to show".
    ///
    /// Called before `galleryTopPanelView` is read, since a `ComponentView` has no view until its
    /// first update.
    open func updateGalleryTopPanel(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGRect {
        return CGRect()
    }
    
    open func animateIn(transition: ContainedViewLayoutTransition) {
        self.alpha = 0.0
        ComponentTransition(transition).setAlpha(view: self.view, alpha: 1.0)
    }
    
    open func animateIn(fromHeight: CGFloat, previousContentNode: GalleryFooterContentNode, transition: ContainedViewLayoutTransition) {
    }
    
    open func animateOut(transition: ContainedViewLayoutTransition) {
        ComponentTransition(transition).setAlpha(view: self.view, alpha: 0.0)
    }
    
    open func animateOut(toHeight: CGFloat, nextContentNode: GalleryFooterContentNode, transition: ContainedViewLayoutTransition, completion: @escaping () -> Void) {
        completion()
    }
}

open class GalleryOverlayContentNode: ASDisplayNode {
    var visibilityAlpha: CGFloat = 1.0
    open func setVisibilityAlpha(_ alpha: CGFloat) {
        self.visibilityAlpha = alpha
    }
    
    open func updateLayout(size: CGSize, metrics: LayoutMetrics, insets: UIEdgeInsets, isHidden: Bool, transition: ContainedViewLayoutTransition) {
    }

    open func animateIn(previousContentNode: GalleryOverlayContentNode?, transition: ContainedViewLayoutTransition) {
    }
    
    open func animateOut(nextContentNode: GalleryOverlayContentNode?, transition: ContainedViewLayoutTransition, completion: @escaping () -> Void) {
        completion()
    }
}
