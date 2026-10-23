// MARK: Regram — projection only: no Telegram payment, gift mutation or balance APIs.
import Foundation
import TelegramCore
import AccountContext
import SwiftSignalKit
import RGSimpleSettings
import RGStrings

public func rgLocalGiftsAccount(_ context: AccountContext) -> String {
    return (context.account.testingEnvironment ? "test:" : "live:") + String(context.account.peerId.toInt64())
}

public func rgLocalGiftsState(context: AccountContext) -> Signal<RGLocalGiftsState, NoError> {
    let account = rgLocalGiftsAccount(context)
    return Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: RGLocalGiftsStore.didChange, object: nil, queue: nil) { notification in
            guard notification.object as? String == account else { return }
            // Read on delivery, so concurrently posted changes cannot publish an old snapshot.
            Queue.mainQueue().async { subscriber.putNext(RGLocalGiftsStore.shared.state(account: account)) }
        }
        subscriber.putNext(RGLocalGiftsStore.shared.state(account: account))
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    } |> distinctUntilChanged |> deliverOnMainQueue
}

public func rgLocalGiftsEnabled(context: AccountContext) -> Bool {
    RGLocalGiftsStore.shared.state(account: rgLocalGiftsAccount(context)).enabled
}

private let fallbackId: Int64 = -84631001

/// Bundled animation means a newly installed account can also buy a local gift offline.
public func rgLocalFallbackGift() -> StarGift.Gift? {
    guard let path = Bundle.main.path(forResource: "anim_gift", ofType: "tgs") else { return nil }
    let file = TelegramMediaFile(
        fileId: .init(namespace: 0, id: fallbackId), partialReference: nil,
        resource: LocalFileReferenceMediaResource(localFilePath: path, randomId: fallbackId),
        previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil,
        mimeType: "application/x-tgsticker", size: nil,
        attributes: [.FileName(fileName: "local_gift.tgs"), .Animated], alternativeRepresentations: []
    )
    return StarGift.Gift(id: fallbackId, title: nil, file: file, price: 100, convertStars: 0,
        availability: nil, soldOut: nil, flags: [], upgradeStars: nil, releasedBy: nil,
        perUserLimit: nil, lockedUntilDate: nil, auctionSlug: nil, auctionGiftsPerRound: nil,
        auctionStartDate: nil, upgradeVariantsCount: nil, background: nil)
}

public func rgLocalGiftTitle(_ gift: StarGift.Gift, language: String) -> String {
    gift.title ?? "LocalGifts.Gift".i18n(language)
}

private func localAssets(context: AccountContext) -> URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("RegramLocalGifts", isDirectory: true)
        .appendingPathComponent(rgLocalGiftsAccount(context), isDirectory: true)
}

private func localArtwork(_ file: TelegramMediaFile, path: String, id: Int64) -> TelegramMediaFile {
    TelegramMediaFile(fileId: file.fileId, partialReference: nil,
        resource: LocalFileReferenceMediaResource(localFilePath: path, randomId: id),
        previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: file.immediateThumbnailData,
        mimeType: file.mimeType, size: file.size, attributes: file.attributes, alternativeRepresentations: [])
}

private func localCopy(_ gift: StarGift.Gift, file: TelegramMediaFile) -> StarGift.Gift {
    // Keep the artwork and price; server-only auction, upgrade and availability actions do not apply.
    StarGift.Gift(id: gift.id, title: gift.title, file: file, price: gift.price, convertStars: 0,
        availability: gift.availability, soldOut: nil, flags: gift.flags.subtracting([.isAuction, .requiresPremium]),
        upgradeStars: nil, releasedBy: nil, perUserLimit: nil, lockedUntilDate: nil,
        auctionSlug: nil, auctionGiftsPerRound: nil, auctionStartDate: nil, upgradeVariantsCount: nil, background: gift.background)
}

/// A cache lookup never starts a fetch. Using local resources also prevents the native preview from fetching artwork.
public func rgCachedLocalGift(context: AccountContext, gift: StarGift.Gift) -> StarGift.Gift? {
    let path: String?
    if let resource = gift.file.resource as? LocalFileReferenceMediaResource {
        path = FileManager.default.fileExists(atPath: resource.localFilePath) ? resource.localFilePath : nil
    } else {
        path = context.engine.resources.completedResourcePath(id: EngineMediaResource(gift.file.resource).id)
    }
    guard let path else { return nil }
    return localCopy(gift, file: localArtwork(gift.file, path: path, id: gift.id))
}

public func rgBuyLocalGift(context: AccountContext, gift: StarGift.Gift) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
    guard rgLocalGiftsEnabled(context: context) else { return .failure(.disabled) }
    // Snapshot already cached artwork. No resource-fetch or checkout service is involved.
    guard let directory = localAssets(context: context),
          let source = rgCachedLocalGift(context: context, gift: gift)?.file ?? rgLocalFallbackGift()?.file,
          let resource = source.resource as? LocalFileReferenceMediaResource else { return .failure(.storage) }
    do {
        let attributes = try FileManager.default.attributesOfItem(atPath: resource.localFilePath)
        guard let size = attributes[.size] as? NSNumber, size.int64Value > 0, size.int64Value <= 8 * 1024 * 1024 else { return .failure(.storage) }
        let artwork = try Data(contentsOf: URL(fileURLWithPath: resource.localFilePath))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString + ".asset")
        try artwork.write(to: destination, options: .atomic)
        let file = localArtwork(source, path: destination.path, id: Int64.random(in: Int64.min...Int64.max))
        let data = try JSONEncoder().encode(StarGift.generic(localCopy(gift, file: file)))
        let language = context.sharedContext.currentPresentationData.with { $0 }.strings.rgLanguageCode
        let result = RGLocalGiftsStore.shared.purchase(account: rgLocalGiftsAccount(context), title: rgLocalGiftTitle(gift, language: language), price: gift.price, gift: data)
        if case .failure = result { try? FileManager.default.removeItem(at: destination) }
        return result
    } catch { return .failure(.storage) }
}

