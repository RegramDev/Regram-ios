// MARK: Regram — projection only: no Telegram payment, gift mutation or balance APIs.
import Foundation
import TelegramCore
import AccountContext
import SwiftSignalKit
import RGSimpleSettings
import RGStrings
import PhoneNumberFormat

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

public func rgLocalGiftBalance(context: AccountContext, ton: Bool = false) -> Int64? {
    let state = RGLocalGiftsStore.shared.state(account: rgLocalGiftsAccount(context))
    return state.enabled ? (ton ? state.tonBalance : state.balance) : nil
}

/// Gift screens project this balance without changing the real wallet or its transactions.
public func rgGiftStarsBalance(context: AccountContext, source: Signal<StarsContext.State?, NoError>) -> Signal<StarsAmount, NoError> {
    combineLatest(source, rgLocalGiftsState(context: context)) |> map { remote, local in
        local.enabled ? StarsAmount(value: local.balance, nanos: 0) : (remote?.balance ?? .zero)
    } |> deliverOnMainQueue
}

public func rgGiftTonBalance(context: AccountContext, source: Signal<StarsContext.State?, NoError>) -> Signal<StarsAmount, NoError> {
    combineLatest(source, rgLocalGiftsState(context: context)) |> map { remote, local in
        local.enabled ? StarsAmount(value: local.tonBalance, nanos: 0) : (remote?.balance ?? .zero)
    } |> deliverOnMainQueue
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
    TelegramMediaFile(fileId: .init(namespace: Namespaces.Media.CloudFile, id: id), partialReference: nil,
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
    rgBuyLocalGift(context: context, gift: .generic(gift), price: gift.price)
}

private func localUniqueCopy(_ gift: StarGift.UniqueGift, id: Int64, attributes: [StarGift.UniqueGift.Attribute], owner: EnginePeer.Id) -> StarGift.UniqueGift {
    var modelId: Int64?, patternId: Int64?, color: PeerCollectibleColor?
    for attribute in attributes {
        switch attribute {
        case let .model(_, file, _, _): modelId = file.fileId.id
        case let .pattern(_, file, _): patternId = file.fileId.id
        default: break
        }
    }
    for attribute in attributes {
        if case let .backdrop(_, _, inner, outer, pattern, text, _) = attribute, let modelId, let patternId {
            color = PeerCollectibleColor(collectibleId: id, giftEmojiFileId: modelId, backgroundEmojiId: patternId,
                accentColor: UInt32(bitPattern: text), colors: [UInt32(bitPattern: inner), UInt32(bitPattern: outer)],
                darkAccentColor: UInt32(bitPattern: pattern), darkColors: nil)
        }
    }
    // A simulated collectible has no server slug, sale, wallet address or original owner.
    return StarGift.UniqueGift(id: id, giftId: gift.giftId, title: gift.title, number: gift.number,
        slug: "", owner: .peerId(owner), attributes: attributes, availability: gift.availability,
        giftAddress: nil, resellAmounts: nil, resellForTonOnly: false, releasedBy: nil,
        valueAmount: nil, valueCurrency: nil, valueUsdAmount: nil, flags: [], themePeerId: nil,
        peerColor: color, hostPeerId: nil, minOfferStars: nil, craftChancePermille: nil)
}

private func localPattern(context: AccountContext) -> TelegramMediaFile? {
    guard let directory = localAssets(context: context), let data = Data(base64Encoded: "H4sIAAAAAAAC/6tWKlOyUjLVM9czUdJRSitSsjI20FHKLFCyAlL5BRBuuZKVoQGQzoDSeblAPT75yYk5Cqm5BSWVCgWJJSWpRXlAE1JSUsBaE4uLU0uKlayiY3WUchIrU4vA7FoAhanBR28AAAA=") else { return nil }
    let url = directory.appendingPathComponent("empty-pattern.asset")
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
    } catch { return nil }
    return TelegramMediaFile(fileId: .init(namespace: Namespaces.Media.CloudFile, id: -84631002), partialReference: nil,
        resource: LocalFileReferenceMediaResource(localFilePath: url.path, randomId: -84631002),
        previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/x-tgsticker",
        size: Int64(data.count), attributes: [.FileName(fileName: "local_pattern.tgs"), .Animated], alternativeRepresentations: [])
}

