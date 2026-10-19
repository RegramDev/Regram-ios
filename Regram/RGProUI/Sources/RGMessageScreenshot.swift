// MARK: Regram — compact, flat single-message export with exactly one sender name.
import UIKit
import Display
public func rgMessageScreenshot(body: UIImage, senderName: String, avatar: UIImage?, backgroundColor: UIColor, textColor: UIColor) -> UIImage {
    let padding: CGFloat = 12, contentX: CGFloat = 60
    let nameFont = Font.semibold(15)
    let nameWidth = min(240, ceil((senderName as NSString).size(withAttributes: [.font: nameFont]).width))
    let contentWidth = max(body.size.width, nameWidth)
    let nameHeight: CGFloat = 26
    let size = CGSize(width: contentX + contentWidth + padding, height: padding * 2 + max(38, nameHeight + body.size.height))
    let format = UIGraphicsImageRendererFormat()
    format.scale = min(body.scale, sqrt(12_000_000 / (size.width * size.height)), 16_384 / size.height)
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
        backgroundColor.setFill(); renderer.fill(CGRect(origin: .zero, size: size))
        let avatarRect = CGRect(x: padding, y: padding, width: 38, height: 38)
        renderer.cgContext.saveGState(); renderer.cgContext.addEllipse(in: avatarRect); renderer.cgContext.clip()
        if let avatar { avatar.draw(in: avatarRect) }
        else {
            textColor.withAlphaComponent(0.15).setFill(); renderer.fill(avatarRect)
            let letter = String(senderName.prefix(1)) as NSString, font = Font.semibold(18)
            let dimensions = letter.size(withAttributes: [.font: font])
            letter.draw(at: CGPoint(x: avatarRect.midX - dimensions.width / 2, y: avatarRect.midY - dimensions.height / 2), withAttributes: [.font: font, .foregroundColor: textColor])
        }
        renderer.cgContext.restoreGState()
        do {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            (senderName as NSString).draw(in: CGRect(x: contentX, y: padding, width: contentWidth, height: 22), withAttributes: [.font: nameFont, .foregroundColor: textColor, .paragraphStyle: paragraph])
        }
        body.draw(at: CGPoint(x: contentX, y: padding + nameHeight))
    }
}
