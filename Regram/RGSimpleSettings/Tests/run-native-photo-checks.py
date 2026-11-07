#!/usr/bin/env python3
"""Exercise native photo encoding entry points with isolated image and compression boundaries."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', help='Prove the photo preference regression against this revision')
parser.add_argument('--clipboard-first', action='store_true', help='Reproduce pixel resolution independently of JPEG quality')
args = parser.parse_args()


def source(path):
    if args.baseline:
        return subprocess.check_output(['git', 'show', args.baseline + ':' + path], cwd=ROOT, text=True)
    return (ROOT / path).read_text()


def function(text, signature):
    start = text.index(signature)
    brace = text.index('{', start)
    end, depth = brace + 1, 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


messages = source('submodules/TelegramUI/Components/ChatMediaSend/Sources/ChatMediaSendMessages.swift')
render = source('submodules/TelegramUI/Components/ChatMediaSend/Sources/ChatMediaSendRender.swift')
single = source('submodules/TelegramUI/Components/ChatMediaSend/Sources/ChatMediaSendSingleItem.swift')
policy = function(messages, 'func rgChatMediaSendIsPastedPhoto(') if 'func rgChatMediaSendIsPastedPhoto(' in messages else ''
encode = function(messages, 'func chatMediaSendRenderedImageMedia(')
prepare = function(render, 'func chatMediaSendPreparedRenderedImage(')
sizes = (function(single, 'public func chatMediaEditorImageMaxSide(') + '\n' + function(single, 'public func chatMediaEditorImageSendSize(')).replace('public func ', 'func ')
start = messages.index('    case let .image(image):', messages.index('private func chatMediaSendItemMedia('))
image_branch = messages[start:messages.index('    case let .imageFile(', start)]
render_limit = next(line.strip() for line in render.splitlines() if 'let maxOutputSide = chatMediaEditorImageMaxSide(forceHd: forceHd' in line)

fixture = r'''
import Foundation
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !value() { print("FAIL: " + message); exit(1) }
}
struct PixelDimensions: Equatable {
    let width: Int32, height: Int32
    init(_ size: CGSize) { width = Int32(size.width); height = Int32(size.height) }
    var cgSize: CGSize { CGSize(width: CGFloat(width), height: CGFloat(height)) }
}
extension CGSize {
    func aspectFittedOrSmaller(_ size: CGSize) -> CGSize {
        let ratio = min(1, size.width / width, size.height / height)
        return CGSize(width: floor(width * ratio), height: floor(height * ratio))
    }
}
final class UIImage { let size: CGSize, scale: CGFloat; init(_ size: CGSize, scale: CGFloat = 1) { self.size = size; self.scale = scale } }
final class RGSimpleSettings { static let shared = RGSimpleSettings(); var outgoingPhotoQuality: Int32 = 100 }
struct TelegramMediaFile {}
enum EngineMediaResource { struct Id {} }
enum EngineMedia { struct Id { init(namespace: Int, id: Int64) {} } }
enum Namespaces { enum Media { static let LocalImage = 0 } }
var createdFiles: [String] = []
struct LocalFileReferenceMediaResource {
    init(localFilePath: String, randomId: Int64) { createdFiles.append(localFilePath) }
}
struct TelegramMediaImageRepresentation {
    let dimensions: PixelDimensions
    init(dimensions: PixelDimensions, resource: LocalFileReferenceMediaResource, progressiveSizes: [Int], immediateThumbnailData: Data?, hasVideo: Bool, isPersonal: Bool) { self.dimensions = dimensions }
}
struct TelegramMediaImageFlags: OptionSet {
    let rawValue: Int
    static let hasStickers = Self(rawValue: 1), isLivePhoto = Self(rawValue: 2)
}
struct TelegramMediaImage {
    let representations: [TelegramMediaImageRepresentation]
    let flags: TelegramMediaImageFlags
    init(imageId: EngineMedia.Id, representations: [TelegramMediaImageRepresentation], immediateThumbnailData: Data?, reference: Int?, partialReference: Int?, flags: TelegramMediaImageFlags, video: TelegramMediaFile?) {
        self.representations = representations; self.flags = flags
    }
}
final class EngineTempBox {
    struct Temp { let path: String }
    static let shared = EngineTempBox()
    func tempFile(fileName: String) -> Temp { Temp(path: NSTemporaryDirectory() + UUID().uuidString) }
    func dispose(_ file: Temp) {}
}
var encodedQuality: Float = -1
func compressImageToJPEG(_ image: UIImage, quality: Float, tempFilePath: String) -> Data? { encodedQuality = quality; return Data([1]) }
func TGScaleImageToPixelSize(_ image: UIImage, _ size: CGSize) -> UIImage? { UIImage(size) }
func chatMediaSendThumbnailRepresentation(thumbnail: UIImage, fittedTo: CGSize, storeResourceData: (EngineMediaResource.Id, Data) -> Void) -> TelegramMediaImageRepresentation? { nil }
struct MediaEditorValues { let dimensions: PixelDimensions }
func chatMediaEditorCroppedNominalDimensions(values: MediaEditorValues) -> PixelDimensions { values.dimensions }
struct ChatMediaSendItem {
    enum Source { case image(UIImage), other }
    let source: Source
    var values: MediaEditorValues?
    var renderedImage: UIImage?
    var thumbnail: UIImage?
    var stickers: [TelegramMediaFile] = []
}
POLICY
SIZES
ENCODE
PREPARE
func direct(item: ChatMediaSendItem, forceHd: Bool, storeResourceData: (EngineMediaResource.Id, Data) -> Void) -> (media: TelegramMediaImage, stickerFiles: [TelegramMediaFile])? {
    switch item.source {
    IMAGE_BRANCH
    default: return nil
    }
}
func renderLimit(item: ChatMediaSendItem, forceHd: Bool) -> CGFloat {
    RENDER_LIMIT
    return maxOutputSide
}
@main enum Tests { static func main() {
    defer { for path in createdFiles { try? FileManager.default.removeItem(atPath: path) } }
    let settings = RGSimpleSettings.shared
    let image = UIImage(CGSize(width: 800, height: 600), scale: 3)
    let ordinary = ChatMediaSendItem(source: .other)
    let pasted = ChatMediaSendItem(source: .image(image))
    if CommandLine.arguments.contains("--clipboard-first") {
        let media = direct(item: pasted, forceHd: false, storeResourceData: { _, _ in })!.media
        check(media.representations.last!.dimensions == PixelDimensions(CGSize(width: 2400, height: 1800)), "Clipboard encoding preserves pixels rather than points")
    }
    for value: Int32 in [100, 60, 25, 10] {
        settings.outgoingPhotoQuality = value
        let photo = chatMediaSendPreparedRenderedImage(item: ordinary, image: image, forceHd: false, storeResourceData: { _, _ in })!
        check(encodedQuality == Float(value) / 100, "Native edited-photo path uses the configured JPEG quality")
        check(photo.representations.last!.dimensions == PixelDimensions(CGSize(width: 1280, height: 960)), "Ordinary photos retain the standard size cap")
        let prepared = chatMediaSendPreparedRenderedImage(item: pasted, image: image, forceHd: false, storeResourceData: { _, _ in })!
        check(encodedQuality == 1, "Prepared clipboard photos keep maximum quality independently of the gallery preference")
        check(prepared.representations.last!.dimensions == PixelDimensions(CGSize(width: 2400, height: 1800)), "Prepared clipboard photos preserve pixels rather than points")
        let fallback = direct(item: pasted, forceHd: false, storeResourceData: { _, _ in })!.media
        check(encodedQuality == 1 && fallback.representations.last!.dimensions == prepared.representations.last!.dimensions, "Fallback clipboard encoding agrees with the asynchronous prepare path")
        check(renderLimit(item: pasted, forceHd: false) == 2560 && renderLimit(item: ordinary, forceHd: false) == 1280, "Clipboard editing keeps the HD limit before encoding")
    }
    for scale: CGFloat in [1, 2, 3] {
        let source = UIImage(CGSize(width: 1200, height: 900), scale: scale)
        let item = ChatMediaSendItem(source: .image(source))
        let output = direct(item: item, forceHd: false, storeResourceData: { _, _ in })!.media
        let expected = CGSize(width: 1200 * scale, height: 900 * scale).aspectFittedOrSmaller(CGSize(width: 2560, height: 2560))
        check(output.representations.last!.dimensions == PixelDimensions(expected), "Clipboard scales keep the same pixel-based HD cap")
    }
    var cropped = pasted
    cropped.values = MediaEditorValues(dimensions: PixelDimensions(CGSize(width: 400, height: 300)))
    cropped.stickers = [TelegramMediaFile()]
    let preparedCrop = chatMediaSendPreparedRenderedImage(item: cropped, image: image, forceHd: false, storeResourceData: { _, _ in })!
    let directCrop = direct(item: cropped, forceHd: false, storeResourceData: { _, _ in })!.media
    check(preparedCrop.representations.last!.dimensions == PixelDimensions(CGSize(width: 400, height: 300)) && directCrop.representations.last!.dimensions == preparedCrop.representations.last!.dimensions, "Crop metadata remains authoritative in both paths")
    check(preparedCrop.flags.contains(.hasStickers) && directCrop.flags.contains(.hasStickers), "Photo stickers keep their message flag")
    check(renderLimit(item: ordinary, forceHd: true) == 2560, "Explicit HD remains available to ordinary photos")
    print("Native photo regressions:", checks, "checks passed")
}}
'''.replace('POLICY', policy).replace('SIZES', sizes).replace('ENCODE', encode).replace('PREPARE', prepare).replace('IMAGE_BRANCH', image_branch).replace('RENDER_LIMIT', render_limit)

with tempfile.TemporaryDirectory(prefix='regram-native-photo-') as temporary:
    folder = Path(temporary)
    harness = folder / 'Tests.swift'; harness.write_text(fixture)
    binary = folder / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', str(harness), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)] + (['--clipboard-first'] if args.clipboard_first else []), capture_output=True, text=True)
    print(result.stdout, end='')
    if args.baseline:
        expected = 'Clipboard encoding preserves pixels rather than points' if args.clipboard_first else 'Native edited-photo path uses the configured JPEG quality'
        if result.returncode == 0 or expected not in result.stdout:
            raise SystemExit('Baseline did not reproduce the native photo preference regression: ' + result.stderr)
        print('Baseline reproduced the clipboard pixel-resolution regression.' if args.clipboard_first else 'Baseline reproduced the native photo quality preference regression.')
    elif result.returncode:
        raise SystemExit(result.stderr or result.returncode)