private func completeLocalAttributes(context: AccountContext, attributes: [StarGift.UniqueGift.Attribute]) -> [StarGift.UniqueGift.Attribute] {
    if !attributes.contains(where: { if case .pattern = $0 { return true }; return false }), let pattern = localPattern(context: context) {
        return attributes + [.pattern(name: "", file: pattern, rarity: .rare)]
    }
    return attributes
}

public func rgBuyLocalGift(context: AccountContext, gift: StarGift, price: Int64, currency: RGLocalGiftCurrency = .stars) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
    guard rgLocalGiftsEnabled(context: context) else { return .failure(.disabled) }
    guard price > 0 else { return .failure(.invalidAmount) }
    guard let directory = localAssets(context: context) else { return .failure(.storage) }
    var snapshots: [URL] = []
    var committed = false
    defer { if !committed { for path in snapshots { try? FileManager.default.removeItem(at: path) } } }
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func snapshot(_ file: TelegramMediaFile) throws -> TelegramMediaFile {
            let path: String?
            if let resource = file.resource as? LocalFileReferenceMediaResource {
                path = resource.localFilePath
            } else {
                path = context.engine.resources.completedResourcePath(id: EngineMediaResource(file.resource).id)
            }
            guard let path else { throw RGLocalGiftsError.storage }
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard let size = attributes[.size] as? NSNumber, size.int64Value > 0, size.int64Value <= 8 * 1024 * 1024 else { throw RGLocalGiftsError.storage }
            let destination = directory.appendingPathComponent(UUID().uuidString + ".asset")
            do {
                try Data(contentsOf: URL(fileURLWithPath: path)).write(to: destination, options: .atomic)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            snapshots.append(destination)
            return localArtwork(file, path: destination.path, id: Int64.random(in: Int64.min ... -1))
        }
        let stored: StarGift
        let title: String
        let language = context.sharedContext.currentPresentationData.with { $0 }.strings.rgLanguageCode
        switch gift {
        case let .generic(generic):
            let source = rgCachedLocalGift(context: context, gift: generic)?.file
            guard let source else { return .failure(.storage) }
            stored = .generic(localCopy(generic, file: try snapshot(source)))
            title = rgLocalGiftTitle(generic, language: language)
        case let .unique(unique):
            var attributes: [StarGift.UniqueGift.Attribute] = []
            var hasModel = false
            for attribute in unique.attributes {
                switch attribute {
                case let .model(name, file, rarity, crafted):
                    attributes.append(.model(name: name, file: try snapshot(file), rarity: rarity, crafted: crafted))
                    hasModel = true
                case let .pattern(name, file, rarity):
                    if let file = try? snapshot(file) { attributes.append(.pattern(name: name, file: file, rarity: rarity)) }
                case .backdrop:
                    attributes.append(attribute)
                case .originalInfo:
                    break
                }
            }
            guard hasModel else { return .failure(.storage) }
            stored = .unique(localUniqueCopy(unique, id: Int64.random(in: Int64.min ... -1), attributes: completeLocalAttributes(context: context, attributes: attributes), owner: context.account.peerId))
            title = unique.title + " #\(unique.number)"
        }
        let data = try JSONEncoder().encode(stored)
        let result = RGLocalGiftsStore.shared.purchase(account: rgLocalGiftsAccount(context), title: title, price: price, gift: data, currency: currency)
        if case .success = result { committed = true }
        return result
    } catch { return .failure(.storage) }
}

