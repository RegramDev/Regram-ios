// MARK: Regram
import Foundation
import CoreImage
import CoreGraphics

public enum RGQrLoginCode {
    private static let imageContext = CIContext(options: [.useSoftwareRenderer: true])

    public static func loginURL(token: Data) -> String? {
        guard !token.isEmpty, token.count <= 512 else { return nil }
        let encoded = token.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "tg://login?token=\(encoded)"
    }

    /// Core Image retains the QR quiet zone; integer scaling keeps the matrix sharp.
    /// The software renderer also works without a Metal device/context.
    public static func image(token: Data, maximumPixelSize: Int, foregroundColor: CGColor) -> CGImage? {
        guard (64 ... 2048).contains(maximumPixelSize), let url = self.loginURL(token: token),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage, image.extent.width > 0 else { return nil }
        guard let colors = CIFilter(name: "CIFalseColor") else { return nil }
        colors.setValue(image, forKey: kCIInputImageKey)
        colors.setValue(CIColor(cgColor: foregroundColor), forKey: "inputColor0")
        colors.setValue(CIColor(red: 1.0, green: 1.0, blue: 1.0), forKey: "inputColor1")
        guard let coloredImage = colors.outputImage else { return nil }
        let scale = floor(CGFloat(maximumPixelSize) / image.extent.width)
        guard scale >= 1.0 else { return nil }
        let scaled = coloredImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return self.imageContext.createCGImage(scaled, from: scaled.extent)
    }
}
