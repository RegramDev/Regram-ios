#!/usr/bin/env python3
"""Exercise production rich projections and their filter/history/summary/repeat consumers offline."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
def read(path): return (root / path).read_text()
def between(path, start, end):
    source = read(path)
    return source[source.index(start):source.index(end, source.index(start))]
def enum(path, start):
    return between(path, start, '    public init(decoder:').replace(': PostboxCoding, Equatable', ': Equatable') + '}\n'

for consumer in ['submodules/AccountContext/Sources/RGContentFilter.swift', 'submodules/TelegramUI/Sources/ChatHistoryListNode.swift', 'submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift']:
    for line in read(consumer).splitlines():
        if 'text: message.' in line and ('shouldHide(' in line or 'RGContentFilterCandidate(' in line):
            assert 'text: message.rgTextContent' in line, consumer

models = r'''
import Foundation
public struct MediaId: Hashable { let namespace: Int32; let id: Int64 }
public struct PixelDimensions: Equatable { let width: Int32; let height: Int32 }
public enum MessageTextEntityType { case Spoiler; public enum DateTimeFormat: Int32 { case date } }
public struct TelegramChannel: Equatable {}
public struct InstantPageButton: Equatable { let text: RichText }
public enum InstantPageButtonRowAlignment { case left }
public struct InstantPageCaption: Equatable { let text: RichText; let credit: RichText }
public struct InstantPageTableCell: Equatable { let text: RichText? }
public struct InstantPageTableRow: Equatable { let cells: [InstantPageTableCell] }
public struct InstantPageRelatedArticle: Equatable {}
public struct InstantPage: Equatable { let blocks: [InstantPageBlock] }
public protocol Media {}
public protocol MessageAttribute {}
public final class RichTextMessageAttribute: MessageAttribute, Equatable {
 let instantPage: InstantPage; var fullInstantPage: InstantPage?
 init(instantPage: InstantPage, fullInstantPage: InstantPage? = nil) { self.instantPage = instantPage; self.fullInstantPage = fullInstantPage }
 public static func ==(a: RichTextMessageAttribute, b: RichTextMessageAttribute) -> Bool { a.instantPage == b.instantPage && a.fullInstantPage == b.fullInstantPage }
}
public struct MessageTextEntity: Equatable { let text: String; var range: Range<Int> { 0..<text.utf16.count }; var type: MessageTextEntityType { .Spoiler } }
public final class TextEntitiesMessageAttribute: MessageAttribute { let entities: [MessageTextEntity]; init(_ value: [MessageTextEntity]) { entities = value } }
public final class EditedMessageAttribute: MessageAttribute { let date: Int32; init(_ value: Int32) { date = value } }
public final class MediaSpoilerMessageAttribute: MessageAttribute {}
public final class RGRevokedMessageAttribute: MessageAttribute {}
public final class TelegramMediaWebpage: Media {}
public final class TelegramMediaImage: Media { let imageId: Int64; init(_ id: Int64 = 1) { imageId = id } }
public final class TelegramMediaFile: Media {}
public final class TelegramMediaMap: Media {}
public final class TelegramMediaContact: Media {}
public typealias EngineRawMedia = Media
public struct EnginePeer { public struct Id: Hashable { let value: Int64; let namespace: Int32; public func toInt64() -> Int64 { value } }; let id: Id }
public struct MessageId: Hashable { let peerId: EnginePeer.Id; let namespace: Int32; let id: Int32 }
public struct Message {
 let id: MessageId; let stableVersion: UInt32; let text: String; let author: EnginePeer?; let attributes: [MessageAttribute]; let media: [Media]; let timestamp: Int32 = 10
 var textEntitiesAttribute: TextEntitiesMessageAttribute? { attributes.first { $0 is TextEntitiesMessageAttribute } as? TextEntitiesMessageAttribute }
 var associatedMedia: [MediaId: Media] { [:] }
 var index: Int32 { id.id }; var containsSecretMedia: Bool { false }; func isCopyProtected() -> Bool { false }
 func effectivelyIncoming(_ account: EnginePeer.Id) -> Bool { author?.id != account }
}
public typealias EngineRawMessage = Message
public struct EngineMessage {
 public typealias Id = MessageId
 public typealias Attribute = MessageAttribute
 let raw: Message
 var id: Id { raw.id }; var stableVersion: UInt32 { raw.stableVersion }; var text: String { raw.text }; var attributes: [MessageAttribute] { raw.attributes }; var author: EnginePeer? { raw.author }
 func effectivelyIncoming(_ account: EnginePeer.Id) -> Bool { raw.effectivelyIncoming(account) }
}
public struct MediaBox {}
public struct RGEditHistoryEntry { let text: String; let entities: [MessageTextEntity]; let date: Int32; let image: TelegramMediaImage?; let imageData: Data?; let imageHasSpoiler: Bool; let richText: RichTextMessageAttribute? }
public final class RGEditHistoryMessageAttribute: MessageAttribute { let entries: [RGEditHistoryEntry]; init(entries: [RGEditHistoryEntry]) { self.entries = entries }; func withAppendedEntry(_ e: RGEditHistoryEntry) -> RGEditHistoryMessageAttribute { .init(entries: entries + [e]) } }
public class AutoremoveTimeoutMessageAttribute: MessageAttribute { let timeout = 1; let countdownBeginTime: Int32? = nil; let isLocallyPreserved = false }
public class AutoclearTimeoutMessageAttribute: MessageAttribute { let timeout = 1; let countdownBeginTime: Int32? = nil; let isLocallyPreserved = false }
func rgEditHistoryCachedImageData(image: TelegramMediaImage, mediaBox: MediaBox) -> Data? { nil }
public enum Namespaces { public enum Message { static let Cloud: Int32 = 0 }; public enum Peer { static let SecretChat: Int32 = 1 } }
final class RGSimpleSettings {
 static let shared = RGSimpleSettings(); var messageFilterRules: [RGMessageFilterRule] = []; var blockedPeerIds: Set<Int64> = []; var messageFilterDisabledPeerIds: Set<Int64> = []; var contentFilterGeneration = 0; var saveEditHistory = true
 func temporarilyVisiblePeerIds(accountId: Int64) -> Set<Int64> { [] }
}
struct Row { let message: Message? }
extension String { func i18n(_ lang: String) -> String { self } }
public struct EngineMedia { public typealias Id = MediaId }
struct MessageReference { init(_ message: Message) {} }
struct AnyMediaReference { static func message(message: MessageReference, media: Media) -> Self { Self() } }
final class AccountContext { let account = 1 }
struct EnqueueMessage {
 let text: String; let attributes: [MessageAttribute]; let group: Int64?
 static func message(text: String, attributes: [MessageAttribute], inlineStickers: [MediaId: Media], mediaReference: AnyMediaReference?, threadId: Int64?, replyToMessageId: Int?, replyToStoryId: Int?, localGroupingKey: Int64?, correlationId: Int64?, bubbleUpEmojiOrStickersets: [Int]) -> Self { Self(text: text, attributes: attributes, group: localGroupingKey) }
}
var sent: [EnqueueMessage] = []
struct Start { func startStandalone() {} }
func enqueueMessages(account: Int, peerId: EnginePeer.Id, messages: [EnqueueMessage]) -> Start { sent = messages; return Start() }
extension TextEntitiesMessageAttribute { convenience init(entities: [MessageTextEntity]) { self.init(entities) } }
'''
source = models
source += enum('submodules/TelegramCore/Sources/SyncCore/SyncCore_RichText.swift', 'public indirect enum RichText:')
source += enum('submodules/TelegramCore/Sources/SyncCore/SyncCore_InstantPage.swift', 'public indirect enum InstantPageBlock:')
source += enum('submodules/TelegramCore/Sources/SyncCore/SyncCore_InstantPage.swift', 'public indirect enum InstantPageListItem:')
source += between('submodules/TelegramCore/Sources/SyncCore/SyncCore_RichText.swift', 'public extension RichText {', '\nextension RichText {')
source += read('submodules/TelegramCore/Sources/Utils/RGMessageText.swift').replace('import Postbox', '')
source += between('submodules/AccountContext/Sources/RGContentFilter.swift', 'private final class RGContentFilterVerdictCache', '/// Emits on every message-filter')
source += between('submodules/TelegramUI/Sources/RGRepeatMessages.swift', 'private func rgRepeatableMedia', '/// Re-sends the messages')
source += between('submodules/TelegramUI/Sources/RGRepeatMessages.swift', 'private func rgEnqueueRepeatCopy', '/// 复读:')
source += between('submodules/TelegramCore/Sources/Utils/RGEditHistory.swift', 'func rgCarryOverLocalMessageAttributes', '// MARK: Regram — preserve already downloaded')
summary = next(line for line in read('Regram/RGProUI/Sources/RGMessageSummaryController.swift').splitlines() if 'let messages = messages.sorted' in line)
bookmark = next(line for line in read('Regram/RGProUI/Sources/RGBookmarksController.swift').splitlines() if 'let preview = row.message.map' in line)
source += '\nfunc summary(_ messages: [Message]) -> [Message] {\n' + summary + '\nreturn messages\n}\n'
source += 'func bookmark(_ message: Message) -> String { let row = Row(message: message); let lang = "en"\n' + bookmark + '\nreturn preview\n}\n'
source += 'func groupSpoilers(_ message: Message) -> [Range<Int>] {\n' + between('Regram/RGCommonGroupMessagesUI/Sources/RGCommonGroupMessagesController.swift', '            let spoilers:', '            let preview =') + '\nreturn spoilers\n}\n'
source += r'''
@main enum Checks {
 static func main() {
  let peer = EnginePeer.Id(value: 1, namespace: 0), account = EnginePeer.Id(value: 2, namespace: 0)
  let caption = InstantPageCaption(text: .plain("media caption"), credit: .plain("credit"))
  let page = InstantPage(blocks: [.heading(text: .plain("blocked heading"), level: 1), .table(title: .plain("table"), rows: [.init(cells: [.init(text: .plain("old cell")), .init(text: .plain("second cell"))])], bordered: true, striped: false, compact: false), .details(title: .plain("details"), blocks: [.list(items: [.text(.plain("list item"), nil, nil)], ordered: false)], expanded: false), .image(id: .init(namespace: 0, id: 1), caption: caption, url: nil, webpageId: nil, spoiler: false), .paragraph(.bold(.textSpoiler(text: .plain("spoiler secret"))))])
  func message(_ text: String, _ rich: RichTextMessageAttribute? = nil, id: Int32 = 1, extra: [MessageAttribute] = []) -> Message {
   .init(id: .init(peerId: peer, namespace: 0, id: id), stableVersion: 1, text: text, author: .init(id: peer), attributes: (rich.map { [$0] } ?? []) + extra, media: [])
  }
  let rich = message("", .init(instantPage: page)), plain = message("plain control", id: 2)
  for word in ["blocked heading", "old cell", "second cell", "list item", "media caption", "credit", "spoiler secret"] { precondition(rich.rgTextContent.contains(word), word) }
  precondition(!rich.rgPreviewText.contains("spoiler secret") && rich.rgPreviewText.contains("•••"))
  let legacy = TextEntitiesMessageAttribute([MessageTextEntity(text: "legacy")])
  precondition(groupSpoilers(message("legacy", extra: [legacy])) == [0..<6])
  precondition(groupSpoilers(message("legacy", .init(instantPage: page), extra: [legacy])).isEmpty, "Legacy fallback offsets cannot be reused for a rich preview")
  RGSimpleSettings.shared.messageFilterRules = [RGMessageFilterRule(pattern: "blocked")]
  precondition(RGContentFilterState(accountPeerId: account).shouldHide(message: .init(raw: rich)))
  precondition(summary([rich, plain]).count == 2 && bookmark(rich).contains("old cell"))
  precondition(!bookmark(rich).contains("spoiler secret"))
  precondition(rgRepeatCopyItems([rich])?.count == 1 && rgRepeatCopyItems([message("")]) == nil)
  rgEnqueueRepeatCopy(context: AccountContext(), peerId: peer, threadId: 42, items: [(rich, nil), (plain, nil)], richPages: [rich.id: RichTextMessageAttribute(instantPage: page)])
  precondition(sent.count == 2 && sent[0].text.isEmpty && sent[1].text == "plain control" && sent[0].group == sent[1].group && sent[0].group != nil)
  precondition(sent[0].attributes.compactMap { $0 as? RichTextMessageAttribute }.first?.instantPage == page, "Copy-repeat must enqueue the structured payload, not only become eligible")
  precondition(sent[1].attributes.isEmpty)
  let changed = RichTextMessageAttribute(instantPage: .init(blocks: [.heading(text: .plain("NEW heading"), level: 1)]))
  let attrs = rgCarryOverLocalMessageAttributes(previousMessage: rich, updatedText: "", updatedAttributes: [changed, EditedMessageAttribute(20)], updatedMedia: [], mediaBox: MediaBox())
  let history = attrs.compactMap { $0 as? RGEditHistoryMessageAttribute }.first!
  precondition(history.entries.count == 1 && history.entries[0].richText?.instantPage == page && history.entries[0].text.contains("old cell"))
  let hydrated = RichTextMessageAttribute(instantPage: page, fullInstantPage: changed.instantPage)
  let unchanged = rgCarryOverLocalMessageAttributes(previousMessage: rich, updatedText: "", updatedAttributes: [hydrated], updatedMedia: [], mediaBox: MediaBox())
  precondition(!unchanged.contains { $0 is RGEditHistoryMessageAttribute }, "Full-page hydration must not create an edit")
  let converted = rgCarryOverLocalMessageAttributes(previousMessage: rich, updatedText: "plain replacement", updatedAttributes: [EditedMessageAttribute(20)], updatedMedia: [], mediaBox: MediaBox())
  precondition(converted.compactMap { $0 as? RGEditHistoryMessageAttribute }.first?.entries.first?.richText != nil)
  precondition(message("fallback", .init(instantPage: .init(blocks: []), fullInstantPage: page)).rgTextContent == rich.rgTextContent)
  print("Rich-message checks passed: production block projection, nested spoilers, filtering, summary/preview selection, repeat eligibility, rich edit snapshots and hydration exclusion.")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-rich-messages-') as temporary:
    work = Path(temporary)
    (work / 'Checks.swift').write_text(source)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', str(root / 'Regram/RGSimpleSettings/Sources/MessageFilter.swift'), str(work / 'Checks.swift'), '-o', str(work / 'checks')], check=True)
    subprocess.run([str(work / 'checks')], check=True, timeout=30)
