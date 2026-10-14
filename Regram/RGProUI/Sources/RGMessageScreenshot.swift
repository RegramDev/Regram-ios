// MARK: Regram — share one rendered bubble with sender identity, without changing the message contents.
import UIKit
import Display
public func rgMessageScreenshot(body: UIImage, senderName: String, avatar: UIImage?, backgroundColor: UIColor, textColor: UIColor) -> UIImage {
    let width = max(260, body.size.width + 24), header: CGFloat = 62
    let size = CGSize(width: width, height: header + body.size.height + 12)
    let format = UIGraphicsImageRendererFormat()
    format.scale = min(body.scale, sqrt(12_000_000 / (size.width * size.height)))
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
        backgroundColor.setFill(); renderer.fill(CGRect(origin: .zero, size: size))
        let avatarRect = CGRect(x: 12, y: 12, width: 38, height: 38)
        renderer.cgContext.saveGState(); renderer.cgContext.addEllipse(in: avatarRect); renderer.cgContext.clip()
        if let avatar { avatar.draw(in: avatarRect) }
        else {
            textColor.withAlphaComponent(0.15).setFill(); renderer.fill(avatarRect)
            let letter = String(senderName.prefix(1)) as NSString, font = Font.semibold(18)
            let dimensions = letter.size(withAttributes: [.font: font])
            letter.draw(at: CGPoint(x: avatarRect.midX - dimensions.width / 2, y: avatarRect.midY - dimensions.height / 2), withAttributes: [.font: font, .foregroundColor: textColor])
        }
        renderer.cgContext.restoreGState()
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (senderName as NSString).draw(in: CGRect(x: 60, y: 12, width: width - 72, height: 38), withAttributes: [.font: Font.semibold(15), .foregroundColor: textColor, .paragraphStyle: paragraph])
        body.draw(at: CGPoint(x: 12, y: header))
    }
}

public func rgMessageScreenshotStack(_ screenshots: [UIImage], backgroundColor: UIColor) -> UIImage? {
    guard !screenshots.isEmpty, screenshots.count <= 30 else { return nil }
    let width = screenshots.map { $0.size.width }.max() ?? 0
    let height = screenshots.reduce(CGFloat(0)) { $0 + $1.size.height } + CGFloat(screenshots.count - 1) * 12
    guard width > 0, height > 0, width.isFinite, height.isFinite else { return nil }
    let scale = min(2, sqrt(12_000_000 / (width * height)), 16_384 / height)
    guard scale >= 1 else { return nil }
    let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = true
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { renderer in
        backgroundColor.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var y: CGFloat = 0
        for image in screenshots { image.draw(at: CGPoint(x: (width - image.size.width) / 2, y: y)); y += image.size.height + 12 }
    }
}
