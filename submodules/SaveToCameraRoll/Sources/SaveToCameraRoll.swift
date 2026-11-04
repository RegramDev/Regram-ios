import Foundation
import AVFoundation // MARK: Regram
import UIKit
import SwiftSignalKit
import TelegramCore
import Photos
import Display
import UniformTypeIdentifiers
import DeviceAccess
import AccountContext
import LegacyComponents

public enum FetchMediaDataState {
    case progress(Float)
    case data(EngineMediaResource.ResourceData)
}

public func fetchMediaData(context: AccountContext, userLocation: MediaResourceUserLocation, customUserContentType: MediaResourceUserContentType? = nil, mediaReference: AnyMediaReference, forceVideo: Bool = false) -> Signal<(FetchMediaDataState, Bool), NoError> {
    var resource: TelegramMediaResource?
    var isImage = true
    var fileExtension: String?
    var userContentType: MediaResourceUserContentType = .other
    if let image = mediaReference.media as? TelegramMediaImage {
        userContentType = .image
        if let video = image.videoRepresentations.last, forceVideo {
            resource = video.resource
            isImage = false
        } else if let representation = largestImageRepresentation(image.representations) {
            resource = representation.resource
        }
    } else if let file = mediaReference.media as? TelegramMediaFile {
        userContentType = MediaResourceUserContentType(file: file)
        resource = file.resource
        if file.isVideo || file.mimeType.hasPrefix("video/") {
            isImage = false
        }
        let maybeExtension = ((file.fileName ?? "") as NSString).pathExtension
        if !maybeExtension.isEmpty {
            fileExtension = maybeExtension
        }
    } else if let webpage = mediaReference.media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content {
        if let file = content.file {
            resource = file.resource
            if file.isVideo {
                isImage = false
            }
        } else if let image = content.image {
            if let representation = largestImageRepresentation(image.representations) {
                resource = representation.resource
            }
        }
    }
    if let customUserContentType {
        userContentType = customUserContentType
    }

    if let resource = resource {
        let engineResource = EngineMediaResource(resource)
        let fetchedData: Signal<FetchMediaDataState, NoError> = Signal { subscriber in
            let fetched = context.engine.resources.fetch(
                reference: mediaReference.resourceReference(resource),
                userLocation: userLocation,
                userContentType: userContentType
            ).start()
            let status = context.engine.resources.status(resource: engineResource).start(next: { status in
                switch status {
                    case .Local:
                        subscriber.putNext(.progress(1.0))
                    case .Remote:
                        subscriber.putNext(.progress(0.0))
                    case let .Fetching(_, progress):
                        subscriber.putNext(.progress(progress))
                    case let .Paused(progress):
                        subscriber.putNext(.progress(progress))
                }
            })
            let data = context.engine.resources.data(
                resource: engineResource,
                pathExtension: fileExtension,
                waitUntilFetchStatus: true
            ).start(next: { next in
                subscriber.putNext(.data(next))
            }, completed: {
                subscriber.putCompletion()
            })
            return ActionDisposable {
                fetched.dispose()
                status.dispose()
                data.dispose()
            }
        }
        return fetchedData
        |> map { data in
            return (data, isImage)
        }
    } else {
        return .complete()
    }
}

// MARK: Regram — callers that display a result must observe the PhotoKit transaction, not a fetch completion.
public enum SaveToCameraRollError: Error {
    case accessDenied
    case generic
}

public func saveToCameraRoll(context: AccountContext, userLocation: MediaResourceUserLocation, customUserContentType: MediaResourceUserContentType? = nil, mediaReference: AnyMediaReference, video: AnyMediaReference? = nil) -> Signal<Float, NoError> {
    return saveToCameraRollWithError(context: context, userLocation: userLocation, customUserContentType: customUserContentType, mediaReference: mediaReference, video: video)
    |> `catch` { _ in .complete() }
}

