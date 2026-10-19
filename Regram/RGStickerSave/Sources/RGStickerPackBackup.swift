// MARK: Regram — export original sticker files and a portable manifest, without account credentials.
import Foundation
import TelegramCore
import AccountContext
import SwiftSignalKit
import SaveToCameraRoll
import ZipArchive

public enum RGStickerPackBackupError: Error { case unavailable, tooLarge, download, io }
public func rgBackupStickerPack(context: AccountContext, info: StickerPackCollectionInfo, items: [StickerPackItem], progress: @escaping (Int, Int) -> Void) -> Signal<URL, RGStickerPackBackupError> {
    guard !items.isEmpty, items.count <= 500 else { return .fail(.tooLarge) }
    return Signal { subscriber in
        let queue = Queue(name: "regram.sticker-pack-backup")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Regram-Stickers-" + UUID().uuidString)
        let contents = directory.appendingPathComponent("contents", isDirectory: true)
        let disposable = MetaDisposable()
        let cancelled = Atomic<Bool>(value: false)
        var completed = false
        var bytes: Int64 = 0
        var records: [[String: Any]] = []
        queue.async {
            do { try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true) } catch { subscriber.putError(.io); return }
            func next(_ index: Int) {
                guard !cancelled.with({ $0 }) else { return }
                if index == items.count {
                    do {
                        let manifest: [String: Any] = ["schema": 1, "format": "Regram.StickerPack", "title": info.title, "shortName": info.shortName, "kind": info.id.namespace == Namespaces.ItemCollection.CloudEmojiPacks ? "emoji" : "sticker", "items": records]
                        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted]).write(to: contents.appendingPathComponent("pack.json"), options: .atomic)
                        let archive = directory.appendingPathComponent("Regram-StickerPack.zip")
                        guard SSZipArchive.createZipFile(atPath: archive.path, withContentsOfDirectory: contents.path, keepParentDirectory: false), !cancelled.with({ $0 }) else { throw RGStickerPackBackupError.io }
                        try FileManager.default.removeItem(at: contents)
                        completed = true; subscriber.putNext(archive); subscriber.putCompletion()
                    } catch { subscriber.putError(.io); try? FileManager.default.removeItem(at: directory) }
                    return
                }
                let item = items[index], file = item.file._parse()
                let reference = FileMediaReference.stickerPack(stickerPack: .id(id: info.id.id, accessHash: info.accessHash), media: file)
                disposable.set((fetchMediaData(context: context, userLocation: .other, mediaReference: reference.abstract)
                    |> map { value -> String? in if case let .data(data) = value.0, data.isComplete { return data.path }; return nil }
                    |> filter { $0 != nil } |> take(1) |> castError(RGStickerPackBackupError.self)
                    |> timeout(120, queue: queue, alternate: .fail(.download)) |> deliverOn(queue)).start(next: { path in
                        guard let path, !cancelled.with({ $0 }) else { return }
                        do {
                            let size = (try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
                            guard size > 0, size <= 32 * 1024 * 1024, bytes + size <= 256 * 1024 * 1024 else { throw RGStickerPackBackupError.tooLarge }
                            let ext = file.isAnimatedSticker ? "tgs" : file.isVideoSticker ? "webm" : file.mimeType == "image/png" ? "png" : "webp"
                            let name = String(format: "%04d", index + 1) + "." + ext
                            try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: contents.appendingPathComponent(name))
                            bytes += size; records.append(["file": name, "id": String(file.fileId.id), "emoji": item.getStringRepresentationsOfIndexKeys(), "mimeType": file.mimeType])
                            progress(index + 1, items.count); next(index + 1)
                        } catch let error as RGStickerPackBackupError { subscriber.putError(error); try? FileManager.default.removeItem(at: directory) }
                        catch { subscriber.putError(.io); try? FileManager.default.removeItem(at: directory) }
                    }, error: { error in subscriber.putError(error); try? FileManager.default.removeItem(at: directory) }))
            }
            next(0)
        }
        return ActionDisposable {
            let _ = cancelled.swap(true); disposable.dispose()
            queue.async { if !completed { try? FileManager.default.removeItem(at: directory) } }
        }
    }
}
