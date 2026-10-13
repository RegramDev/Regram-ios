import Foundation
import CoreImage
import CoreGraphics

@main struct QrLoginCodeTests {
    static func main() {
        let tokens = [Data(repeating: 0x5a, count: 32), Data((0..<48).map(UInt8.init)), Data(repeating: 0xff, count: 64)]
        let colors = [CGColor(red: 0.0, green: 0.44, blue: 0.22, alpha: 1.0), CGColor(red: 0.08, green: 0.35, blue: 0.72, alpha: 1.0)]
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(options: [.useSoftwareRenderer: true]), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
        for token in tokens {
            let url = RGQrLoginCode.loginURL(token: token)!
            let encoded = String(url.dropFirst("tg://login?token=".count))
            assert(!encoded.contains("=") && !encoded.contains("+") && !encoded.contains("/"))
            let base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            assert(Data(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)) == token)
            for color in colors {
                let image = RGQrLoginCode.image(token: token, maximumPixelSize: 780, foregroundColor: color)!
                assert(image.width <= 780 && image.width == image.height)
                var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
                pixels.withUnsafeMutableBytes { buffer in
                    let bitmap = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                }
                assert(stride(from: 0, to: pixels.count, by: 4).contains { pixels[$0] != pixels[$0 + 1] || pixels[$0 + 1] != pixels[$0 + 2] }, "QR pixels must contain color, not just black and white")
                let results = detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
                assert(results.contains(url), "Rendered colored QR must decode to the exact login URL")
            }
        }
        assert(RGQrLoginCode.loginURL(token: Data()) == nil)
        assert(RGQrLoginCode.loginURL(token: Data(repeating: 0x42, count: 513)) == nil)
        assert(RGQrLoginCode.image(token: tokens[0], maximumPixelSize: 16, foregroundColor: colors[0]) == nil)
        print("QR checks passed: token round trips, six colored render/decode cases, invalid input.")
    }
}
