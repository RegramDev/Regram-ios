// MARK: Regram — project the owner's rating into native profile components only.
import TelegramCore
import AccountContext
import RGSimpleSettings

public func rgLocalProfileCachedData(context: AccountContext, peerId: EnginePeer.Id, cachedData: EngineCachedPeerData?, localState: RGLocalGiftsState) -> EngineCachedPeerData? {
    guard peerId == context.account.peerId else { return cachedData }
    guard localState.ratingEnabled || (localState.enabled && localState.walletCardEnabled) else { return cachedData }
    var result = (cachedData as? CachedUserData) ?? CachedUserData()
    if localState.ratingEnabled {
        let level = localState.ratingLevel
        let points = Int64(level) * 1_000
        let rating = TelegramStarRating(level: level, currentLevelStars: points, stars: points, nextLevelStars: level < 0 ? 0 : points + 1_000)
        result = result.withUpdatedStarRating(rating).withUpdatedPendingStarRating(nil)
    }
    if localState.enabled && localState.walletCardEnabled {
        // An empty address is deliberate: local display never creates a receiving wallet.
        result = result.withUpdatedWalletCard(WalletCard(address: "", balance: localState.tonBalance, stickers: []))
    }
    return result
}
