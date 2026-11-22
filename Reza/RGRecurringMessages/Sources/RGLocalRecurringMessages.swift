// MARK: Regram — account-local daily tasks, sent silently on the first foreground launch of each day.
import Foundation
import Postbox
import SwiftSignalKit

private let rgDailyTasksKey = ValueBoxKey("regram.startupDailyMessages.v1")
private struct RGStartupDailyTask: Codable {
    var messageId: MessageId
    var lastSentDay: Int?
    var lastRunMessageId: MessageId?
}
private struct RGStartupDailyState: Codable {
    var tasks: [RGStartupDailyTask] = []
}
private func rgDailyState(_ transaction: Transaction) -> RGStartupDailyState {
    transaction.getPreferencesEntry(key: rgDailyTasksKey)?.get(RGStartupDailyState.self) ?? RGStartupDailyState()
}
private func rgSaveDailyState(_ transaction: Transaction, _ state: RGStartupDailyState) {
    transaction.updatePreferencesEntry(key: rgDailyTasksKey, { _ in PreferencesEntry(state) })
}
private func rgDailyStoreMessage(_ message: Message, timestamp: Int32? = nil, flags: StoreMessageFlags? = nil, text: String? = nil, attributes: [MessageAttribute]? = nil, media: [Media]? = nil) -> StoreMessage {
    StoreMessage(id: message.id, customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: timestamp ?? message.timestamp, flags: flags ?? StoreMessageFlags(message.flags), tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: message.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: message.author?.id, text: text ?? message.text, attributes: attributes ?? message.attributes, media: media ?? message.media)
}

/// Keep a local scheduled-list entry as the editable task; it must never enter the network outbox.
func rgCaptureStartupDailyMessages(transaction: Transaction, ids: [MessageId]) {
    var state = rgDailyState(transaction)
    var changed = false
    for id in ids where id.namespace == Namespaces.Message.ScheduledLocal {
        guard let message = transaction.getMessage(id), message.scheduleRepeatPeriod == rgStartupDailyRepeatPeriod else { continue }
        if !state.tasks.contains(where: { $0.messageId == id }) {
            state.tasks.append(.init(messageId: id, lastSentDay: nil, lastRunMessageId: nil))
            changed = true
        }
        transaction.updateMessage(id, update: { current in
            var flags = StoreMessageFlags(current.flags)
            flags.subtract([.Unsent, .Sending, .Failed])
            return .update(rgDailyStoreMessage(current, flags: flags))
        })
    }
    if changed { rgSaveDailyState(transaction, state) }
}

func rgRemoveStartupDailyMessages(transaction: Transaction, ids: [MessageId]) {
    let ids = Set(ids)
    var state = rgDailyState(transaction)
    let previousCount = state.tasks.count
    state.tasks.removeAll { ids.contains($0.messageId) }
    if previousCount != state.tasks.count { rgSaveDailyState(transaction, state) }
}

private func rgEnqueueStartupDailyMessage(transaction: Transaction, account: Account, task: RGStartupDailyTask, now: Date, calendar: Calendar, force: Bool) -> MessageId? {
    guard let message = transaction.getMessage(task.messageId), force || RGRecurringSchedulePolicy.shouldRun(start: message.timestamp, lastSentDay: task.lastSentDay, now: now, calendar: calendar) else { return nil }
    // An offline outbox entry already owns this occurrence; resuming must not add a second copy.
    if !force, let pendingId = task.lastRunMessageId, let pending = transaction.getMessage(pendingId),
       pending.flags.contains(.Unsent) || pending.flags.contains(.Sending) {
        return pendingId
    }
    var attributes = filterMessageAttributesForOutgoingMessage(message.attributes)
    attributes.removeAll { $0 is OutgoingScheduleInfoMessageAttribute || $0 is OutgoingQuickReplyMessageAttribute || $0 is NotificationInfoMessageAttribute || $0 is PaidStarsMessageAttribute }
    attributes.append(NotificationInfoMessageAttribute(flags: [.muted]))
    let reply = message.attributes.compactMap { $0 as? ReplyMessageAttribute }.first.map(resentReplySubject)
    let replyStory = message.attributes.compactMap { $0 as? ReplyStoryAttribute }.first?.storyId
    let mediaReference = message.media.first.map { media -> AnyMediaReference in
        if let sourceId = task.lastRunMessageId, let source = transaction.getMessage(sourceId) {
            return .message(message: MessageReference(source), media: media)
        }
        return .standalone(media: media)
    }
    let enqueue = EnqueueMessage.message(text: message.text, attributes: attributes, inlineStickers: [:], mediaReference: mediaReference, threadId: message.threadId, replyToMessageId: reply, replyToStoryId: replyStory, localGroupingKey: message.groupingKey.map { $0 &+ Int64(RGRecurringSchedulePolicy.dayKey(now, calendar: calendar)) }, correlationId: nil, bubbleUpEmojiOrStickersets: [])
    return enqueueMessages(transaction: transaction, account: account, peerId: message.id.peerId, messages: [(false, enqueue)]).first ?? nil
}

