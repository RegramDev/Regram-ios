// MARK: Regram — render the local ledger with Telegram's wallet card components.
import Foundation
import AccountContext
import TelegramCore
import TelegramPresentationData
import WalletContext
import RGSimpleSettings
import RGStrings

public func rgLocalWalletEnabled(context: AccountContext, peerId: EnginePeer.Id) -> Bool {
    guard peerId == context.account.peerId else { return false }
    let state = RGLocalGiftsStore.shared.state(account: rgLocalGiftsAccount(context))
    return state.enabled && state.walletCardEnabled
}

public func rgLocalWalletNotice(context: AccountContext) -> String {
    "LocalWallet.Notice".i18n(context.sharedContext.currentPresentationData.with { $0 }.strings.rgLanguageCode)
}

/// Only rendering data is passed to the native card. There is no NFT, slug or receiving address.
public func rgLocalWalletStickers(context: AccountContext, state localState: RGLocalGiftsState? = nil) -> [WalletContext.CardSticker] {
    let state = localState ?? RGLocalGiftsStore.shared.state(account: rgLocalGiftsAccount(context))
    guard state.enabled && state.walletCardEnabled else { return [] }
    let gifts = state.purchases.filter { $0.savedToProfile && $0.pinnedToTop }.compactMap { purchase -> (RGLocalGiftPurchase, StarGift.UniqueGift)? in
        guard case let .unique(gift) = rgLocalGift(context: context, purchase: purchase) else { return nil }
        return (purchase, gift)
    }.prefix(6)
    let positions: [(Double, Double, Double)] = [(0.16, 0.21, -0.18), (0.65, 0.19, 0.16), (0.86, 0.78, 0.18), (0.46, 0.79, -0.15), (0.89, 0.2, 0.12), (0.14, 0.78, -0.12)]
    return gifts.enumerated().compactMap { index, item in
        let (purchase, gift) = item
        var model: Data?, pattern: Data?
        for attribute in gift.attributes {
            switch attribute {
            case let .model(_, file, _, _):
                let encoder = EnginePostboxEncoder(); encoder.encodeRootObject(file); model = encoder.makeData()
            case let .pattern(_, file, _):
                let encoder = EnginePostboxEncoder(); encoder.encodeRootObject(file); pattern = encoder.makeData()
            default: break
            }
        }
        guard let model else { return nil }
        var style: WalletContext.CardGiftStyle?
        for case let .backdrop(_, _, inner, outer, color, _, _) in gift.attributes {
            style = .init(innerColor: inner, outerColor: outer, patternColor: color, patternFile: pattern)
        }
        let collectible = WalletContext.Collectible(address: "regram-local:" + purchase.id.uuidString, name: gift.title, subtitle: "", kind: .gift)
        let position = positions[index]
        return WalletContext.CardSticker(gift: collectible, x: position.0, y: position.1, angle: position.2,
            scale: 1.0, modelFile: model, geometryVersion: 2, giftStyle: style)
    }
}
