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
final class TelegramGroup: Peer {}
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
struct EngineMessageReplyQuote {
    let text: String; let offset: Int?
    init(text: String, offset: Int?) { self.text = text; self.offset = offset }
}
final class ReplyMessageAttribute: MessageAttribute {
    let messageId: MessageId; let threadMessageId: MessageId?; let quote: EngineMessageReplyQuote?
    let isQuote: Bool; let innerSubject: Int?
    init(messageId: MessageId, threadMessageId: MessageId? = nil, quote: EngineMessageReplyQuote? = nil, isQuote: Bool = false, innerSubject: Int? = nil) {
        self.messageId = messageId; self.threadMessageId = threadMessageId; self.quote = quote; self.isQuote = isQuote; self.innerSubject = innerSubject
    }
}
final class QuotedReplyMessageAttribute: MessageAttribute {}
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
    let id: MessageId, text: String, attributes: [MessageAttribute], media: [Media]
    var peers: [PeerId: Peer]
    let stableVersion: UInt32
    var protected = false, containsSecretMedia = false, incoming = true
    var richText: String? = nil, adAttribute: String? = nil, activeEphemeralReplacementMessage: String? = nil
    var groupingKey: Int64? = nil
    var associatedMessages: [MessageId: Message] = [:]
    init(id: Int32, text: String, attributes: [MessageAttribute] = [], media: [Media] = [], version: UInt32 = 1, peerValue: Int64 = 99) {
        let peer = PeerId(value: peerValue)
        self.id = MessageId(peerId: peer, id: id); self.text = text; self.attributes = attributes; self.media = media
        self.peers = [peer: TelegramChannel()]; self.stableVersion = version
    }
    var textEntitiesAttribute: TextEntitiesMessageAttribute? { attributes.first { $0 is TextEntitiesMessageAttribute } as? TextEntitiesMessageAttribute }
    func isCopyProtected() -> Bool { protected }
    func effectivelyIncoming(_ peer: PeerId) -> Bool { incoming }
    private func preserving(_ copy: Message) -> Message {
        copy.associatedMessages = associatedMessages; copy.peers = peers; copy.incoming = incoming; copy.groupingKey = groupingKey
        copy.protected = protected; copy.containsSecretMedia = containsSecretMedia; copy.richText = richText
        copy.adAttribute = adAttribute; copy.activeEphemeralReplacementMessage = activeEphemeralReplacementMessage; return copy
    }
    func withUpdatedText(_ text: String) -> Message { preserving(Message(id: id.id, text: text, attributes: attributes, media: media, version: stableVersion, peerValue: id.peerId.value)) }
    func withUpdatedAttributes(_ value: [MessageAttribute]) -> Message { preserving(Message(id: id.id, text: text, attributes: value, media: media, version: stableVersion, peerValue: id.peerId.value)) }
    func withUpdatedStableVersion(stableVersion: UInt32) -> Message { preserving(Message(id: id.id, text: text, attributes: attributes, media: media, version: stableVersion, peerValue: id.peerId.value)) }
    func withUpdatedMedia(_ value: [Media]) -> Message { preserving(Message(id: id.id, text: text, attributes: attributes, media: value, version: stableVersion, peerValue: id.peerId.value)) }
    func withUpdatedAssociatedMessages(_ value: [MessageId: Message]) -> Message { let copy = withUpdatedText(text); copy.associatedMessages = value; return copy }
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
    static func spin(_ condition: () -> Bool, timeout: Double = 10, line: UInt = #line) {
        let until = Date().addingTimeInterval(timeout)
        while !condition() && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(condition(), "timed out at check line \(line)")
    }
    static func settle(_ duration: Double = 0.25) { RunLoop.current.run(until: Date().addingTimeInterval(duration)) }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = AccountContext(root.path), account = context.account.peerId
        let session = RGAdFilterSession.get(context)
        // A completed pinned verdict must advance the pending one-second background refresh.
        let urgent = Message(id: 30001, text: "服务套餐与购买说明\n#ad")
        let notified = Box(false)
        let notificationStart = ProcessInfo.processInfo.systemUptime
        let urgentObserver = NotificationCenter.default.addObserver(forName: RGSimpleSettings.contentFiltersDidChangeNotification, object: nil, queue: .main) { _ in
            if session.shouldHide(urgent, accountPeerId: account, scope: .pinned) { notified.value = true }
        }
        session.prepare([urgent], accountPeerId: account, scope: .pinned)
        spin { notified.value }
        let urgentLatency = ProcessInfo.processInfo.systemUptime - notificationStart
        precondition(urgentLatency < 0.7, "pinned result waited for the background refresh")
        NotificationCenter.default.removeObserver(urgentObserver)
        print("Pinned notification latency: \(Int(urgentLatency * 1000)) ms")
        let replyTarget = Message(id: 31000, text: "商业套餐说明\n#ad", media: [TelegramMediaImage()])
        let replyHeader = ReplyMessageAttribute(messageId: replyTarget.id)
        let reply = Message(id: 31001, text: "这是对上条消息的正常讨论", attributes: [replyHeader, QuotedReplyMessageAttribute()], media: [TelegramMediaImage()])
        reply.incoming = false; reply.associatedMessages[replyTarget.id] = replyTarget
        let replyReady = Box(false)
        session.prepare([reply], accountPeerId: account) { replyReady.value = true }; spin { replyReady.value }
        let replyDisplay = session.display(reply, accountPeerId: account)
        precondition(session.display(replyTarget, accountPeerId: account).media.isEmpty, "a hidden ad exposed its image through a secondary display path")
        precondition(replyDisplay.text == reply.text && replyDisplay.media.count == 1 && !replyDisplay.incoming, "normal/outgoing reply was changed")
        precondition(!replyDisplay.attributes.contains { $0 is ReplyMessageAttribute || $0 is QuotedReplyMessageAttribute }, "hidden reply target leaked through its preview")
        precondition(rgAdOriginalMessage(replyDisplay) === reply && reply.attributes.contains { $0 is ReplyMessageAttribute }, "reply metadata was not recoverable")
        precondition(session.display(replyDisplay, accountPeerId: account).stableVersion == replyDisplay.stableVersion, "reply display projection was applied twice")
        RGSimpleSettings.shared.adFiltering = false
        precondition(session.display(replyDisplay, accountPeerId: account) === reply, "disabling the filter did not restore the reply")
        RGSimpleSettings.shared.adFiltering = nil
        let replyMixedText = "正文说明。\n0充值，免费体验，中奖可提现 → @promotion_user\n正常尾部"
        let replyMention = (replyMixedText as NSString).range(of: "@promotion_user")
        let replyMixed = Message(id: 31002, text: replyMixedText, attributes: [TextEntitiesMessageAttribute(entities: [MessageTextEntity(range: replyMention.location..<NSMaxRange(replyMention), type: .Mention)])])
        let adQuoteRange = (replyMixedText as NSString).range(of: "中奖可提现")
        let quoteReply = Message(id: 31003, text: "正常回复", attributes: [ReplyMessageAttribute(messageId: replyMixed.id, quote: EngineMessageReplyQuote(text: "中奖可提现", offset: adQuoteRange.location), isQuote: true)])
        quoteReply.associatedMessages[replyMixed.id] = replyMixed
        replyReady.value = false; session.prepare([quoteReply], accountPeerId: account) { replyReady.value = true }; spin { replyReady.value }
        let quoteDisplay = session.display(quoteReply, accountPeerId: account)
        precondition((quoteDisplay.attributes.first { $0 is ReplyMessageAttribute } as? ReplyMessageAttribute)?.quote == nil, "explicit quote brought the deleted ad back")
        precondition(quoteDisplay.associatedMessages[replyMixed.id]?.text.contains("正常尾部") == true && quoteDisplay.associatedMessages[replyMixed.id]?.text.contains("中奖") == false, "mixed reply did not retain only normal target content")
        let normalQuoteRange = (replyMixedText as NSString).range(of: "正常尾部")
        let normalQuote = Message(id: 31004, text: "正常回复", attributes: [ReplyMessageAttribute(messageId: replyMixed.id, quote: EngineMessageReplyQuote(text: "正常尾部", offset: normalQuoteRange.location), isQuote: true)])
        normalQuote.associatedMessages[replyMixed.id] = replyMixed
        precondition((session.display(normalQuote, accountPeerId: account).attributes.first { $0 is ReplyMessageAttribute } as? ReplyMessageAttribute)?.quote?.text == "正常尾部", "normal explicit quotation was discarded")
        let unloadedReply = Message(id: 31005, text: "正常回复", attributes: [replyHeader])
        precondition(session.display(unloadedReply, accountPeerId: account) === unloadedReply, "unloaded reply was guessed to be advertising")
        let editedTarget = Message(id: replyTarget.id.id, text: "已修改为正常说明", version: 2)
        let editedReply = Message(id: reply.id.id, text: reply.text, attributes: [replyHeader], version: 2)
        editedReply.associatedMessages[editedTarget.id] = editedTarget
        precondition(session.display(editedReply, accountPeerId: account) === editedReply, "stale target verdict hid an edited reply")
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
            var sample = try rgAdSampleDraft(message, store: store)
            sample.spans = []; sample.buttonLabels = sample.buttonLabels.mapValues { _ in .normal }; sample.mediaLabel = .normal
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
        spin { records.value }
        let largeReady = Box(false)
        session.prepare(large, accountPeerId: account) { largeReady.value = true }
        spin { rgAdMessageWasFiltered(display(large.last!)) }
        // Current-chat results now notify before the rest of the batch finishes. A queue
        // barrier does not drain scheduled inference; wait for the actual completion.
        spin({ largeReady.value }, timeout: 30)
        let drained = Box(false)
        session.perform({ _ in true }) { _ in drained.value = true }
        spin { drained.value }; settle(1.1)
        let loopCount = loops.value; session.prepare(large, accountPeerId: account); settle(1.1)
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
        let cancelledMessage = Message(id: 21001, text: "商业套餐说明\n#ad")
        let cancelledScope = RGAdFilterSession.Scope.chatList(UUID())
        let cancelledCompletion = Box(false)
        let cancelled = session.prepare([cancelledMessage], accountPeerId: account, scope: cancelledScope) { cancelledCompletion.value = true }
        cancelled.cancel()
        let barrier = Box(false)
        session.perform({ _ in true }) { _ in barrier.value = true }; spin { barrier.value }; settle()
        precondition(!cancelledCompletion.value && !session.isPrepared(cancelledMessage, accountPeerId: account, scope: cancelledScope), "disposed preview still classified its obsolete message")
        session.prepare([cancelledMessage], accountPeerId: account, scope: cancelledScope)
        spin { session.shouldHide(cancelledMessage, accountPeerId: account, scope: cancelledScope) }
        // A server edit must invalidate the identity memo, even before the new batch finishes.
        let edited = Message(id: 21001, text: "今天讨论开源去广告规则", version: 2)
        precondition(!session.shouldHide(edited, accountPeerId: account, scope: cancelledScope), "old verdict leaked onto an edited message")
        precondition(session.display(edited, accountPeerId: account, scope: cancelledScope) === edited)
        let editedReady = Box(false)
        session.prepare([edited], accountPeerId: account, scope: cancelledScope) { editedReady.value = true }
        spin { editedReady.value }
        precondition(!session.shouldHide(edited, accountPeerId: account, scope: cancelledScope))
        // This isolated bridge has no bundled model. Failure must not become a cached keep.
        precondition(!session.isPrepared(edited, accountPeerId: account, scope: cancelledScope), "unavailable classifier was cached as normal")
        session.release(scope: cancelledScope)
        let entered = DispatchSemaphore(value: 0), releaseQueue = DispatchSemaphore(value: 0)
        session.perform({ _ in entered.signal(); _ = releaseQueue.wait(timeout: .now() + 3) }) { _ in }
        precondition(entered.wait(timeout: .now() + 3) == .success)
        var retiredWindow: RGAdFilterWorkScope? = RGAdFilterWorkScope(session: session, scope: .historyView(UUID()))
        let activeWindow = RGAdFilterWorkScope(session: session, scope: .historyView(UUID()))
        let retiredMessage = Message(id: 22001, text: "已离开页面的商业卡片\n#ad")
        let activeMessage = Message(id: 22002, text: "仍在显示的商业卡片\n#ad")
        retiredWindow?.prepare([retiredMessage], accountPeerId: account)
        activeWindow.prepare([activeMessage], accountPeerId: account)
        retiredWindow = nil; releaseQueue.signal()
        spin { session.shouldHide(activeMessage, accountPeerId: account, scope: activeWindow.scope) }
        precondition(!session.isPrepared(retiredMessage, accountPeerId: account), "retired history window kept running")
        print("Ad bridge checks passed: original restoration, display versions, entities, buttons, media, translation, privacy eligibility, reveal controls, corrections and bounded-cache refresh stability.")
    }
}
'''
def run():
    with tempfile.TemporaryDirectory(prefix='regram-ad-bridge-') as directory:
        work = Path(directory)
        swift = work / 'BridgeChecks.swift'
        swift.write_text(adapters + '\n' + bridge + '\n' + tests)
        binary = work / 'checks'
        subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-warnings-as-errors',*map(str, sorted((root/'Reza/RGAdFilter/Sources').glob('*.swift'))),str(swift),'-o',str(binary)],check=True,cwd=root)
        subprocess.run([str(binary)],check=True,timeout=60)

if __name__ == '__main__':
    run()
