import XCTest
import Foundation // MARK: Regram — isolated media storage for the merged update path.
import Postbox
@testable import TelegramCore

/// `mergedServerMessageUpdate`: the server's copy of a stored message keeps the state the server does not send.
/// Edit updates have always merged this way; feed pages, which refresh posts the account already stores, do too.
final class ServerMessageMergeTests: XCTestCase {
    // MARK: Regram — the shared merge now retains cached edit-history media as well.
    private var mediaBox: MediaBox!
    private var mediaPath: String!

    override func setUp() {
        super.setUp()
        self.mediaPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        self.mediaBox = MediaBox(basePath: self.mediaPath, isMainProcess: false)
    }

    override func tearDown() {
        self.mediaBox = nil
        try? FileManager.default.removeItem(atPath: self.mediaPath)
        super.tearDown()
    }
    private let channel = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(1))

    private var messageId: MessageId {
        return MessageId(peerId: self.channel, namespace: Namespaces.Message.Cloud, id: 10)
    }

    private func stored(text: String, attributes: [MessageAttribute], media: [Media]) -> Message {
        return Message(stableId: 1, stableVersion: 0, id: self.messageId, globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 100, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: text, attributes: attributes, media: media, peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func fromServer(text: String, media: [Media]) -> StoreMessage {
        return StoreMessage(id: self.messageId, customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: 100, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: nil, text: text, attributes: [], media: media)
    }

    func testTranslationSurvivesTheSameText() {
        let translation = TranslationMessageAttribute(text: "Hallo", entities: [], toLang: "de")
        let merged = mergedServerMessageUpdate(previous: self.stored(text: "Hello", attributes: [translation], media: []), updated: self.fromServer(text: "Hello", media: []), mediaBox: self.mediaBox)
        XCTAssertTrue(merged.attributes.contains(where: { $0 is TranslationMessageAttribute }))
    }

    func testTranslationIsDroppedWhenTheTextChanged() {
        let translation = TranslationMessageAttribute(text: "Hallo", entities: [], toLang: "de")
        let merged = mergedServerMessageUpdate(previous: self.stored(text: "Hello", attributes: [translation], media: []), updated: self.fromServer(text: "Hello!", media: []), mediaBox: self.mediaBox)
        XCTAssertFalse(merged.attributes.contains(where: { $0 is TranslationMessageAttribute }))
    }

    // MARK: Regram — an upstream edit/feed refresh must not erase locally retained history.
    func testLocalHistorySurvivesAServerRefresh() {
        let history = RGEditHistoryMessageAttribute(entries: [RGEditHistoryEntry(text: "Original", entities: [], date: 50)])
        let merged = mergedServerMessageUpdate(previous: self.stored(text: "Hello", attributes: [history], media: []), updated: self.fromServer(text: "Hello", media: []), mediaBox: self.mediaBox)
        let storedHistory = merged.attributes.compactMap { $0 as? RGEditHistoryMessageAttribute }
        XCTAssertEqual(storedHistory.count, 1)
        XCTAssertEqual(storedHistory.first?.entries.first?.text, "Original")
    }

    // A purchased paid post must not fall back to its locked preview.
    func testUnlockedPaidMediaSurvives() {
        let image = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: 1), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        let unlocked = TelegramMediaPaidContent(amount: 10, extendedMedia: [.full(media: image)])
        let locked = TelegramMediaPaidContent(amount: 10, extendedMedia: [.preview(dimensions: nil, immediateThumbnailData: nil, videoDuration: nil)])
        let merged = mergedServerMessageUpdate(previous: self.stored(text: "", attributes: [], media: [unlocked]), updated: self.fromServer(text: "", media: [locked]), mediaBox: self.mediaBox)
        guard let paid = merged.media.first as? TelegramMediaPaidContent, case .full = paid.extendedMedia.first else {
            XCTFail("the paid media went back to its preview")
            return
        }
    }
}
