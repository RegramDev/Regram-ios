// MARK: Regram — account-scoped display overlays; no account/profile update RPCs.
import Foundation
import TelegramCore
import AccountContext
import SwiftSignalKit
import RGSimpleSettings

private struct LocalAppearance: Codable {
    let namePreset: Int32?
    let nameCollectible: PeerCollectibleColor?
    let profileColor: Int32?
    let replyFileId: Int64?
    let backgroundFileId: Int64?
    let emojiStatus: PeerEmojiStatus?
}

public func rgSaveLocalGiftAppearance(context: AccountContext, nameColor: PeerColor, profileColor: PeerNameColor?, replyFileId: Int64?, backgroundFileId: Int64?, emojiStatus: PeerEmojiStatus?) -> Bool {
    let state = RGLocalGiftsStore.shared.state(account: rgLocalGiftsAccount(context))
    guard state.enabled else { return false }
    var profileGiftId: UUID?, nameGiftId: UUID?
    var namePreset: Int32?, nameCollectible: PeerCollectibleColor?
    switch nameColor {
    case let .preset(color): namePreset = color.rawValue
    case let .collectible(color): nameCollectible = color
    }
    for purchase in state.purchases {
        guard case let .unique(gift) = rgLocalGift(context: context, purchase: purchase) else { continue }
        if nameCollectible?.collectibleId == gift.id { nameGiftId = purchase.id }
        if case let .starGift(id, _, _, _, _, _, _, _, _) = emojiStatus?.content, id == gift.id { profileGiftId = purchase.id }
    }
    if let color = nameCollectible, color.collectibleId < 0, nameGiftId == nil { return false }
    if case let .starGift(id, _, _, _, _, _, _, _, _) = emojiStatus?.content, id < 0, profileGiftId == nil { return false }
    let appearance = LocalAppearance(namePreset: namePreset, nameCollectible: nameCollectible, profileColor: profileColor?.rawValue,
        replyFileId: replyFileId, backgroundFileId: backgroundFileId, emojiStatus: emojiStatus)
    guard let data = try? JSONEncoder().encode(appearance) else { return false }
    if case .success = RGLocalGiftsStore.shared.setAppearance(account: rgLocalGiftsAccount(context), profileGiftId: profileGiftId, nameGiftId: nameGiftId, appearance: data) { return true }
    return false
}

/// Prime only local inline media before projecting a gift status or collectible name color.
public func rgLocalAppearanceState(context: AccountContext) -> Signal<RGLocalGiftsState, NoError> {
    rgLocalGiftsState(context: context) |> mapToSignal { state -> Signal<RGLocalGiftsState, NoError> in
        guard state.enabled else { return .single(state) }
        let files: [TelegramMediaFile] = state.purchases.flatMap { purchase -> [TelegramMediaFile] in
            guard case let .unique(gift) = rgLocalGift(context: context, purchase: purchase) else { return [] }
            return gift.attributes.compactMap { attribute -> TelegramMediaFile? in
                switch attribute {
                case let .model(_, file, _, _), let .pattern(_, file, _): return file
                default: return nil
                }
            }
        }
        return Signal<RGLocalGiftsState, NoError> { subscriber in
            context.engine.stickers.cacheLocalGiftInlineStickers(files: files).start(completed: {
                subscriber.putNext(state)
                subscriber.putCompletion()
            })
        }
    } |> deliverOnMainQueue
}

public func rgLocalAppearancePeer(context: AccountContext, peer: EnginePeer) -> EnginePeer {
    guard peer.id == context.account.peerId, case let .user(user) = peer else { return peer }
    let state = RGLocalGiftsStore.shared.state(account: rgLocalGiftsAccount(context))
    guard state.enabled, let data = state.appearance, let appearance = try? JSONDecoder().decode(LocalAppearance.self, from: data) else { return peer }
    // Rebind negative model/pattern IDs when reading purchases made by older app builds.
    var emojiStatus = appearance.emojiStatus
    var nameColor = appearance.nameCollectible.map(PeerColor.collectible) ?? appearance.namePreset.map(PeerNameColor.init(rawValue:)).map(PeerColor.preset)
    if let id = state.profileGiftId, let purchase = state.purchases.first(where: { $0.id == id }), case let .unique(gift) = rgLocalGift(context: context, purchase: purchase) {
        emojiStatus = rgLocalGiftEmojiStatus(gift)
    }
    if let id = state.nameGiftId, let purchase = state.purchases.first(where: { $0.id == id }), case let .unique(gift) = rgLocalGift(context: context, purchase: purchase), let color = gift.peerColor {
        nameColor = .collectible(color)
    }
    return .user(user.withUpdatedNameColor(nameColor ?? .preset(.blue)).withUpdatedBackgroundEmojiId(appearance.replyFileId)
        .withUpdatedProfileColor(appearance.profileColor.map(PeerNameColor.init(rawValue:)))
        .withUpdatedProfileBackgroundEmojiId(appearance.backgroundFileId).withUpdatedEmojiStatus(emojiStatus))
}

public func rgLocalGiftEmojiStatus(_ gift: StarGift.UniqueGift) -> PeerEmojiStatus? {
    var modelId: Int64?, patternId: Int64?
    for attribute in gift.attributes {
        switch attribute {
        case let .model(_, file, _, _): modelId = file.fileId.id
        case let .pattern(_, file, _): patternId = file.fileId.id
        default: break
        }
    }
    for attribute in gift.attributes {
        if case let .backdrop(_, _, inner, outer, pattern, text, _) = attribute, let modelId, let patternId {
            return PeerEmojiStatus(content: .starGift(id: gift.id, fileId: modelId, title: gift.title, slug: "", patternFileId: patternId,
                innerColor: inner, outerColor: outer, patternColor: pattern, textColor: text), expirationDate: nil)
        }
    }
    return nil
}

public func rgLocalUniqueGifts(context: AccountContext) -> [StarGift.UniqueGift] {
    let state = RGLocalGiftsStore.shared.state(account: rgLocalGiftsAccount(context))
    guard state.enabled else { return [] }
    return state.purchases.compactMap { purchase in
        if case let .unique(gift) = rgLocalGift(context: context, purchase: purchase) { return gift }
        return nil
    }
}

public func rgIsLocalGiftAppearance(nameColor: PeerColor, emojiStatus: PeerEmojiStatus?) -> Bool {
    if case let .collectible(color) = nameColor, color.collectibleId < 0 { return true }
    if case let .starGift(id, _, _, _, _, _, _, _, _) = emojiStatus?.content, id < 0 { return true }
    return false
}
