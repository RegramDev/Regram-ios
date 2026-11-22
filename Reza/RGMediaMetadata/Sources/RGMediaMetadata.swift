import Foundation
import AVFoundation
import CoreMedia
import ImageIO
import UniformTypeIdentifiers
import SwiftSignalKit
import Display
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import RGSimpleSettings
import RGStrings

// MARK: Regram — "Media Info" for the photo/video viewer.
// Describes a gallery item (type, format, resolution, size, duration, frame rate, bitrate, codec)
// from what is already on this device: the completed file through AVFoundation / ImageIO, else the
// header of a partially streamed MP4, else the attributes the server declared. It never fetches;
// anything that cannot be read locally is shown as "Unknown".
public enum RGMediaMetadata {
    /// Whether the viewer menus offer the item (Regram settings ▸ "Show Media Info").
    public static var isEnabled: Bool {
        return RGSimpleSettings.shared.showMediaMetadata
    }

    public static func menuItemTitle(strings: PresentationStrings) -> String {
        return "MediaMetadata.MenuItem".i18n(strings.baseLanguageCode)
    }

    /// Reads the metadata off the main thread and presents it as an alert.
    /// The returned disposable may be ignored; disposing it only drops a pending alert.
    @discardableResult
    public static func present(
        context: AccountContext,
        mediaReference: AnyMediaReference,
        presentationData: PresentationData,
        present: @escaping (ViewController) -> Void
    ) -> Disposable {
        let lang = presentationData.strings.baseLanguageCode
        let request = Request(mediaBox: context.account.postbox.mediaBox, mediaReference: mediaReference)
        let okTitle = presentationData.strings.Common_OK

        let signal = Signal<String, NoError> { subscriber in
            subscriber.putNext(RGMediaMetadata.buildText(request: request, lang: lang))
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(Queue.concurrentDefaultQueue())
        |> deliverOnMainQueue

        return signal.start(next: { text in
            let controller = textAlertController(
                context: context,
                forceTheme: defaultDarkColorPresentationTheme,
                title: "MediaMetadata.Title".i18n(lang),
                text: text,
                actions: [TextAlertAction(type: .defaultAction, title: okTitle, action: {})]
            )
            present(controller)
        })
    }

    // MARK: - Request (resolved on the calling thread)

    private enum Kind {
        case image
        case video
        case gif
        case audio
        case animation
        case file
    }

    private struct Request {
        var kind: Kind = .file
        var declaredWidth: Int?
        var declaredHeight: Int?
        var declaredDuration: Double?
        var declaredCodec: String?
        var declaredSize: Int64?
        var mimeType: String?
        /// The fully downloaded file, if any.
        var completePath: String?
        /// The streaming cache of a video, used only to read an MP4 header that is already there.
        var partialPath: String?

        init(mediaBox: MediaBox, mediaReference: AnyMediaReference) {
            if let imageReference = mediaReference.concrete(TelegramMediaImage.self) {
                self.kind = .image
                if let representation = largestImageRepresentation(imageReference.media.representations) {
                    self.declaredWidth = Int(representation.dimensions.width)
                    self.declaredHeight = Int(representation.dimensions.height)
                    self.declaredSize = representation.resource.size
                    self.completePath = mediaBox.completedResourcePath(representation.resource)
                }
            } else if let fileReference = mediaReference.concrete(TelegramMediaFile.self) {
                let file = fileReference.media
                var isVideo = false
                var isAnimated = false
                var isAudio = false
                for attribute in file.attributes {
                    switch attribute {
                    case let .Video(duration, size, _, _, _, videoCodec):
                        isVideo = true
                        self.declaredDuration = duration
                        self.declaredWidth = Int(size.width)
                        self.declaredHeight = Int(size.height)
                        self.declaredCodec = videoCodec
                    case let .Audio(_, duration, _, _, _):
                        isAudio = true
                        if self.declaredDuration == nil {
                            self.declaredDuration = Double(duration)
                        }
                    case let .ImageSize(size):
                        if self.declaredWidth == nil {
                            self.declaredWidth = Int(size.width)
                            self.declaredHeight = Int(size.height)
                        }
                    case .Animated:
                        isAnimated = true
                    default:
                        break
                    }
                }
                if isVideo {
                    self.kind = isAnimated ? .gif : .video
                } else if isAudio {
                    self.kind = .audio
                } else if isAnimated {
                    self.kind = .animation
                } else if file.mimeType.hasPrefix("image/") {
                    self.kind = .image
                } else {
                    self.kind = .file
                }
                self.declaredSize = file.size
                self.mimeType = file.mimeType.isEmpty ? nil : file.mimeType
                if isVideo || isAudio || isAnimated {
                    // The media cache stores files without an extension, and AVFoundation picks the
                    // container by extension; `pathExtension` links the completed file under one,
                    // as the rest of the app does before handing it to AVFoundation.
                    let pathExtension = UTType(mimeType: file.mimeType)?.preferredFilenameExtension ?? (isAudio && !isVideo ? "m4a" : "mp4")
                    self.completePath = mediaBox.completedResourcePath(file.resource, pathExtension: pathExtension)
                } else {
                    self.completePath = mediaBox.completedResourcePath(file.resource)
                }
                if self.completePath == nil && (isVideo || isAudio) {
                    self.partialPath = mediaBox.storePathsForId(file.resource.id).partial
                }
            }
        }
    }

    // MARK: - Text

    private static func buildText(request: Request, lang: String) -> String {
        let unknown = "MediaMetadata.Unknown".i18n(lang)
        var lines: [(String, String)] = []
        func add(_ key: String, _ value: String?) {
            lines.append((key.i18n(lang), value ?? unknown))
        }

        let typeKey: String
        switch request.kind {
        case .image:
            typeKey = "MediaMetadata.Image"
        case .video:
            typeKey = "MediaMetadata.Video"
        case .gif:
            typeKey = "MediaMetadata.Animation"
        case .audio:
            typeKey = "MediaMetadata.Audio"
        case .animation:
            typeKey = "MediaMetadata.Animation"
        case .file:
            typeKey = "MediaMetadata.File"
        }
        add("MediaMetadata.Type", typeKey.i18n(lang))

        var fileBytes: Int64?
        if let path = request.completePath, let size = fileSize(atPath: path), size > 0 {
            fileBytes = size
        } else if let size = request.declaredSize, size > 0 {
            fileBytes = size
        }

        switch request.kind {
        case .image, .file:
            let probe = request.completePath.flatMap(probeImage(path:))
            add("MediaMetadata.Format", probe?.format ?? request.mimeType)
            add("MediaMetadata.Resolution", formatResolution(width: probe?.width ?? request.declaredWidth, height: probe?.height ?? request.declaredHeight))
            add("MediaMetadata.FileSize", fileBytes.flatMap(formatBytes))
        case .video, .gif, .animation, .audio:
            var probe = request.completePath.flatMap(probeAsset(path:)) ?? AssetProbe()
            if (probe.codec == nil || probe.frameRate == nil), let path = request.completePath ?? request.partialPath {
                // A streamed video usually has only its partial cache; a faststart MP4 keeps `moov`
                // at the front, which is on disk once a few seconds have played.
                let header = probeMP4Header(path: path)
                if probe.codec == nil {
                    probe.codec = header.codec
                }
                if probe.frameRate == nil {
                    probe.frameRate = header.frameRate
                }
            }
            let duration = probe.duration ?? request.declaredDuration

            add("MediaMetadata.Format", request.mimeType)
            if request.kind != .audio {
                add("MediaMetadata.Resolution", formatResolution(width: probe.width ?? request.declaredWidth, height: probe.height ?? request.declaredHeight))
            }
            add("MediaMetadata.Duration", duration.flatMap(formatDuration))
            add("MediaMetadata.FileSize", fileBytes.flatMap(formatBytes))
            if request.kind != .audio {
                add("MediaMetadata.FrameRate", probe.frameRate.map { String(format: "%.2f fps", $0) })
            }
            var bitrate = probe.bitrate
            if bitrate == nil, let bytes = fileBytes, let duration, duration > 0 {
                // Whole-file average when the track does not report its own rate.
                bitrate = Double(bytes) * 8.0 / duration
            }
            add("MediaMetadata.Bitrate", bitrate.map(formatBitrate))
            if request.kind != .audio {
                add("MediaMetadata.Codec", probe.codec ?? request.declaredCodec.map(declaredCodecDisplayName))
            }
            if request.kind != .gif && request.kind != .animation {
                add("MediaMetadata.AudioCodec", probe.audioCodec)
            }
        }

        var text = lines.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        if request.completePath == nil {
            text += "\n\n" + "MediaMetadata.NotDownloaded".i18n(lang)
        }
        return text
    }

    // MARK: - ImageIO

    private struct ImageProbe {
        var width: Int?
        var height: Int?
        var format: String?
    }

    private static func probeImage(path: String) -> ImageProbe? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, options) else {
            return nil
        }
        var result = ImageProbe()
        if let type = CGImageSourceGetType(source) {
            let identifier = type as String
            if let ext = UTType(identifier)?.preferredFilenameExtension {
                result.format = ext.uppercased()
            } else {
                result.format = identifier
            }
        }
        if CGImageSourceGetCount(source) > 0, let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any] {
            var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
            var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
            // EXIF orientations 5–8 are rotated by 90°: report the size as displayed.
            if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, orientation >= 5 && orientation <= 8 {
                swap(&width, &height)
            }
            result.width = width
            result.height = height
        }
        if result.width == nil && result.format == nil {
            return nil
        }
        return result
    }

    // MARK: - AVFoundation

    private struct AssetProbe {
        var width: Int?
        var height: Int?
        var duration: Double?
        var frameRate: Float?
        var bitrate: Double?
        var codec: String?
        var audioCodec: String?
    }

    private static func probeAsset(path: String) -> AssetProbe? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path), options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        var result = AssetProbe()

        let duration = asset.duration
        if duration.isValid && !duration.isIndefinite && duration.seconds.isFinite && duration.seconds > 0 {
            result.duration = duration.seconds
        }

        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            if size.width != 0 && size.height != 0 {
                result.width = Int(abs(size.width).rounded())
                result.height = Int(abs(size.height).rounded())
            }
            if track.nominalFrameRate > 0 {
                result.frameRate = track.nominalFrameRate
            }
            if track.estimatedDataRate > 0 {
                result.bitrate = Double(track.estimatedDataRate)
            }
            if let subtype = mediaSubType(track.formatDescriptions.first) {
                result.codec = videoCodecDisplayName(fourCCString(subtype))
            }
        }
        if let track = asset.tracks(withMediaType: .audio).first {
            if let subtype = mediaSubType(track.formatDescriptions.first) {
                result.audioCodec = audioCodecDisplayName(fourCCString(subtype))
            }
            if result.bitrate == nil, track.estimatedDataRate > 0, asset.tracks(withMediaType: .video).isEmpty {
                result.bitrate = Double(track.estimatedDataRate)
            }
        }
        return result
    }

    private static func mediaSubType(_ description: Any?) -> FourCharCode? {
        guard let description else {
            return nil
        }
        let object = description as AnyObject
        guard CFGetTypeID(object) == CMFormatDescriptionGetTypeID() else {
            return nil
        }
        let formatDescription = object as! CMFormatDescription
        return CMFormatDescriptionGetMediaSubType(formatDescription)
    }

    private static func fourCCString(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        return (String(bytes: bytes, encoding: .ascii) ?? "").trimmingCharacters(in: .whitespaces)
    }

    private static func videoCodecDisplayName(_ fourcc: String) -> String? {
        switch fourcc {
        case "":
            return nil
        case "avc1", "avc3":
            return "H.264"
        case "hvc1", "hev1":
            return "HEVC"
        case "dvh1", "dvhe":
            return "Dolby Vision (HEVC)"
        case "vp08":
            return "VP8"
        case "vp09":
            return "VP9"
        case "av01":
            return "AV1"
        case "mp4v":
            return "MPEG-4"
        case "s263":
            return "H.263"
        case "jpeg":
            return "Motion JPEG"
        default:
            return fourcc.uppercased()
        }
    }

    private static func audioCodecDisplayName(_ fourcc: String) -> String? {
        switch fourcc {
        case "":
            return nil
        case "aac", "mp4a":
            return "AAC"
        case "aach":
            return "HE-AAC"
        case "aacp":
            return "HE-AAC v2"
        case "opus":
            return "Opus"
        case ".mp3":
            return "MP3"
        case "alac":
            return "ALAC"
        case "flac":
            return "FLAC"
        case "ac-3":
            return "AC-3"
        case "ec-3":
            return "E-AC-3"
        case "lpcm":
            return "PCM"
        default:
            return fourcc.uppercased()
        }
    }

    private static func declaredCodecDisplayName(_ codec: String) -> String {
        switch codec.lowercased() {
        case "h264", "avc":
            return "H.264"
        case "h265", "hevc":
            return "HEVC"
        case "av1":
            return "AV1"
        case "vp9":
            return "VP9"
        case "vp8":
            return "VP8"
        default:
            return codec.uppercased()
        }
    }

    // MARK: - MP4 header
    // Reads moov → trak → mdia from a possibly partial MP4: the stsd sample entry gives the codec,
    // mdhd + stts give the frame rate. Ranges that are not downloaded read as holes or past the end,
    // and the size checks in `childBoxes` stop the walk there.

    private struct HeaderProbe {
        var codec: String?
        var frameRate: Float?
    }

    private final class BoxReader {
        private let handle: FileHandle
        let fileLength: Int64

        init?(path: String) {
            guard let handle = FileHandle(forReadingAtPath: path) else {
                return nil
            }
            self.handle = handle
            guard let length = try? handle.seekToEnd() else {
                try? handle.close()
                return nil
            }
            self.fileLength = Int64(length)
        }

        deinit {
            try? self.handle.close()
        }

        func read(at offset: Int64, count: Int) -> [UInt8]? {
            guard offset >= 0, count > 0, offset + Int64(count) <= self.fileLength else {
                return nil
            }
            guard let _ = try? self.handle.seek(toOffset: UInt64(offset)), let data = try? self.handle.read(upToCount: count), data.count == count else {
                return nil
            }
            return [UInt8](data)
        }
    }

    private static func beUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32? {
        guard offset >= 0, bytes.count >= offset + 4 else {
            return nil
        }
        return (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16) | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    private static func beUInt64(_ bytes: [UInt8], _ offset: Int) -> UInt64? {
        guard let high = beUInt32(bytes, offset), let low = beUInt32(bytes, offset + 4) else {
            return nil
        }
        return (UInt64(high) << 32) | UInt64(low)
    }

    private static func childBoxes(_ reader: BoxReader, _ range: Range<Int64>) -> [(type: String, payload: Range<Int64>)] {
        var result: [(type: String, payload: Range<Int64>)] = []
        var offset = range.lowerBound
        while offset <= range.upperBound - 8, result.count < 512 {
            guard let header = reader.read(at: offset, count: 8), let size32 = beUInt32(header, 0) else {
                break
            }
            guard let type = String(bytes: header[4..<8], encoding: .ascii), type.allSatisfy({ $0.isASCII && !$0.isNewline }) else {
                break
            }
            var size = Int64(size32)
            var payloadStart = offset + 8
            if size32 == 1 {
                guard let ext = reader.read(at: offset + 8, count: 8), let size64 = beUInt64(ext, 0), size64 <= UInt64(Int64.max) else {
                    break
                }
                size = Int64(size64)
                payloadStart = offset + 16
            }
            guard size >= payloadStart - offset, size <= range.upperBound - offset else {
                break
            }
            let endOffset = offset + size
            result.append((type: type, payload: payloadStart..<endOffset))
            offset = endOffset
        }
        return result
    }

    private static func probeMP4Header(path: String) -> HeaderProbe {
        var result = HeaderProbe()
        guard let reader = BoxReader(path: path), reader.fileLength > 16 else {
            return result
        }
        guard let moov = childBoxes(reader, 0..<reader.fileLength).first(where: { $0.type == "moov" })?.payload else {
            return result
        }
        for trak in childBoxes(reader, moov) where trak.type == "trak" {
            guard let mdia = childBoxes(reader, trak.payload).first(where: { $0.type == "mdia" })?.payload else {
                continue
            }
            let mdiaChildren = childBoxes(reader, mdia)

            guard let hdlr = mdiaChildren.first(where: { $0.type == "hdlr" })?.payload,
                  let hdlrBytes = reader.read(at: hdlr.lowerBound, count: 12),
                  String(bytes: hdlrBytes[8..<12], encoding: .ascii) == "vide" else {
                continue
            }

            var timescale: Double?
            var duration: Double?
            if let mdhd = mdiaChildren.first(where: { $0.type == "mdhd" })?.payload,
               let bytes = reader.read(at: mdhd.lowerBound, count: min(Int(mdhd.upperBound - mdhd.lowerBound), 32)) {
                if bytes[0] == 0, let ts = beUInt32(bytes, 12), let d = beUInt32(bytes, 16) {
                    timescale = Double(ts)
                    duration = Double(d)
                } else if bytes[0] == 1, let ts = beUInt32(bytes, 20), let d = beUInt64(bytes, 24) {
                    timescale = Double(ts)
                    duration = Double(d)
                }
            }

            guard let minf = mdiaChildren.first(where: { $0.type == "minf" })?.payload,
                  let stbl = childBoxes(reader, minf).first(where: { $0.type == "stbl" })?.payload else {
                continue
            }
            let stblChildren = childBoxes(reader, stbl)

            if let stsd = stblChildren.first(where: { $0.type == "stsd" })?.payload,
               let bytes = reader.read(at: stsd.lowerBound, count: 16),
               let fourcc = String(bytes: bytes[12..<16], encoding: .ascii) {
                result.codec = videoCodecDisplayName(fourcc.trimmingCharacters(in: .whitespaces))
            }

            if let stts = stblChildren.first(where: { $0.type == "stts" })?.payload,
               let head = reader.read(at: stts.lowerBound, count: 8),
               let entryCount32 = beUInt32(head, 4) {
                let entryCount = Int(entryCount32)
                if entryCount > 0, entryCount <= 4096,
                   let table = reader.read(at: stts.lowerBound + 8, count: entryCount * 8) {
                    var samples: Double = 0
                    for i in 0 ..< entryCount {
                        samples += Double(beUInt32(table, i * 8) ?? 0)
                    }
                    if samples > 0, let ts = timescale, let d = duration, ts > 0, d > 0 {
                        result.frameRate = Float(samples / (d / ts))
                    }
                }
            }

            if result.codec != nil {
                break
            }
        }
        return result
    }

    // MARK: - Formatting

    private static func fileSize(atPath path: String) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path), let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }

    private static func formatResolution(width: Int?, height: Int?) -> String? {
        guard let width, let height, width > 0, height > 0 else {
            return nil
        }
        return "\(width) × \(height)"
    }

    private static func formatBytes(_ bytes: Int64) -> String? {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024.0 && index < units.count - 1 {
            value /= 1024.0
            index += 1
        }
        if index == 0 {
            return "\(bytes) B"
        }
        return String(format: "%.2f %@", value, units[index])
    }

    private static func formatBitrate(_ bitsPerSecond: Double) -> String {
        if bitsPerSecond >= 1_000_000.0 {
            return String(format: "%.2f Mbps", bitsPerSecond / 1_000_000.0)
        } else if bitsPerSecond >= 1_000.0 {
            return String(format: "%.0f Kbps", bitsPerSecond / 1_000.0)
        }
        return String(format: "%.0f bps", bitsPerSecond)
    }

    private static func formatDuration(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds > 0 else {
            return nil
        }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
