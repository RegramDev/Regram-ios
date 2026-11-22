import Foundation
import UIKit

/// UIKit swipe actions render white labels. A theme's accent may itself be white in dark mode.
public func rgSettingsSwipeActionColor(_ preferred: UIColor) -> UIColor {
    var red: CGFloat = 0.0, green: CGFloat = 0.0, blue: CGFloat = 0.0, alpha: CGFloat = 0.0
    guard preferred.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
        return UIColor(red: 0.0, green: 0.36, blue: 0.8, alpha: 1.0)
    }
    func linear(_ component: CGFloat) -> CGFloat {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
    // Keep the theme hue and lower its brightness only when a white label would lose contrast.
    for _ in 0 ..< 16 {
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        if 1.05 / (luminance + 0.05) >= 4.5 { break }
        red *= 0.88; green *= 0.88; blue *= 0.88
    }
    return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
}
