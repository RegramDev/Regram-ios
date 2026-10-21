import Foundation
import UIKit

/// Symbols are reserved for distinct editors. Plain groups keep their shared text alignment.
public enum RGSettingsIcons {
    public static let fonts = make("textformat", color: 0x007aff)
    public static let appIcon = make("app.fill", color: 0xaf52de)
    public static let screenshotBadge = make("camera.viewfinder", color: 0x5856d6)
    public static let transcription = make("waveform", color: 0xff9500)
    public static let summary = make("text.bubble.fill", color: 0x00a6a6)
    public static let network = make("network", color: 0x34a853)
    public static let diagnostics = make("waveform.path.ecg", color: 0x007aff)
    public static let backup = make("externaldrive.fill", color: 0x00a6a6)
    public static let update = make("arrow.triangle.2.circlepath", color: 0x007aff)
    public static let bottomBar = make("rectangle.bottomthird.inset.filled", color: 0x5856d6)
    public static let messageMenu = make("list.bullet.rectangle", color: 0xff9500)

    private static func make(_ name: String, color: UInt32) -> UIImage? {
        guard let symbol = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .semibold)) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let symbolImage = UIGraphicsImageRenderer(size: CGSize(width: 30.0, height: 30.0), format: format).image { _ in
            symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(at: CGPoint(x: (30.0 - symbol.size.width) * 0.5, y: (30.0 - symbol.size.height) * 0.5))
        }
        guard let glyph = trimmedGlyph(symbolImage) else { return nil }
        return UIGraphicsImageRenderer(size: CGSize(width: 30.0, height: 30.0), format: format).image { _ in
            UIColor(red: CGFloat((color >> 16) & 0xff) / 255.0, green: CGFloat((color >> 8) & 0xff) / 255.0, blue: CGFloat(color & 0xff) / 255.0, alpha: 1.0).setFill()
            UIBezierPath(roundedRect: CGRect(x: 0.0, y: 0.0, width: 30.0, height: 30.0), cornerRadius: 7.0).fill()
            let scale = 18.0 / CGFloat(max(glyph.width, glyph.height))
            let size = CGSize(width: CGFloat(glyph.width) * scale, height: CGFloat(glyph.height) * scale)
            UIImage(cgImage: glyph).draw(in: CGRect(x: (30.0 - size.width) * 0.5, y: (30.0 - size.height) * 0.5, width: size.width, height: size.height))
        }.withRenderingMode(.alwaysOriginal)
    }

    /// SF Symbols include baseline padding; center the visible glyph rather than its canvas.
    private static func trimmedGlyph(_ image: UIImage) -> CGImage? {
        guard let image = image.cgImage,
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0 ..< image.height {
            for x in 0 ..< image.width where pixels[y * context.bytesPerRow + x * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return context.makeImage()?.cropping(to: CGRect(x: CGFloat(minX), y: CGFloat(minY), width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1)))
    }
}
