#!/usr/bin/env python3
"""Exercise production media-save signals with real SwiftSignalKit and isolated Photos adapters."""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--baseline", nargs="?", const="HEAD", help="Run against a Git revision, defaulting to HEAD")
parser.add_argument("--native-output", type=Path, help="Also write an iOS fixture using the native Photos/AVFoundation APIs")
args = parser.parse_args()


def block(text, start):
    begin = text.index(start)
    end = text.index("{", begin) + 1
    depth = 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[begin:end]


relative = "submodules/SaveToCameraRoll/Sources/SaveToCameraRoll.swift"
source = subprocess.check_output(["git", "show", args.baseline + ":" + relative], cwd=ROOT, text=True) if args.baseline else (ROOT / relative).read_text()
legacy_baseline = "public func saveToCameraRollWithError(" not in source
if legacy_baseline:
    production = block(source, "public func saveToCameraRoll(").replace("func saveToCameraRoll(", "func saveToCameraRollWithError(")
else:
    production = "\n".join(block(source, name) for name in [
        "public enum SaveToCameraRollError:", "public func saveToCameraRoll(",
        "public func saveToCameraRollWithError(", "private func rgSaveVideoToPhotoLibrary(",
    ])
production = production.replace("public ", "")

hls = (ROOT / "submodules/TelegramUniversalVideoContent/Sources/HLSVideoContent.swift").read_text()
native = (ROOT / "submodules/TelegramUniversalVideoContent/Sources/NativeVideoContent.swift").read_text()
gallery = (ROOT / "submodules/GalleryUI/Sources/Items/UniversalVideoGalleryItem.swift").read_text()
codec_fixture = r'''
struct MediaId: Equatable { let id: Int64 }
enum FileAttribute { case ImageSize(CGSize), Video(Bool, CGSize, Int?, Int?, Int?, String?) }
final class TelegramMediaFile {
    let fileId: MediaId, mimeType: String, fileName: String?, attributes: [FileAttribute]
    var alternativeRepresentations: [TelegramMediaFile] = []
    init(_ id: Int64, _ mime: String, _ name: String?, _ attributes: [FileAttribute] = []) {
        self.fileId = MediaId(id: id); self.mimeType = mime; self.fileName = name; self.attributes = attributes
    }
}
struct FileMediaReference {
    let media: TelegramMediaFile
    func withMedia(_ media: TelegramMediaFile) -> FileMediaReference { FileMediaReference(media: media) }
}
'''
codec_fixture += block(hls, "public struct HLSCodecConfiguration").replace("public ", "")
codec_fixture += "\nenum NativeVideoContent {" + block(native, "public static func isVideoCodecSupported(").replace("public ", "") + "}\n"
codec_fixture += block(hls, "public final class HLSQualitySet").replace("public ", "")
save_codecs = next(line.strip() for line in gallery.splitlines() if "let saveCodecs =" in line) if not legacy_baseline else "let saveCodecs = HLSCodecConfiguration(isHardwareAv1Supported: true, isSoftwareAv1Supported: true)"
codec_checks = r'''
func codecChecks() {
    SAVE_CODECS
    let size = CGSize(width: 720, height: 1280)
    let h264 = TelegramMediaFile(1, "video/mp4", nil, [.Video(false, size, nil, nil, nil, "h264")])
    let av1 = TelegramMediaFile(2, "video/mp4", nil, [.Video(false, size, nil, nil, nil, "av1")])
    let av01 = TelegramMediaFile(3, "video/mp4", nil, [.Video(false, size, nil, nil, nil, "av01")])
    let playlists = [1, 2, 3].map { TelegramMediaFile(Int64($0 + 10), "application/x-mpegurl", "mtproto:\($0)") }
    let base = TelegramMediaFile(99, "video/mp4", nil)
    for alternatives in [[h264, av1, av01], [av01, av1, h264]] {
        base.alternativeRepresentations = alternatives + playlists
        let reference = FileMediaReference(media: base)
        let playback = HLSQualitySet(baseFile: reference, codecConfiguration: HLSCodecConfiguration(isHardwareAv1Supported: false, isSoftwareAv1Supported: true))
        expect(playback?.qualityFiles[720]?.media.fileId != h264.fileId, "The fixture must reproduce software AV1 playback selection")
        let saved = HLSQualitySet(baseFile: reference, codecConfiguration: saveCodecs)
        expect(saved?.qualityFiles[720]?.media.fileId == h264.fileId, "Saving must use H.264 regardless of representation order")
    }
    base.alternativeRepresentations = [av1, playlists[1]]
    expect(HLSQualitySet(baseFile: FileMediaReference(media: base), codecConfiguration: saveCodecs) == nil, "AV1-only variants must use the original-file fallback")
    print("PASS: production HLS quality selection keeps H.264 for saves and handles AV1-only variants")
}
codecChecks()
'''.replace("SAVE_CODECS", save_codecs)

