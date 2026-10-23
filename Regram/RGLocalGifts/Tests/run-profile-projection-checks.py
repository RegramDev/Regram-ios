#!/usr/bin/env python3
"""Exercise the production owner-only rating/card projection with immutable data adapters."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'Regram/RGLocalGifts/Sources/LocalRating.swift').read_text()
source = '\n'.join(line for line in source.splitlines() if not line.startswith('import '))
source = source.replace('public func', 'func')
native = (root / 'submodules/TelegramCore/Sources/SyncCore/SyncCore_CachedUserData.swift').read_text()
rating = native.split('public final class TelegramStarRating:', 1)[1].split('public final class TelegramStarPendingRating:', 1)[0]
rating = 'public final class TelegramStarRating:' + rating
fixture = '''
import Foundation
struct EnginePeer { typealias Id = Int64 }
struct Account { let peerId: Int64 }
struct AccountContext { let account: Account }
protocol EngineCachedPeerData: AnyObject {}
struct WalletCard: Equatable {
    let address: String
    let balance: Int64
    let stickers: [String]
}
final class CachedUserData: EngineCachedPeerData {
    let starRating: TelegramStarRating?
    let pendingStarRating: String?
    let walletCard: WalletCard?
    let unrelated: String
    init(starRating: TelegramStarRating? = nil, pendingStarRating: String? = nil, walletCard: WalletCard? = nil, unrelated: String = "preserved") {
        self.starRating = starRating; self.pendingStarRating = pendingStarRating
        self.walletCard = walletCard; self.unrelated = unrelated
    }
    func withUpdatedStarRating(_ rating: TelegramStarRating?) -> CachedUserData {
        CachedUserData(starRating: rating, pendingStarRating: pendingStarRating, walletCard: walletCard, unrelated: unrelated)
    }
    func withUpdatedPendingStarRating(_ pending: String?) -> CachedUserData {
        CachedUserData(starRating: starRating, pendingStarRating: pending, walletCard: walletCard, unrelated: unrelated)
    }
    func withUpdatedWalletCard(_ card: WalletCard?) -> CachedUserData {
        CachedUserData(starRating: starRating, pendingStarRating: pendingStarRating, walletCard: card, unrelated: unrelated)
    }
}
RATING
PROJECTION
@main enum Tests {
    static func main() {
        let owner = AccountContext(account: Account(peerId: 1))
        let remoteRating = TelegramStarRating(level: 7, currentLevelStars: 10, stars: 12, nextLevelStars: 20)
        let remoteCard = WalletCard(address: "real-fixture", balance: 123, stickers: ["real-sticker"])
        let remote = CachedUserData(starRating: remoteRating, pendingStarRating: "pending", walletCard: remoteCard)
        var local = RGLocalGiftsState()
        func project(_ id: Int64 = 1) -> CachedUserData {
            rgLocalProfileCachedData(context: owner, peerId: id, cachedData: remote, localState: local) as! CachedUserData
        }
        precondition(project() === remote)
        precondition(rgLocalProfileCachedData(context: owner, peerId: 1, cachedData: nil, localState: local) == nil)
        local.ratingEnabled = true
        for level: Int32 in [-999, -1, 0, 88, 999] {
            local.ratingLevel = level
            let result = project()
            precondition(result.starRating?.level == level && result.pendingStarRating == nil)
            precondition(result.starRating!.nextLevelStars! > result.starRating!.stars)
            precondition(result.walletCard == remoteCard && result.unrelated == "preserved")
            precondition(project(2) === remote, "Never project local customization onto another user")
        }
        local.walletCardEnabled = true
        precondition(project().walletCard == remoteCard, "Gift mode off retains the real wallet")
        local.enabled = true
        for amount: Int64 in [0, 1, 4_940_030_000_000, RGLocalGiftsStore.maximumBalance] {
            local.tonBalance = amount
            let result = project()
            precondition(result.walletCard?.balance == amount && result.walletCard?.address == "")
            precondition(result.walletCard!.stickers.isEmpty, "Local records must not be represented as on-chain NFTs")
            precondition(result.starRating?.level == local.ratingLevel)
        }
        local.ratingEnabled = false
        precondition(project().starRating == remoteRating && project().pendingStarRating == "pending")
        local.walletCardEnabled = false
        precondition(project() === remote, "Turning off both overlays restores the original snapshot")
        precondition(remote.walletCard == remoteCard && remote.starRating == remoteRating && remote.pendingStarRating == "pending")
        print("Owner-only native rating/TON card projection: signed levels, zero/large balances, independent switches, restoration and immutable remote snapshots passed")
    }
}
'''.replace('RATING', rating).replace('PROJECTION', source)
with tempfile.TemporaryDirectory(prefix='regram-profile-projection-') as directory:
    work = Path(directory)
    swift = work / 'ProfileProjectionTests.swift'
    swift.write_text(fixture)
    binary = work / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors',
                    str(root / 'Regram/RGSimpleSettings/Sources/LocalGifts.swift'), str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
