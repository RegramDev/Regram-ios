// MARK: Regram
import Foundation
import UIKit
import Photos
import ImageIO
import UniformTypeIdentifiers
import Accelerate
import SwiftSignalKit
import TelegramCore
import AccountContext
import DeviceAccess
import Display
import AnimatedStickerNode
import LottieSettings
import WebPBinding
import SaveToCameraRoll

private let stickerExportQueue = Queue(name: "regram.sticker-export")

/// Saves static stickers as transparent PNG, and TGS/video stickers as looping GIF.
public func rgSaveStickerToPhotos(context: AccountContext, fileReference: FileMediaReference, userLocation: MediaResourceUserLocation) -> Signal<Bool, NoError> {
    let authorized = Signal<Bool, NoError> { subscriber in
        DeviceAccess.authorizeAccess(to: .mediaLibrary(.save), presentationData: context.sharedContext.currentPresentationData.with { $0 }, present: { controller, arguments in
            context.sharedContext.presentGlobalController(controller, arguments)
        }, openSettings: context.sharedContext.applicationBindings.openSettings, { allowed in
            subscriber.putNext(allowed)
            subscriber.putCompletion()
        })
        return EmptyDisposable
    }
    let settings = context.lottieRenderingSettings
    return authorized
    |> mapToSignal { allowed -> Signal<Bool, NoError> in
        guard allowed else { return .single(false) }
        return fetchMediaData(context: context, userLocation: userLocation, mediaReference: fileReference.abstract)
        |> map { value -> String? in
            if case let .data(data) = value.0, data.isComplete { return data.path }
            return nil
        }
        |> filter { $0 != nil }
        |> take(1)
        |> mapToSignal { path -> Signal<Bool, NoError> in
            guard let path else { return .single(false) }
            return Signal { subscriber in
                let cancelled = Atomic<Bool>(value: false)
                stickerExportQueue.async {
                    guard !cancelled.with({ $0 }) else { return }
                    guard let url = rgExportSticker(path: path, file: fileReference.media, settings: settings, cancelled: cancelled) else {
                        subscriber.putNext(false)
                        subscriber.putCompletion()
                        return
                    }
                    guard !cancelled.with({ $0 }) else {
                        try? FileManager.default.removeItem(at: url)
                        return
                    }
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.originalFilename = url.lastPathComponent
                        options.uniformTypeIdentifier = url.pathExtension == "gif" ? UTType.gif.identifier : UTType.png.identifier
                        PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: options)
                    }, completionHandler: { success, _ in
                        try? FileManager.default.removeItem(at: url)
                        subscriber.putNext(success)
                        subscriber.putCompletion()
                    })
                }
                return ActionDisposable { let _ = cancelled.modify { _ in true } }
            }
        }
        |> timeout(120.0, queue: .mainQueue(), alternate: .single(false))
    }
}

private func rgExportSticker(path: String, file: TelegramMediaFile, settings: LottieRenderingSettings, cancelled: Atomic<Bool>) -> URL? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe), data.count <= 32 * 1024 * 1024 else { return nil }
    let animated = file.isAnimatedSticker || file.isVideoSticker
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Regram-Sticker-\(UUID().uuidString).\(animated ? "gif" : "png")")
    var completed = false
    defer { if !completed { try? FileManager.default.removeItem(at: url) } }
    if !animated {
        guard let image = WebP.convert(fromWebP: data) ?? UIImage(data: data), let png = image.pngData() else { return nil }
        do { try png.write(to: url) } catch { return nil }
        completed = true
        return url
    }
    let size = (file.dimensions?.cgSize ?? CGSize(width: 512, height: 512)).aspectFitted(CGSize(width: 512, height: 512))
    let width = max(1, Int(size.width)), height = max(1, Int(size.height))
    func source() -> AnimatedStickerFrameSource? {
        if file.isVideoSticker {
            return makeVideoStickerDirectFrameSource(queue: stickerExportQueue, path: path, hintVP9: true, width: width, height: height, cachePathPrefix: nil, unpremultiplyAlpha: false)
        }
        return AnimatedStickerDirectFrameSource(queue: stickerExportQueue, data: data, width: width, height: height, cachePathPrefix: nil, fitzModifier: nil, lottieSettings: settings)
    }
    guard var frames = source() else { return nil }
    var frameCount = frames.frameCount
    // Video sources discover their frame count at EOF. Count without retaining decoded frames.
    if frameCount == 0 {
        while frameCount < 1200 && !cancelled.with({ $0 }) {
            let hasFrame = autoreleasepool { frames.takeFrame(draw: true) != nil }
            if !hasFrame { break }
            frameCount += 1
        }
        guard frameCount > 0, frameCount < 1200, let restarted = source() else { return nil }
        frames = restarted
    }
    guard frameCount > 0, frameCount <= 1200, !cancelled.with({ $0 }),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else { return nil }
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let delay = 1.0 / Double(max(1, frames.frameRate))
    for _ in 0 ..< frameCount {
        guard !cancelled.with({ $0 }) else { return nil }
        let added = autoreleasepool { () -> Bool in
            guard let frame = frames.takeFrame(draw: true), case .argb = frame.type,
                  frame.data.count >= frame.bytesPerRow * frame.height else { return false }
            let image = generateImagePixel(CGSize(width: frame.width, height: frame.height), scale: 1.0, pixelGenerator: { _, pixels, stride in
                frame.data.withUnsafeBytes { buffer in
                    guard let base = buffer.baseAddress else { return }
                    for row in 0 ..< frame.height {
                        memcpy(pixels.advanced(by: row * stride), base.advanced(by: row * frame.bytesPerRow), frame.width * 4)
                    }
                    // Video decoder frames have straight alpha; DrawingContext expects premultiplied BGRA.
                    if file.isVideoSticker {
                        var image = vImage_Buffer(data: pixels, height: vImagePixelCount(frame.height), width: vImagePixelCount(frame.width), rowBytes: stride)
                        let permutation: [UInt8] = [3, 2, 1, 0]
                        vImagePermuteChannels_ARGB8888(&image, &image, permutation, vImage_Flags(kvImageDoNotTile))
                        vImagePremultiplyData_ARGB8888(&image, &image, vImage_Flags(kvImageDoNotTile))
                        vImagePermuteChannels_ARGB8888(&image, &image, permutation, vImage_Flags(kvImageDoNotTile))
                    }
                }
            })
            guard let cgImage = image?.cgImage else { return false }
            CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
            return true
        }
        guard added else { return nil }
    }
    guard CGImageDestinationFinalize(destination) else { return nil }
    completed = true
    return url
}
