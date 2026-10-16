import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit

public enum TabBarItemSwipeDirection {
    case left
    case right
}

public protocol TabBarController: ViewController {
    var currentController: ViewController? { get }
    var controllers: [ViewController] { get }
    var selectedIndex: Int { get set }
    
    func setControllers(_ controllers: [ViewController], selectedIndex: Int?)
    
    func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition)
    
    func frameForControllerTab(controller: ViewController) -> CGRect?
    func isPointInsideContentArea(point: CGPoint) -> Bool
    
    func updateIsTabBarEnabled(_ value: Bool, transition: ContainedViewLayoutTransition)
    func updateIsTabBarHidden(_ value: Bool, transition: ContainedViewLayoutTransition)
    func updateLayout(transition: ContainedViewLayoutTransition)
    
    func updateControllerLayout(controller: ViewController)

    // MARK: Regram — root Settings can interactively return to the Chats tab.
    func rgBeginInteractiveReturnToChats() -> Bool
    func rgUpdateInteractiveReturnToChats(progress: CGFloat)
    func rgEndInteractiveReturnToChats(completed: Bool, velocity: CGFloat)
}

// MARK: Regram — other tab containers keep their existing navigation behavior.
public extension TabBarController {
    func rgBeginInteractiveReturnToChats() -> Bool { false }
    func rgUpdateInteractiveReturnToChats(progress: CGFloat) {}
    func rgEndInteractiveReturnToChats(completed: Bool, velocity: CGFloat) {}
}