public func rgLocalGift(context: AccountContext, purchase: RGLocalGiftPurchase) -> StarGift? {
    guard let gift = try? JSONDecoder().decode(StarGift.self, from: purchase.gift) else { return nil }
    // An iOS data container/bundle path can change on upgrade; rebind to the current container.
    func rebound(_ file: TelegramMediaFile) -> TelegramMediaFile? {
        guard let directory = localAssets(context: context), let resource = file.resource as? LocalFileReferenceMediaResource else { return nil }
        let path = directory.appendingPathComponent(URL(fileURLWithPath: resource.localFilePath).lastPathComponent).path
        if FileManager.default.fileExists(atPath: path) {
            let id = resource.randomId > 0 ? -resource.randomId : (resource.randomId == 0 ? -84631003 : resource.randomId)
            return localArtwork(file, path: path, id: id)
        }
        return nil
    }
    switch gift {
    case let .generic(generic):
        guard let file = rebound(generic.file) ?? rgLocalFallbackGift()?.file else { return nil }
        return .generic(localCopy(generic, file: file))
    case let .unique(unique):
        var attributes: [StarGift.UniqueGift.Attribute] = []
        var hasModel = false
        for attribute in unique.attributes {
            switch attribute {
            case let .model(name, file, rarity, crafted):
                if let file = rebound(file) { attributes.append(.model(name: name, file: file, rarity: rarity, crafted: crafted)); hasModel = true }
            case let .pattern(name, file, rarity):
                if let file = rebound(file) { attributes.append(.pattern(name: name, file: file, rarity: rarity)) }
            case .backdrop: attributes.append(attribute)
            case .originalInfo: break
            }
        }
        guard hasModel else { return nil }
        return .unique(localUniqueCopy(unique, id: unique.id, attributes: completeLocalAttributes(context: context, attributes: attributes), owner: context.account.peerId))
    }
}

