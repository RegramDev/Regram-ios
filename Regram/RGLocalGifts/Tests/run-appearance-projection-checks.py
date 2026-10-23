#!/usr/bin/env python3
"""Exercise the production appearance projection with native color/status codecs and immutable peers."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'Regram/RGLocalGifts/Sources/LocalGiftAppearance.swift').read_text()
native = (root / 'submodules/TelegramCore/Sources/SyncCore/SyncCore_CachedUserData.swift').read_text()


def block(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


types = '\n'.join(block(native, name) for name in [
    'public enum PeerNameColor:', 'public struct PeerCollectibleColor:',
    'public enum PeerColor:', 'public struct PeerEmojiStatus:'
])
# FlatBuffers persistence is independent of this JSON-backed display projection.
for marker in ['public init(flatBuffersObject:', 'public func encodeToFlatBuffers(']:
    while marker in types:
        types = types.replace(block(types, marker), '', 1)
projection = '\n'.join(block(source, name) for name in [
    'private struct LocalAppearance:', 'public func rgLocalAppearancePeer(',
    'public func rgLocalGiftEmojiStatus(', 'public func rgLocalUniqueGifts('
]).replace('public func', 'func')
projection += '\n' + block((root / 'Regram/RGLocalGifts/Sources/LocalGifts.swift').read_text(), 'public func rgLocalGiftUpgradePrice(').replace('public func', 'func')
fixture = r'''
import Foundation
TYPES
struct Account { let peerId: Int64 }
struct AccountContext { let account: Account }
enum EnginePeer {
    case user(User), channel(Int64)
    var id: Int64 { switch self { case let .user(user): return user.id; case let .channel(id): return id } }
}
struct User: Equatable {
    let id: Int64
    var nameColor: PeerColor?
    var backgroundEmojiId: Int64?
    var profileColor: PeerNameColor?
    var profileBackgroundEmojiId: Int64?
    var emojiStatus: PeerEmojiStatus?
    func withUpdatedNameColor(_ value: PeerColor?) -> Self { var copy = self; copy.nameColor = value; return copy }
    func withUpdatedBackgroundEmojiId(_ value: Int64?) -> Self { var copy = self; copy.backgroundEmojiId = value; return copy }
    func withUpdatedProfileColor(_ value: PeerNameColor?) -> Self { var copy = self; copy.profileColor = value; return copy }
    func withUpdatedProfileBackgroundEmojiId(_ value: Int64?) -> Self { var copy = self; copy.profileBackgroundEmojiId = value; return copy }
    func withUpdatedEmojiStatus(_ value: PeerEmojiStatus?) -> Self { var copy = self; copy.emojiStatus = value; return copy }
}
struct File { let fileId: FileId; struct FileId { let id: Int64 } }
enum StarGift {
    case unique(UniqueGift)
    struct Gift { let upgradeStars: Int64? }
    struct UniqueGift {
        enum Attribute { case model(String, File, Int, Int), pattern(String, File, Int), backdrop(String, Int, Int32, Int32, Int32, Int32, Int) }
        let id: Int64
        let title: String
        let attributes: [Attribute]
        let peerColor: PeerCollectibleColor?
    }
}
struct StarGiftUpgradePreview {
    struct Price { let stars: Int64; let date: Int32 }
    let prices: [Price]
    let nextPrices: [Price]
}
struct Purchase { let id: UUID; let gift: StarGift }
struct RGLocalGiftsState {
    var enabled = false
    var appearance: Data?
    var profileGiftId: UUID?
    var nameGiftId: UUID?
    var purchases: [Purchase] = []
}
final class RGLocalGiftsStore {
    static let shared = RGLocalGiftsStore()
    var current = RGLocalGiftsState()
    var reads = 0
    func state(account: String) -> RGLocalGiftsState { precondition(account == "fixture"); reads += 1; return current }
}
func rgLocalGiftsAccount(_ context: AccountContext) -> String { "fixture" }
func rgLocalGift(context: AccountContext, purchase: Purchase) -> StarGift? { purchase.gift }
PROJECTION
@main enum Tests {
    static func main() throws {
        let context = AccountContext(account: Account(peerId: 1))
        let original = User(id: 1, nameColor: .preset(.cyan), backgroundEmojiId: 12, profileColor: .blue, profileBackgroundEmojiId: 13, emojiStatus: PeerEmojiStatus(content: .emoji(fileId: 77), expirationDate: nil))
        var state = RGLocalGiftsState()
        func project(_ state: RGLocalGiftsState) -> User {
            guard case let .user(result) = rgLocalAppearancePeer(context: context, peer: .user(original), localState: state) else { fatalError() }
            return result
        }
        precondition(project(state) == original)
        state.enabled = true
        state.appearance = Data("invalid".utf8)
        precondition(project(state) == original)
        let color = PeerCollectibleColor(collectibleId: -8, giftEmojiFileId: -80, backgroundEmojiId: -81, accentColor: 0xF08080, colors: [0x123456, 0xABCDEF], darkAccentColor: 0x102030, darkColors: [0x456789])
        let gift = StarGift.UniqueGift(id: -8, title: "Fixture Gift", attributes: [.model("model", File(fileId: .init(id: -80)), 0, 0), .pattern("pattern", File(fileId: .init(id: -81)), 0), .backdrop("backdrop", 0, 1, 2, 3, 4, 0)], peerColor: color)
        let purchase = Purchase(id: UUID(), gift: .unique(gift))
        state.purchases = [purchase]
        state.nameGiftId = purchase.id
        state.profileGiftId = purchase.id
        state.appearance = try JSONEncoder().encode(LocalAppearance(namePreset: 0, nameCollectible: nil, profileColor: 3, replyFileId: -81, backgroundFileId: -999, emojiStatus: original.emojiStatus))
        let result = project(state)
        precondition(result.nameColor == .collectible(color), "Quotes must get the collectible's complete light/dark palette")
        precondition(result.backgroundEmojiId == -81 && result.profileBackgroundEmojiId == nil, "Retain available patterns and discard missing local files")
        precondition(result.emojiStatus?.content == .starGift(id: -8, fileId: -80, title: "Fixture Gift", slug: "", patternFileId: -81, innerColor: 1, outerColor: 2, patternColor: 3, textColor: 4), "The top title and profile must use the same rebound gift model")
        precondition(original.nameColor == .preset(.cyan) && original.emojiStatus?.content == .emoji(fileId: 77), "Do not mutate remote account data")
        RGLocalGiftsStore.shared.current = state
        guard case let .user(current) = rgLocalAppearancePeer(context: context, peer: .user(original)) else { fatalError() }
        precondition(current == result, "Synchronous quote rendering and reactive header rendering use the same projection")
        let reads = RGLocalGiftsStore.shared.reads
        let other = User(id: 2, nameColor: .preset(.pink), emojiStatus: nil)
        guard case let .user(otherResult) = rgLocalAppearancePeer(context: context, peer: .user(other)) else { fatalError() }
        precondition(otherResult == other && RGLocalGiftsStore.shared.reads == reads, "Other accounts never read or inherit this account's local appearance")
        guard case .channel(1) = rgLocalAppearancePeer(context: context, peer: .channel(1), localState: state) else { fatalError() }
        state.enabled = false
        precondition(project(state) == original, "Disabling local gifts restores the server color and status")
        state.enabled = true
        state.nameGiftId = nil
        state.profileGiftId = nil
        state.purchases = []
        state.appearance = try JSONEncoder().encode(LocalAppearance(namePreset: 6, nameCollectible: nil, profileColor: nil, replyFileId: nil, backgroundFileId: nil, emojiStatus: nil))
        precondition(project(state).nameColor == .preset(.pink) && project(state).emojiStatus == nil, "A changed preset or cleared status must replace the previous gift")
        let preview = StarGiftUpgradePreview(prices: [.init(stars: 100, date: 10)], nextPrices: [.init(stars: 50, date: 20)])
        let limited = StarGift.Gift(upgradeStars: 75)
        precondition(rgLocalGiftUpgradePrice(gift: limited, preview: preview, at: 5) == 75)
        precondition(rgLocalGiftUpgradePrice(gift: limited, preview: preview, at: 15) == 100)
        precondition(rgLocalGiftUpgradePrice(gift: limited, preview: preview, at: 20) == 50, "Charge the effective quote, never a future lower price")
        precondition(rgLocalGiftUpgradePrice(gift: .init(upgradeStars: nil), preview: .init(prices: [], nextPrices: []), at: 20) == nil)
        print("Production local appearance projection passed: native codecs, collectible palettes, gift model rebinding, synchronous/reactive consistency, account isolation, clearing and disable restoration")
    }
}
'''.replace('TYPES', types).replace('PROJECTION', projection)
with tempfile.TemporaryDirectory(prefix='regram-appearance-projection-') as temporary:
    work = Path(temporary)
    swift = work / 'Appearance.swift'
    swift.write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors', str(swift), '-o', str(work / 'tests')], check=True)
    subprocess.run([str(work / 'tests')], check=True)