/// The outbox insertion and day marker commit together, including when the app exits offline.
func rgRunStartupDailyMessages(transaction: Transaction, account: Account, now: Date, calendar: Calendar, only messageId: MessageId? = nil, force: Bool = false) -> Bool {
    var state = rgDailyState(transaction)
    // b34635 used the native daily value. Only registered local tasks migrate; server schedules stay intact.
    for task in state.tasks where task.messageId.namespace == Namespaces.Message.ScheduledLocal {
        guard transaction.getMessage(task.messageId)?.scheduleRepeatPeriod == 86400 else { continue }
        transaction.updateMessage(task.messageId, update: { current in
            let attributes = current.attributes.map { attribute -> MessageAttribute in
                if let schedule = attribute as? OutgoingScheduleInfoMessageAttribute, schedule.repeatPeriod == 86400 {
                    return schedule.withUpdatedRepeatPeriod(rgStartupDailyRepeatPeriod)
                }
                return attribute
            }
            return .update(rgDailyStoreMessage(current, attributes: attributes))
        })
    }
    var changed = false
    var found = false
    for index in state.tasks.indices where messageId == nil || state.tasks[index].messageId == messageId {
        found = true
        if let id = rgEnqueueStartupDailyMessage(transaction: transaction, account: account, task: state.tasks[index], now: now, calendar: calendar, force: force) {
            state.tasks[index].lastSentDay = RGRecurringSchedulePolicy.dayKey(now, calendar: calendar)
            state.tasks[index].lastRunMessageId = id
            changed = true
        }
    }
    if changed { rgSaveDailyState(transaction, state) }
    return found
}

public func rgRunStartupDailyMessages(account: Account) -> Signal<Void, NoError> {
    account.postbox.transaction { transaction -> Void in
        _ = rgRunStartupDailyMessages(transaction: transaction, account: account, now: Date(), calendar: .current)
    }
}

func rgSendStartupDailyMessageNow(account: Account, messageId: MessageId) -> Signal<Never, NoError> {
    account.postbox.transaction { transaction -> Bool in
        rgRunStartupDailyMessages(transaction: transaction, account: account, now: Date(), calendar: .current, only: messageId, force: true)
    }
    |> mapToSignal { handled -> Signal<Never, NoError> in
        handled ? .complete() : _internal_sendScheduledMessageNowInteractively(postbox: account.postbox, messageId: messageId)
    }
}

/// Retain resolved cloud media on the editable task after each successful send.
func rgApplyStartupDailyDelivery(transaction: Transaction, previousId: MessageId, updatedId: MessageId) {
    var state = rgDailyState(transaction)
    guard let index = state.tasks.firstIndex(where: { $0.lastRunMessageId == previousId }), let sent = transaction.getMessage(updatedId) else { return }
    state.tasks[index].lastRunMessageId = updatedId
    let taskId = state.tasks[index].messageId
    transaction.updateMessage(taskId, update: { current in
        return .update(rgDailyStoreMessage(current, media: sent.media))
    })
    rgSaveDailyState(transaction, state)
}