public func saveToCameraRollWithError(context: AccountContext, userLocation: MediaResourceUserLocation, customUserContentType: MediaResourceUserContentType? = nil, mediaReference: AnyMediaReference, video: AnyMediaReference? = nil) -> Signal<Float, SaveToCameraRollError> {
    let fetchData: (AnyMediaReference) -> Signal<(FetchMediaDataState, Bool), NoError> = { reference in
        return fetchMediaData(context: context, userLocation: userLocation, customUserContentType: customUserContentType, mediaReference: reference)
        |> take(until: { state, _ in
            // MARK: Regram — late fetch status updates must not cancel or repeat an in-flight Photos import.
            if case let .data(data) = state, data.isComplete {
                return SignalTakeAction(passthrough: true, complete: true)
            }
            return SignalTakeAction(passthrough: true, complete: false)
        })
    }
    let mediaData = fetchData(mediaReference)
    let videoData: Signal<FetchMediaDataState?, NoError>
    if let video {
        videoData = fetchData(video)
        |> map { state, _ in
            return state
        }
        |> map(Optional.init)
    } else {
        videoData = .single(nil)
    }

    return combineLatest(
        queue: Queue.mainQueue(),
        mediaData,
        videoData
    )
    |> castError(SaveToCameraRollError.self)
    |> mapToSignal { stateAndIsImage, videoStateAndIsImage -> Signal<Float, SaveToCameraRollError> in
        let isImage = stateAndIsImage.1
        var mainData: EngineMediaResource.ResourceData?
        var videoData: EngineMediaResource.ResourceData?
        var waitForVideo = false
        if let videoState = videoStateAndIsImage {
            switch videoState {
            case let .progress(value):
                return .single(value * 0.9)
            case let .data(data):
                videoData = data
            }
            switch stateAndIsImage.0 {
            case let .progress(value):
                return .single(0.9 + 0.05 * value)
            case let .data(data):
                mainData = data
            }
            waitForVideo = true
        } else {
            switch stateAndIsImage.0 {
            case let .progress(value):
                // MARK: Regram — reserve 100% for a confirmed Photos write.
                return .single(value * 0.95)
            case let .data(data):
                mainData = data
            }
        }
        if let mainData, mainData.isComplete, videoData?.isComplete == true || !waitForVideo {
            return Signal<Float, SaveToCameraRollError> { subscriber in
                let cancelled = Atomic(value: false)
                let videoSaveDisposable = MetaDisposable()
                DeviceAccess.authorizeAccess(to: .mediaLibrary(.save), presentationData: context.sharedContext.currentPresentationData.with { $0 }, present: { c, a in
                    context.sharedContext.presentGlobalController(c, a)
                }, openSettings: context.sharedContext.applicationBindings.openSettings, { authorized in
                    guard !cancelled.with({ $0 }) else { return }
                    if !authorized {
                        subscriber.putError(.accessDenied)
                        return
                    }

                    let tempVideoPath = NSTemporaryDirectory() + "\(Int64.random(in: Int64.min ... Int64.max)).mp4"
                    let finish: (Bool, Error?) -> Void = { success, error in
                        guard !cancelled.with({ $0 }) else { return }
                        if success && error == nil {
                            subscriber.putNext(1.0)
                            subscriber.putCompletion()
                        } else {
                            subscriber.putError(.generic)
                        }
                    }
                    if isImage, let videoData, let imageData = try? Data(contentsOf: URL(fileURLWithPath: mainData.path)) {
                        let id = UUID().uuidString

                        guard let jpegWithID = addAssetIdentifierToJPEG(imageData, assetIdentifier: id) else {
                            subscriber.putError(.generic)
                            return
                        }
                        let outputVideoURL = URL(fileURLWithPath: NSTemporaryDirectory() + "\(id).mov")

                        do {
                            try FileManager.default.copyItem(atPath: videoData.path, toPath: tempVideoPath)
                        } catch {
                            subscriber.putError(.generic)
                            return
                        }

                        addAssetIdentifierToVideo(inputURL: URL(fileURLWithPath: tempVideoPath), outputURL: outputVideoURL, assetIdentifier: id) { success in
                            guard success, !cancelled.with({ $0 }) else {
                                try? FileManager.default.removeItem(atPath: tempVideoPath)
                                try? FileManager.default.removeItem(at: outputVideoURL)
                                subscriber.putError(.generic)
                                return
                            }

                            PHPhotoLibrary.shared().performChanges({
                                let request = PHAssetCreationRequest.forAsset()

                                request.addResource(with: .photo, data: jpegWithID, options: nil)
                                request.addResource(with: .pairedVideo, fileURL: outputVideoURL, options: nil)
                            }, completionHandler: { success, error in
                                try? FileManager.default.removeItem(atPath: tempVideoPath)
                                try? FileManager.default.removeItem(at: outputVideoURL)
                                finish(success, error)
                            })
                        }
                    } else if isImage {
                        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: mainData.path)), !imageData.isEmpty else {
                            subscriber.putError(.generic)
                            return
                        }
                        PHPhotoLibrary.shared().performChanges({
                            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: imageData, options: nil)
                        }, completionHandler: finish)
                    } else {
                        // MARK: Regram — video containers accepted for playback may require export before Photos can import them.
                        videoSaveDisposable.set(rgSaveVideoToPhotoLibrary(path: mainData.path, completion: { success in finish(success, nil) }))
                    }
                })

                return ActionDisposable {
                    let _ = cancelled.swap(true)
                    videoSaveDisposable.dispose()
                }
            }
        } else {
            return .complete()
        }
    }
}