public func rgLocalGift(context: AccountContext, purchase: RGLocalGiftPurchase) -> StarGift.Gift? {
    guard let gift = try? JSONDecoder().decode(StarGift.self, from: purchase.gift), case let .generic(generic) = gift else { return nil }
    // An iOS data container/bundle path can change on upgrade; rebind to the current container.
    if let directory = localAssets(context: context), let resource = generic.file.resource as? LocalFileReferenceMediaResource {
        let path = directory.appendingPathComponent(URL(fileURLWithPath: resource.localFilePath).lastPathComponent).path
        if FileManager.default.fileExists(atPath: path) {
            return localCopy(generic, file: localArtwork(generic.file, path: path, id: resource.randomId))
        }
    }
    if let fallback = rgLocalFallbackGift() { return localCopy(generic, file: fallback.file) }
    return nil
}

public func rgRemoveLocalGift(context: AccountContext, purchase: RGLocalGiftPurchase) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
    let result = RGLocalGiftsStore.shared.remove(account: rgLocalGiftsAccount(context), id: purchase.id)
    if case .success = result,
       let gift = try? JSONDecoder().decode(StarGift.self, from: purchase.gift), case let .generic(generic) = gift,
       let resource = generic.file.resource as? LocalFileReferenceMediaResource,
       let directory = localAssets(context: context) {
        // Every purchase owns a unique snapshot. Only remove a file inside this account's asset directory.
        let file = directory.appendingPathComponent(URL(fileURLWithPath: resource.localFilePath).lastPathComponent)
        try? FileManager.default.removeItem(at: file)
    }
    return result
}

public func rgLocalGiftPurchaseId(gift: ProfileGiftsContext.State.StarGift) -> UUID? {
    // Identity survives deletion/disable notifications, so a stale tile still cannot open server actions.
    guard gift.reference == nil, let text = gift.text, text.hasPrefix("Regram.LocalGift:") else { return nil }
    return UUID(uuidString: String(text.dropFirst("Regram.LocalGift:".count)))
}

/// Merge for display in the owner's uncollected profile pane only. Server contexts stay intact.
public func rgLocalGiftProfileState(context: AccountContext, peerId: EnginePeer.Id, profileGifts: ProfileGiftsContext, canSelect: Bool) -> Signal<ProfileGiftsContext.State, NoError> {
    guard peerId == context.account.peerId, profileGifts.collectionId == nil, !canSelect else { return profileGifts.state }
    return combineLatest(profileGifts.state, rgLocalGiftsState(context: context)) |> map { remote, local in
        guard local.enabled else { return remote }
        var state = remote
        let gifts: [ProfileGiftsContext.State.StarGift] = local.purchases.compactMap { purchase in
            guard let gift = rgLocalGift(context: context, purchase: purchase) else { return nil }
            return ProfileGiftsContext.State.StarGift(gift: .generic(gift), reference: nil, fromPeer: nil,
                date: purchase.date, text: "Regram.LocalGift:" + purchase.id.uuidString, entities: nil,
                nameHidden: false, savedToProfile: true, pinnedToTop: false, convertStars: nil,
                canUpgrade: false, canExportDate: nil, upgradeStars: nil, transferStars: nil,
                canTransferDate: nil, canResaleDate: nil, collectionIds: nil, prepaidUpgradeHash: nil,
                upgradeSeparate: false, dropOriginalDetailsStars: nil, number: nil, isRefunded: false, canCraftAt: nil)
        }
        let filtered = gifts.filter { item in
            guard state.filter.contains(.displayed), case let .generic(gift) = item.gift else { return false }
            if state.filter.contains(.peerColor), !gift.flags.contains(.peerColorAvailable) { return false }
            if gift.availability == nil { return state.filter.contains(.unlimited) }
            return state.filter.contains(gift.upgradeStars == nil ? .limitedNonUpgradable : .limitedUpgradable)
        }
        // Preserve upstream ordering between server gifts; only insert local items around it.
        func merged(_ serverItems: [ProfileGiftsContext.State.StarGift], _ additions: [ProfileGiftsContext.State.StarGift]) -> [ProfileGiftsContext.State.StarGift] {
            var result = serverItems
            let sorted = additions.sorted { lhs, rhs in
                if remote.sorting == .value, case let .generic(a) = lhs.gift, case let .generic(b) = rhs.gift, a.price != b.price { return a.price > b.price }
                return lhs.date > rhs.date
            }
            for item in sorted {
                let index = result.firstIndex { other in
                    guard !other.pinnedToTop else { return false }
                    if remote.sorting == .value, case let .generic(a) = item.gift, case let .generic(b) = other.gift { return a.price > b.price }
                    if remote.sorting == .value { return false }
                    return item.date > other.date
                } ?? result.endIndex
                result.insert(item, at: index)
            }
            return result
        }
        state.gifts = merged(remote.gifts, gifts)
        state.filteredGifts = merged(remote.filteredGifts, filtered)
        state.count = Int32(clamping: Int64(remote.count ?? Int32(clamping: remote.gifts.count)) + Int64(gifts.count))
        return state
    } |> deliverOnMainQueue
}