adapters = r'''
import Foundation
import SwiftSignalKit
enum EngineMediaResource { struct ResourceData { let path: String; let isComplete: Bool } }
typealias ResourceData = EngineMediaResource.ResourceData
enum FetchMediaDataState { case progress(Float), data(ResourceData) }
enum MediaResourceUserLocation { case other }
enum MediaResourceUserContentType { case other }
struct AnyMediaReference {
    let states: [(FetchMediaDataState, Bool)]
    var events: ValuePipe<(FetchMediaDataState, Bool)>? = nil
}
final class AccountContext { let sharedContext = SharedContext() }
final class SharedContext {
    let currentPresentationData = DataBox(), applicationBindings = Bindings()
    func presentGlobalController(_ value: Int, _ args: Int) {}
}
final class DataBox { func with<T>(_ f: (Int) -> T) -> T { f(0) } }
final class Bindings { func openSettings() {} }
enum Access { case mediaLibrary(Kind); enum Kind { case save } }
enum DeviceAccess {
    static var authorized = true, delayed = false
    static var pending: ((Bool) -> Void)?
    static func authorizeAccess(to: Access, presentationData: Int, present: (Int, Int) -> Void,
                                openSettings: () -> Void, _ completion: @escaping (Bool) -> Void) {
        if delayed { pending = completion } else { completion(authorized) }
    }
}
func fetchMediaData(context: AccountContext, userLocation: MediaResourceUserLocation,
                    customUserContentType: MediaResourceUserContentType?, mediaReference: AnyMediaReference) -> Signal<(FetchMediaDataState, Bool), NoError> {
    if let events = mediaReference.events { return events.signal() }
    return Signal { subscriber in
        for state in mediaReference.states { subscriber.putNext(state) }
        subscriber.putCompletion()
        return EmptyDisposable
    }
}
func addAssetIdentifierToJPEG(_ data: Data, assetIdentifier: String) -> Data? { data.isEmpty ? nil : data }
func addAssetIdentifierToVideo(inputURL: URL, outputURL: URL, assetIdentifier: String, completion: @escaping (Bool) -> Void) {
    do { try FileManager.default.copyItem(at: inputURL, to: outputURL); completion(true) } catch { completion(false) }
}
'''