func rgEditStartupDailyMessage(transaction: Transaction, messageId: MessageId, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, richText: RichTextMessageAttribute?, inlineStickers: [MediaId: Media], webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool, scheduleInfoAttribute: OutgoingScheduleInfoMessageAttribute?, invertMediaAttribute: InvertMediaMessageAttribute?) -> Bool? {
    guard rgDailyState(transaction).tasks.contains(where: { $0.messageId == messageId }), let message = transaction.getMessage(messageId) else { return nil }
    for (_, sticker) in inlineStickers { transaction.storeMediaIfNotPresent(media: sticker) }
    var attributes = message.attributes.filter { !($0 is TextEntitiesMessageAttribute) && !($0 is RichTextMessageAttribute) && !($0 is WebpagePreviewMessageAttribute) && !($0 is OutgoingContentInfoMessageAttribute) && !($0 is InvertMediaMessageAttribute) }
    if let entities { attributes.append(entities) }
    if let richText { attributes.append(richText) }
    if let webpagePreviewAttribute { attributes.append(webpagePreviewAttribute) }
    if let invertMediaAttribute { attributes.append(invertMediaAttribute) }
    if disableUrlPreview { attributes.append(OutgoingContentInfoMessageAttribute(flags: [.disableLinkPreviews])) }
    var flags = StoreMessageFlags(message.flags)
    if let scheduleInfoAttribute {
        attributes.removeAll { $0 is OutgoingScheduleInfoMessageAttribute }
        attributes.append(scheduleInfoAttribute)
        if scheduleInfoAttribute.repeatPeriod != rgStartupDailyRepeatPeriod {
            rgRemoveStartupDailyMessages(transaction: transaction, ids: [messageId])
            flags.insert(.Unsent)
        }
    }
    let mediaList: [Media]
    switch media { case .keep: mediaList = message.media; case let .update(reference): mediaList = [augmentMediaWithReference(reference)] }
    transaction.updateMessage(messageId, update: { current in
        .update(rgDailyStoreMessage(current, timestamp: scheduleInfoAttribute?.scheduleTime, flags: flags, text: text, attributes: attributes, media: mediaList))
    })
    return true
}

/// Changing an existing server schedule to Daily creates the same persistent local task as a new send.
func rgConvertStartupDailyMessage(transaction: Transaction, account: Account, messageId: MessageId, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, richText: RichTextMessageAttribute?, inlineStickers: [MediaId: Media], webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool, scheduleInfoAttribute: OutgoingScheduleInfoMessageAttribute, invertMediaAttribute: InvertMediaMessageAttribute?) -> Bool? {
    guard messageId.namespace == Namespaces.Message.ScheduledCloud, scheduleInfoAttribute.repeatPeriod == rgStartupDailyRepeatPeriod,
          let message = transaction.getMessage(messageId) else { return nil }
    var attributes = filterMessageAttributesForOutgoingMessage(message.attributes)
    attributes.removeAll { $0 is OutgoingScheduleInfoMessageAttribute }
    attributes.append(scheduleInfoAttribute)
    let reply = message.attributes.compactMap { $0 as? ReplyMessageAttribute }.first.map(resentReplySubject)
    let replyStory = message.attributes.compactMap { $0 as? ReplyStoryAttribute }.first?.storyId
    let enqueue = EnqueueMessage.message(text: message.text, attributes: attributes, inlineStickers: inlineStickers, mediaReference: message.media.first.map(AnyMediaReference.standalone), threadId: message.threadId, replyToMessageId: reply, replyToStoryId: replyStory, localGroupingKey: message.groupingKey, correlationId: nil, bubbleUpEmojiOrStickersets: [])
    guard let id = enqueueMessages(transaction: transaction, account: account, peerId: messageId.peerId, messages: [(false, enqueue)]).first ?? nil else { return false }
    _ = rgEditStartupDailyMessage(transaction: transaction, messageId: id, text: text, media: media, entities: entities, richText: richText, inlineStickers: inlineStickers, webpagePreviewAttribute: webpagePreviewAttribute, disableUrlPreview: disableUrlPreview, scheduleInfoAttribute: scheduleInfoAttribute, invertMediaAttribute: invertMediaAttribute)
    deleteMessagesInteractively(transaction: transaction, stateManager: account.stateManager, postbox: account.postbox, messageIds: [messageId], type: .forEveryone, removeIfPossiblyDelivered: false)
    return true
}
