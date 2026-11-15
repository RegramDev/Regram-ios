#!/usr/bin/env python3
"""Run the production AccountContext ad bridge with isolated message/UI-boundary adapters."""
from pathlib import Path
import subprocess, tempfile

root = Path(__file__).resolve().parents[3]
bridge = (root / 'submodules/AccountContext/Sources/RGAdFiltering.swift').read_text()
bridge = '\n'.join(line for line in bridge.splitlines() if not line.startswith('import ')).replace('public ', '')
adapters = r'''
import Foundation
struct PeerId: Hashable { let value: Int64; var namespace: Int32 { 0 }; func toInt64() -> Int64 { value } }
struct MessageId: Hashable { let peerId: PeerId; let namespace: Int32 = 0; let id: Int32 }
enum Namespaces { enum Message { static let Cloud: Int32 = 0 }; enum Peer { static let SecretChat: Int32 = 1 } }
class Peer {}
final class TelegramChannel: Peer { enum Info { case broadcast, group }; let info = Info.broadcast }
struct PostboxDecoder {}
struct PostboxEncoder {}
protocol MessageAttribute: AnyObject {}
enum EntityType { case TextUrl(url: String), Url, Mention, TextMention, Code, Pre, BlockQuote, CustomEmoji(Int?, Int64), Bold }
struct MessageTextEntity { let range: Range<Int>; let type: EntityType }
final class TextEntitiesMessageAttribute: MessageAttribute {
    let entities: [MessageTextEntity]; init(entities: [MessageTextEntity]) { self.entities = entities }
}
enum ButtonAction { case url(String), urlAuth(String, Int32), openWebView(String, Bool), callback }
struct ReplyButton { let title: String; let action: ButtonAction }
struct ReplyMarkupRow { let buttons: [ReplyButton] }
struct MarkupFlags: OptionSet { let rawValue: Int; static let inline = MarkupFlags(rawValue: 1) }
final class ReplyMarkupMessageAttribute: MessageAttribute {
    let rows: [ReplyMarkupRow]; let flags: MarkupFlags; let placeholder: String?
    init(rows: [ReplyMarkupRow], flags: MarkupFlags, placeholder: String?) { self.rows = rows; self.flags = flags; self.placeholder = placeholder }
}
final class TranslationMessageAttribute: MessageAttribute {}
class Media { let id: Int64? = 1 }
final class TelegramMediaFile: Media { let isVideo = false; let isVoice = false }
final class TelegramMediaImage: Media {}
final class TelegramMediaWebpage: Media {
    struct Content { let url: String }
    enum State { case Loaded(Content), pending }
    let content: State
    init(_ url: String) { content = .Loaded(Content(url: url)) }
}
final class Message {
    let id: MessageId, text: String, attributes: [MessageAttribute], media: [Media], peers: [PeerId: Peer]
    let stableVersion: UInt32
    var protected = false, containsSecretMedia = false, incoming = true
    var richText: String? = nil, adAttribute: String? = nil, activeEphemeralReplacementMessage: String? = nil
    init(id: Int32, text: String, attributes: [MessageAttribute] = [], media: [Media] = [], version: UInt32 = 1) {
        let peer = PeerId(value: 99)
        self.id = MessageId(peerId: peer, id: id); self.text = text; self.attributes = attributes; self.media = media
        self.peers = [peer: TelegramChannel()]; self.stableVersion = version
    }
    var textEntitiesAttribute: TextEntitiesMessageAttribute? { attributes.first { $0 is TextEntitiesMessageAttribute } as? TextEntitiesMessageAttribute }
    func isCopyProtected() -> Bool { protected }
    func effectivelyIncoming(_ peer: PeerId) -> Bool { incoming }
    func withUpdatedText(_ text: String) -> Message { Message(id: id.id, text: text, attributes: attributes, media: media, version: stableVersion) }
    func withUpdatedAttributes(_ value: [MessageAttribute]) -> Message { Message(id: id.id, text: text, attributes: value, media: media, version: stableVersion) }
    func withUpdatedStableVersion(stableVersion: UInt32) -> Message { Message(id: id.id, text: text, attributes: attributes, media: media, version: stableVersion) }
    func withUpdatedMedia(_ value: [Media]) -> Message { Message(id: id.id, text: text, attributes: attributes, media: value, version: stableVersion) }
}
final class AccountContext {
    struct Account { let basePath: String; let peerId = PeerId(value: 1) }
    let account: Account
    init(_ path: String) { account = Account(basePath: path) }
}
final class RGSimpleSettings {
    static let shared = RGSimpleSettings(), contentFiltersDidChangeNotification = Notification.Name("AdBridgeChecks.changed")
    var messageFilterDisabledPeerIds = Set<Int64>(), revealed = Set<Int64>()
    struct ChatPreferences { var adFiltering: Bool? }
    var adFiltering: Bool? = nil
    func chatPreferences(accountId: Int64, peerId: Int64) -> ChatPreferences { ChatPreferences(adFiltering: adFiltering) }
    func temporarilyVisiblePeerIds(accountId: Int64) -> Set<Int64> { revealed }
}
'''
tests = r'''
final class Box<T> { var value: T; init(_ value: T) { self.value = value } }
@main enum Checks {
    static func spin(_ condition: () -> Bool, timeout: Double = 5) {
        let until = Date().addingTimeInterval(timeout)
        while !condition() && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(condition(), "timed out")
    }
    static func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.15)) }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = AccountContext(root.path), account = context.account.peerId
        let session = RGAdFilterSession.get(context)
        let text = "剧名：春日旅程\n简介：正常正文。\n0充值，免费体验，中奖可提现 → @promotion_user"
        let range = (text as NSString).range(of: "@promotion_user")
        let entities = TextEntitiesMessageAttribute(entities: [MessageTextEntity(range: range.location..<NSMaxRange(range), type: .Mention), MessageTextEntity(range: 0..<text.utf16.count, type: .Bold)])
        let markup = ReplyMarkupMessageAttribute(rows: [ReplyMarkupRow(buttons: [ReplyButton(title: "电影搜索", action: .url("https://t.me/search_helper")), ReplyButton(title: "推广", action: .url("https://t.me/promotion_user"))])], flags: .inline, placeholder: nil)
        let message = Message(id: 1, text: text, attributes: [entities, markup, TranslationMessageAttribute()], media: [TelegramMediaImage()])
        func display(_ value: Message = message) -> Message { session.display(value, accountPeerId: account) }
        let refreshes = Box(0)
        let observer = NotificationCenter.default.addObserver(forName: RGSimpleSettings.contentFiltersDidChangeNotification, object: nil, queue: .main) { _ in refreshes.value += 1; session.prepare([message], accountPeerId: account) }
        defer { NotificationCenter.default.removeObserver(observer) }
        session.prepare([message], accountPeerId: account)
        spin { rgAdMessageWasFiltered(display()) }
        let filtered = display()
        precondition(filtered.text.hasPrefix("剧名：春日旅程\n简介：正常正文。\n") && !filtered.text.contains("中奖"))
        precondition(rgAdOriginalMessage(filtered) === message && message.text == text)
        precondition(filtered.stableVersion != message.stableVersion && display().stableVersion == filtered.stableVersion)
        precondition(filtered.media.count == 1 && !filtered.attributes.contains { $0 is TranslationMessageAttribute })
        precondition((filtered.attributes.first { $0 is ReplyMarkupMessageAttribute } as? ReplyMarkupMessageAttribute)?.rows[0].buttons.count == 1)
        precondition(filtered.textEntitiesAttribute!.entities.allSatisfy { $0.range.upperBound <= filtered.text.utf16.count })
        precondition(rgAdOriginalRange(filtered, range: NSRange(location: 0, length: 2)) == NSRange(location: 0, length: 2))
        precondition(filtered.text == "剧名：春日旅程\n简介：正常正文。\n", "cleaned text must not add a notice")
        settle(); let settled = refreshes.value; session.prepare([message], accountPeerId: account); settle()
        precondition(refreshes.value == settled, "prepared batch keeps notifying itself")
        RGSimpleSettings.shared.revealed = [99]; precondition(display() === message); RGSimpleSettings.shared.revealed = []
        RGSimpleSettings.shared.messageFilterDisabledPeerIds = [99]
        precondition(rgAdMessageWasFiltered(display()), "legacy keyword opt-out must not disable segment filtering")
        RGSimpleSettings.shared.adFiltering = false; precondition(display() === message)
        RGSimpleSettings.shared.adFiltering = nil; precondition(rgAdMessageWasFiltered(display()))
        RGSimpleSettings.shared.messageFilterDisabledPeerIds = []
        message.protected = true; precondition(display() === message); message.protected = false
        message.richText = "rich"; precondition(display() === message); message.richText = nil
        let done = Box(false)
        session.perform(changes: true, { store in
            var sample = try store.draft(input: rgAdInput(message), messageKey: "99:1", mediaKinds: ["image"], mediaIdentity: "fixture")
            sample.buttonLabels = sample.buttonLabels.mapValues { _ in .normal }; sample.mediaLabel = .normal
            try store.save(sample)
        }) { result in try! result.get(); done.value = true }
        spin { done.value }; spin { display() === message }
        session.prepare([message], accountPeerId: account); settle(); precondition(display() === message, "normal correction failed")
        NotificationCenter.default.removeObserver(observer)
        let large = (2...601).map { Message(id: Int32($0), text: text, attributes: [entities, markup]) }
        let loops = Box(0)
        let repeatObserver = NotificationCenter.default.addObserver(forName: RGSimpleSettings.contentFiltersDidChangeNotification, object: nil, queue: .main) { _ in loops.value += 1; session.prepare(large, accountPeerId: account) }
        defer { NotificationCenter.default.removeObserver(repeatObserver) }
        // Normal correction above matches the same body; use a different prefix to exercise ads.
        let records = Box(false)
        session.perform(changes: true, { store in for sample in try store.load() { try store.remove(sample) } }) { _ in records.value = true }
        spin { records.value }; session.prepare(large, accountPeerId: account)
        spin { rgAdMessageWasFiltered(display(large.last!)) }
        let drained = Box(false)
        session.perform({ _ in true }) { _ in drained.value = true }
        spin { drained.value }; settle()
        let loopCount = loops.value; session.prepare(large, accountPeerId: account); settle()
        precondition(loops.value == loopCount, "large window caused refresh loop")
        NotificationCenter.default.removeObserver(repeatObserver)
        let pinned = Message(id: 9001, text: text, attributes: [entities, markup])
        session.prepare([pinned], accountPeerId: account, scope: .pinned)
        spin { rgAdMessageWasFiltered(display(pinned)) }
        let otherWindow = large.map { Message(id: $0.id.id + 1000, text: text, attributes: [entities, markup]) }
        session.prepare(otherWindow, accountPeerId: account)
        drained.value = false; session.perform({ _ in true }) { _ in drained.value = true }; spin { drained.value }
        precondition(rgAdMessageWasFiltered(display(pinned)), "scrolling evicted a pinned ad projection")
        let adLine = "0充值，免费体验，中奖可提现 → @promotion_user\n"
        let mixedText = "开头\n" + adLine + "正常尾部👋"
        let mention = (mixedText as NSString).range(of: "@promotion_user")
        let middle = Message(id: 700, text: mixedText, attributes: [TextEntitiesMessageAttribute(entities: [MessageTextEntity(range: mention.location..<NSMaxRange(mention), type: .Mention)])])
        session.prepare([middle], accountPeerId: account)
        spin { rgAdMessageWasFiltered(display(middle)) }
        let cleaned = display(middle)
        let selected = (cleaned.text as NSString).range(of: "正常尾部👋")
        precondition(rgAdOriginalRange(cleaned, range: selected) == (mixedText as NSString).range(of: "正常尾部👋"), "quote offset was not restored")
        precondition(rgAdOriginalRange(cleaned, range: NSRange(location: 0, length: NSMaxRange(selected))) == nil, "discontinuous text must not become a forged quote")
        print("Ad bridge checks passed: original restoration, display versions, entities, buttons, media, translation, privacy eligibility, reveal controls, corrections and bounded-cache refresh stability.")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-ad-bridge-') as directory:
    work = Path(directory)
    swift = work / 'BridgeChecks.swift'
    swift.write_text(adapters + '\n' + bridge + '\n' + tests)
    binary = work / 'checks'
    subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-warnings-as-errors',*map(str, sorted((root/'Regram/RGAdFilter/Sources').glob('*.swift'))),str(swift),'-o',str(binary)],check=True,cwd=root)
    subprocess.run([str(binary)],check=True,timeout=30)