photos = r'''
enum AssetResourceType { case photo, video, pairedVideo }
final class PHAssetCreationRequest {
    static func forAsset() -> PHAssetCreationRequest { PHAssetCreationRequest() }
    func addResource(with: AssetResourceType, data: Data, options: Int?) {}
    func addResource(with: AssetResourceType, fileURL: URL, options: Int?) { PHPhotoLibrary.paths.append(fileURL) }
}
final class PHAssetChangeRequest {
    static func creationRequestForAssetFromVideo(atFileURL: URL) { PHPhotoLibrary.paths.append(atFileURL) }
}
final class PHPhotoLibrary {
    static let instance = PHPhotoLibrary()
    static var paths: [URL] = [], pending: [(Bool, Error?) -> Void] = []
    static var writes = 0
    static func shared() -> PHPhotoLibrary { instance }
    func performChanges(_ changes: () -> Void, completionHandler: @escaping (Bool, Error?) -> Void) {
        changes(); PHPhotoLibrary.writes += 1; PHPhotoLibrary.pending.append(completionHandler)
    }
    static func resolve(_ success: Bool) {
        let callback = pending.removeFirst(); callback(success, success ? nil : NSError(domain: "PhotosFixture", code: 1))
    }
}
enum ExportStatus { case completed, failed, cancelled }
enum FileType { case mp4 }
let AVAssetExportPresetHighestQuality = "HighestQuality"
final class AVURLAsset { let url: URL; init(url: URL) { self.url = url } }
final class AVAssetExportSession {
    static var succeeds = true, count = 0, delayed = false
    static var pending: (() -> Void)?
    var outputURL: URL?, outputFileType: FileType?, shouldOptimizeForNetworkUse = false
    var status: ExportStatus = .completed
    let asset: AVURLAsset
    init?(asset: AVURLAsset, presetName: String) { self.asset = asset; Self.count += 1 }
    func exportAsynchronously(completionHandler: @escaping () -> Void) {
        let run = {
            if self.status != .cancelled {
                self.status = Self.succeeds ? .completed : .failed
                if Self.succeeds { try? FileManager.default.copyItem(at: self.asset.url, to: self.outputURL!) }
            }
            completionHandler()
        }
        if Self.delayed { Self.pending = run } else { run() }
    }
    func cancelExport() { status = .cancelled }
}
'''