// MARK: Regram — retry a rejected video as a standard MP4 and report the actual import result.
private func rgSaveVideoToPhotoLibrary(path: String, completion: @escaping (Bool) -> Void) -> Disposable {
    let cancelled = Atomic(value: false)
    let exportSession = Atomic<AVAssetExportSession?>(value: nil)
    let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    let originalURL = temporaryDirectory.appendingPathComponent("original.mp4")
    let exportedURL = temporaryDirectory.appendingPathComponent("exported.mp4")
    let finish: (Bool) -> Void = { success in
        try? FileManager.default.removeItem(at: temporaryDirectory)
        if !cancelled.with({ $0 }) { completion(success) }
    }
    do {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: originalURL)
    } catch {
        finish(false)
        return EmptyDisposable
    }

    let save: (URL, @escaping (Bool) -> Void) -> Void = { url, completion in
        guard !cancelled.with({ $0 }) else { finish(false); return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
        }, completionHandler: { success, error in
            completion(success && error == nil)
        })
    }
    save(originalURL, { success in
        guard !cancelled.with({ $0 }) else { finish(false); return }
        if success {
            finish(true)
            return
        }
        let asset = AVURLAsset(url: originalURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            finish(false)
            return
        }
        let _ = exportSession.swap(session)
        session.outputURL = exportedURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.exportAsynchronously {
            guard session.status == .completed, !cancelled.with({ $0 }) else {
                finish(false)
                return
            }
            save(exportedURL, finish)
        }
    })
    return ActionDisposable {
        let _ = cancelled.swap(true)
        exportSession.with({ $0 })?.cancelExport()
    }
}

public func copyToPasteboard(context: AccountContext, userLocation: MediaResourceUserLocation, mediaReference: AnyMediaReference) -> Signal<Void, NoError> {
    return fetchMediaData(context: context, userLocation: userLocation, mediaReference: mediaReference)
    |> mapToSignal { state, isImage -> Signal<Void, NoError> in
        if case let .data(data) = state, data.isComplete {
            return Signal<Void, NoError> { subscriber in
                let pasteboard = UIPasteboard.general

                if mediaReference.media is TelegramMediaImage {
                    if let fileData = try? Data(contentsOf: URL(fileURLWithPath: data.path), options: .mappedIfSafe) {
                        pasteboard.setData(fileData, forPasteboardType: UTType.jpeg.identifier)
                    }
                }
                subscriber.putNext(Void())
                subscriber.putCompletion()

                return EmptyDisposable
            }
        } else {
            return .complete()
        }
    }
    |> mapToSignal { _ -> Signal<Void, NoError> in return .complete() }
}

private func addAssetIdentifierToJPEG(_ imageData: Data, assetIdentifier: String) -> Data? {
    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil), let uti = CGImageSourceGetType(source), let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return nil
    }

    let mutableData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(mutableData, uti, 1, nil) else {
        return nil
    }

    var metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]

    var maker = metadata[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] ?? [:]
    maker["17"] = assetIdentifier
    metadata[kCGImagePropertyMakerAppleDictionary as String] = maker

    CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)
    CGImageDestinationFinalize(destination)

    return mutableData as Data
}

private func addAssetIdentifierToVideo(inputURL: URL, outputURL: URL, assetIdentifier: String, completion: @escaping (Bool) -> Void) {
    let asset = AVAsset(url: inputURL)

    guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
        completion(false)
        return
    }

    let identifierItem = AVMutableMetadataItem()
    identifierItem.keySpace = .quickTimeMetadata
    identifierItem.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier as NSString
    identifierItem.value = assetIdentifier as NSString

    let stillImageTimeItem = AVMutableMetadataItem()
    let keyStillImageTime = "com.apple.quicktime.still-image-time"
    let keySpaceQuickTimeMetadata = "mdta"
    stillImageTimeItem.key = keyStillImageTime as (NSCopying & NSObjectProtocol)?
    stillImageTimeItem.keySpace = AVMetadataKeySpace(rawValue: keySpaceQuickTimeMetadata)
    stillImageTimeItem.value = 0 as (NSCopying & NSObjectProtocol)?
    stillImageTimeItem.dataType = "com.apple.metadata.datatype.int8"

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mov
    exportSession.metadata = [identifierItem, stillImageTimeItem]
    exportSession.shouldOptimizeForNetworkUse = true

    exportSession.exportAsynchronously {
        completion(exportSession.status == .completed)
    }
}