public func rgRemoveLocalGift(context: AccountContext, purchase: RGLocalGiftPurchase) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
    let result = RGLocalGiftsStore.shared.remove(account: rgLocalGiftsAccount(context), id: purchase.id)
    if case .success = result, let gift = try? JSONDecoder().decode(StarGift.self, from: purchase.gift), let directory = localAssets(context: context) {
        let files: [TelegramMediaFile]
        switch gift {
        case let .generic(generic): files = [generic.file]
        case let .unique(unique): files = unique.attributes.compactMap { attribute in
            switch attribute {
            case let .model(_, file, _, _), let .pattern(_, file, _): return file
            default: return nil
            }
        }
        }
        // Every purchase owns a unique snapshot. Only remove a file inside this account's asset directory.
        for file in files {
            guard let resource = file.resource as? LocalFileReferenceMediaResource else { continue }
            let path = directory.appendingPathComponent(URL(fileURLWithPath: resource.localFilePath).lastPathComponent)
            guard path.lastPathComponent != "empty-pattern.asset" else { continue }
            try? FileManager.default.removeItem(at: path)
        }
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
            return rgLocalProfileGift(gift: gift, purchase: purchase)
        }
        let filtered = gifts.filter { item in
            guard state.filter.contains(item.savedToProfile ? .displayed : .hidden) else { return false }
            switch item.gift {
            case let .generic(gift):
                if state.filter.contains(.peerColor), !gift.flags.contains(.peerColorAvailable) { return false }
                if gift.availability == nil { return state.filter.contains(.unlimited) }
                return state.filter.contains(.limitedNonUpgradable)
            case let .unique(gift):
                if state.filter.contains(.peerColor), gift.peerColor == nil { return false }
                return state.filter.contains(.unique)
            }
        }
        // Preserve upstream ordering between server gifts; only insert local items around it.
        let prices = Dictionary(uniqueKeysWithValues: local.purchases.filter { $0.currency == .stars }.map { ($0.id, $0.price) })
        func price(_ item: ProfileGiftsContext.State.StarGift) -> Int64? {
            if let id = rgLocalGiftPurchaseId(gift: item) { return prices[id] }
            switch item.gift {
            case let .generic(gift): return gift.price
            case let .unique(gift): return gift.resellAmounts?.first(where: { $0.currency == .stars })?.amount.value
            }
        }
        func merged(_ serverItems: [ProfileGiftsContext.State.StarGift], _ additions: [ProfileGiftsContext.State.StarGift]) -> [ProfileGiftsContext.State.StarGift] {
            var result = serverItems
            let sorted = additions.sorted { lhs, rhs in
                if lhs.pinnedToTop != rhs.pinnedToTop { return lhs.pinnedToTop }
                if remote.sorting == .value, let a = price(lhs), let b = price(rhs), a != b { return a > b }
                return lhs.date > rhs.date
            }
            for item in sorted {
                let index = result.firstIndex { other in
                    if item.pinnedToTop { return !other.pinnedToTop }
                    guard !other.pinnedToTop else { return false }
                    if remote.sorting == .value, let a = price(item), let b = price(other) { return a > b }
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

public func rgLocalProfileGift(gift: StarGift, purchase: RGLocalGiftPurchase) -> ProfileGiftsContext.State.StarGift {
    return ProfileGiftsContext.State.StarGift(gift: gift, reference: nil, fromPeer: nil,
        date: purchase.date, text: "Regram.LocalGift:" + purchase.id.uuidString, entities: nil,
        nameHidden: false, savedToProfile: purchase.savedToProfile, pinnedToTop: purchase.pinnedToTop, convertStars: nil,
        canUpgrade: false, canExportDate: nil, upgradeStars: nil, transferStars: nil,
        canTransferDate: nil, canResaleDate: nil, collectionIds: nil, prepaidUpgradeHash: nil,
        upgradeSeparate: false, dropOriginalDetailsStars: nil, number: nil, isRefunded: false, canCraftAt: nil)
}

public func rgLocalGiftPurchase(context: AccountContext, id: UUID) -> RGLocalGiftPurchase? {
    let state = RGLocalGiftsStore.shared.state(account: rgLocalGiftsAccount(context))
    return state.enabled ? state.purchases.first(where: { $0.id == id }) : nil
}

public func rgSetLocalGiftVisibility(context: AccountContext, id: UUID, saved: Bool) {
    _ = RGLocalGiftsStore.shared.setVisibility(account: rgLocalGiftsAccount(context), id: id, saved: saved)
}

public func rgDeleteLocalGift(context: AccountContext, id: UUID) {
    guard let purchase = rgLocalGiftPurchase(context: context, id: id) else { return }
    _ = rgRemoveLocalGift(context: context, purchase: purchase)
}

public func rgSetLocalGiftPinned(context: AccountContext, id: UUID, pinned: Bool, profileGifts: ProfileGiftsContext? = nil) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
    guard let purchase = rgLocalGiftPurchase(context: context, id: id), case .unique = rgLocalGift(context: context, purchase: purchase) else { return .failure(.storage) }
    let configuredLimit = context.currentAppConfiguration.with { $0 }.data?["stargifts_pinned_to_top_limit"] as? Double
    let limit: Int
    if let configuredLimit, configuredLimit.isFinite, configuredLimit >= 0 {
        limit = Int(min(Double(RGLocalGiftsStore.maximumPinnedGifts), configuredLimit))
    } else {
        limit = 6
    }
    let serverPins = profileGifts?.currentState?.gifts.filter { $0.pinnedToTop }.count ?? 0
    return RGLocalGiftsStore.shared.setPinned(account: rgLocalGiftsAccount(context), id: id, pinned: pinned, maximumCount: max(0, limit - serverPins))
}

public func rgFormattedDisplayedPhone(context: AccountContext, peerId: EnginePeer.Id, phone: String?) -> String? {
    if peerId == context.account.peerId {
        let state = RGLocalGiftsStore.shared.state(account: rgLocalGiftsAccount(context))
        if state.phoneEnabled {
            return rgFormatLocalPhoneNumber(state.phoneNumber) { formatPhoneNumber(context: context, number: $0) }
        }
    }
    return phone.map { formatPhoneNumber(context: context, number: $0) }
}