checks = r'''
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
func reset() {
    PHPhotoLibrary.pending = []; PHPhotoLibrary.paths = []; PHPhotoLibrary.writes = 0
    AVAssetExportSession.count = 0; AVAssetExportSession.succeeds = true; AVAssetExportSession.delayed = false
    AVAssetExportSession.pending = nil
    DeviceAccess.authorized = true; DeviceAccess.delayed = false; DeviceAccess.pending = nil
}
let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
let path = folder.appendingPathComponent("video.mp4").path
try Data([1, 2, 3]).write(to: URL(fileURLWithPath: path))
let context = AccountContext()
var lateEvents: ValuePipe<(FetchMediaDataState, Bool)>?
var progress: [Float] = [], errors = 0, completions = 0
func start(path: String, isImage: Bool = false, lateStatus: Bool = false) -> Disposable {
    progress = []; errors = 0; completions = 0
    let states: [(FetchMediaDataState, Bool)] = [(.progress(1.0), isImage), (.data(ResourceData(path: path, isComplete: true)), isImage)]
    lateEvents = lateStatus ? ValuePipe() : nil
    let disposable = saveToCameraRollWithError(context: context, userLocation: .other, mediaReference: AnyMediaReference(states: states, events: lateEvents))
        .start(next: { progress.append($0) }, error: { _ in errors += 1 }, completed: { completions += 1 })
    lateEvents?.putNext(states[1])
    return disposable
}
reset()
var disposable = start(path: path)
pump()
expect(PHPhotoLibrary.writes == 1 && errors == 0 && completions == 0, "Import must remain pending until PhotoKit answers")
expect(!progress.contains(1.0), "A fully downloaded video must not report a successful Photos save")
let staged = PHPhotoLibrary.paths[0]
expect(FileManager.default.fileExists(atPath: staged.path), "Keep the staged video alive until Photos finishes")
PHPhotoLibrary.resolve(true); pump()
expect(progress.last == 1.0 && completions == 1 && errors == 0, "Confirmed Photos import must report success exactly once")
expect(!FileManager.default.fileExists(atPath: staged.path), "Successful imports must clean temporary files")
expect(AVAssetExportSession.count == 0, "Do not transcode videos already accepted by Photos")
disposable.dispose()
reset()
disposable = start(path: path)
pump(); PHPhotoLibrary.resolve(false); pump()
expect(completions == 0 && !progress.contains(1.0), "A rejected Photos transaction must not display saved or 100%")
expect(AVAssetExportSession.count == 1 && PHPhotoLibrary.writes == 2, "Rejected videos must get one MP4 export retry")
PHPhotoLibrary.resolve(false); pump()
expect(errors == 1 && completions == 0 && !progress.contains(1.0), "Failed imports must never display success")
expect(PHPhotoLibrary.paths.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }, "Failed imports must clean temporary files")
disposable.dispose()
reset()
disposable = start(path: path)
pump(); PHPhotoLibrary.resolve(false); pump(); PHPhotoLibrary.resolve(true); pump()
expect(AVAssetExportSession.count == 1 && completions == 1 && errors == 0, "A compatible MP4 retry may complete the original save")
disposable.dispose()
reset(); AVAssetExportSession.succeeds = false
disposable = start(path: path)
pump(); PHPhotoLibrary.resolve(false); pump()
expect(errors == 1 && completions == 0 && PHPhotoLibrary.writes == 1, "Export failure must report failure without another Photos write")
disposable.dispose()
reset()
disposable = start(path: folder.appendingPathComponent("missing.mp4").path)
pump()
expect(errors == 1 && completions == 0 && PHPhotoLibrary.writes == 0, "Missing files must fail before creating an empty Photos transaction")
disposable.dispose()
reset(); DeviceAccess.authorized = false
disposable = start(path: path)
pump()
expect(errors == 1 && completions == 0 && PHPhotoLibrary.writes == 0, "Denied Photos permission must not display success")
disposable.dispose()
reset(); DeviceAccess.delayed = true
disposable = start(path: path)
pump(); disposable.dispose(); DeviceAccess.pending?(true); pump()
expect(PHPhotoLibrary.writes == 0, "Cancelling before authorization must prevent a Photos write")
reset(); AVAssetExportSession.delayed = true
disposable = start(path: path)
pump(); PHPhotoLibrary.resolve(false); pump(); disposable.dispose(); AVAssetExportSession.pending?(); pump()
expect(PHPhotoLibrary.writes == 1 && completions == 0 && errors == 0, "Cancelling a fallback export must prevent the retry import")
reset()
disposable = start(path: path, lateStatus: true)
pump()
lateEvents?.putNext((.progress(1.0), false))
lateEvents?.putNext((.data(ResourceData(path: path, isComplete: true)), false))
pump()
expect(PHPhotoLibrary.writes == 1, "Late Local status and duplicate data must not repeat a Photos write")
PHPhotoLibrary.resolve(true); pump()
expect(completions == 1 && errors == 0, "Late Local status must not cancel an in-flight import")
disposable.dispose()
reset()
disposable = start(path: path, isImage: true)
pump(); PHPhotoLibrary.resolve(false); pump()
expect(errors == 1 && completions == 0, "Photo failures must retain explicit result semantics")
disposable.dispose()
print("PASS: 10 production save scenarios, PhotoKit acknowledgement, MP4 retry, errors, cleanup, cancellation and late fetch events")
'''
if legacy_baseline:
    checks = checks.replace("error: { _ in errors += 1 }, ", "")

if args.native_output:
    args.native_output.mkdir(parents=True, exist_ok=True)
    (args.native_output / "MediaSave.swift").write_text(adapters + "\nimport Photos\nimport AVFoundation\n" + production)

with tempfile.TemporaryDirectory(prefix="regram-media-save-") as temporary:
    directory = Path(temporary)
    signal_sources = sorted((ROOT / "submodules/SSignalKit/SwiftSignalKit/Source").glob("*.swift"))
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-emit-library", "-emit-module", "-module-name", "SwiftSignalKit", *map(str, signal_sources), "-o", str(directory / "libSwiftSignalKit.dylib")], check=True)
    fixture = directory / "main.swift"
    fixture.write_text(adapters + photos + production + codec_fixture + checks + codec_checks)
    binary = directory / "checks"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-warnings-as-errors", "-I", str(directory), "-L", str(directory), "-lSwiftSignalKit", str(fixture), "-o", str(binary)], check=True)
    result = subprocess.run([str(binary)], env={**os.environ, "DYLD_LIBRARY_PATH": str(directory)})
    raise SystemExit(result.returncode)
