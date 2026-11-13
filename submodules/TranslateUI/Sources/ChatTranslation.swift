import TextFormat
import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramUIPreferences

public struct ChatTranslationState: Codable, Equatable {
    // MARK: Regram — refresh cached Chinese detections made before checking the actual characters.
    fileprivate static let currentDetectionVersion: Int32 = 2

    enum CodingKeys: String, CodingKey {
        case baseLang
        case fromLang
        case timestamp
        case toLang
        case isEnabled
        case detectionVersion
    }
    
    public let baseLang: String
    public let fromLang: String
    public let timestamp: Int32?
    public let toLang: String?
    public let isEnabled: Bool
    fileprivate let detectionVersion: Int32
    
    public init(
        baseLang: String,
        fromLang: String,
        timestamp: Int32?,
        toLang: String?,
        isEnabled: Bool
    ) {
        self.init(baseLang: baseLang, fromLang: fromLang, timestamp: timestamp, toLang: toLang, isEnabled: isEnabled, detectionVersion: Self.currentDetectionVersion)
    }

    private init(
        baseLang: String,
        fromLang: String,
        timestamp: Int32?,
        toLang: String?,
        isEnabled: Bool,
        detectionVersion: Int32
    ) {
        self.baseLang = baseLang
        self.fromLang = fromLang
        self.timestamp = timestamp
        self.toLang = toLang
        self.isEnabled = isEnabled
        self.detectionVersion = detectionVersion
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.baseLang = try container.decode(String.self, forKey: .baseLang)
        self.fromLang = try container.decode(String.self, forKey: .fromLang)
        self.timestamp = try container.decodeIfPresent(Int32.self, forKey: .timestamp)
        self.toLang = try container.decodeIfPresent(String.self, forKey: .toLang)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.detectionVersion = try container.decodeIfPresent(Int32.self, forKey: .detectionVersion) ?? 0
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.baseLang, forKey: .baseLang)
        try container.encode(self.fromLang, forKey: .fromLang)
        try container.encodeIfPresent(self.timestamp, forKey: .timestamp)
        try container.encodeIfPresent(self.toLang, forKey: .toLang)
        try container.encode(self.isEnabled, forKey: .isEnabled)
        try container.encode(self.detectionVersion, forKey: .detectionVersion)
    }

    public func withFromLang(_ fromLang: String) -> ChatTranslationState {
        return ChatTranslationState(
            baseLang: self.baseLang,
            fromLang: fromLang,
            timestamp: self.timestamp,
            toLang: self.toLang,
            isEnabled: self.isEnabled,
            detectionVersion: self.detectionVersion
        )
    }
    public func withToLang(_ toLang: String?) -> ChatTranslationState {
        return ChatTranslationState(
            baseLang: self.baseLang,
            fromLang: self.fromLang,
            timestamp: self.timestamp,
            toLang: toLang,
            isEnabled: self.isEnabled,
            detectionVersion: self.detectionVersion
        )
    }
    
    public func withIsEnabled(_ isEnabled: Bool) -> ChatTranslationState {
        return ChatTranslationState(
            baseLang: self.baseLang,
            fromLang: self.fromLang,
            timestamp: self.timestamp,
            toLang: self.toLang,
            isEnabled: isEnabled,
            detectionVersion: self.detectionVersion
        )
    }
}

/// Whether to translate a chat and into which language: the user's choice, as opposed to the language a chat is
/// detected to be in. A peer with threads (forum topics, a discussion group's comment threads) has one choice that every
/// thread and the peer's own chat share, so enabling translation in one topic enables it in all of them; the detected
/// language stays each location's own (`ChatTranslationState.fromLang`), so a topic in an ignored language shows no
/// translation without turning it off for the others.
public struct ChatTranslationPeerChoice: Codable, Equatable {
    public let isEnabled: Bool
    public let toLang: String?
    
    public init(isEnabled: Bool, toLang: String?) {
        self.isEnabled = isEnabled
        self.toLang = toLang
    }
    
    public init(_ state: ChatTranslationState) {
        self.init(isEnabled: state.isEnabled, toLang: state.toLang)
    }
}

/// Whether a peer's locations share one `ChatTranslationPeerChoice`. A monoforum's threads are separate conversations,
/// each with a different user, so each keeps its own choice, as separate private chats do.
public func chatTranslationSharesPeerChoice(peer: EnginePeer?) -> Bool {
    if let peer, peer.isMonoForum {
        return false
    }
    return true
}

/// The choice to store for a peer that has none yet, from the state of one of its locations: translation was stored
/// per topic before the choice was shared, so a location translated then enables the whole peer.
public func chatTranslationPeerChoiceToMigrate(locationState: ChatTranslationState, peerChoice: ChatTranslationPeerChoice?) -> ChatTranslationPeerChoice? {
    if peerChoice == nil && locationState.isEnabled {
        return ChatTranslationPeerChoice(locationState)
    }
    return nil
}

/// Whether discarding a location's state (its language added to "Do not translate") discards the peer's choice too. In a
/// chat without topics the location is the whole peer, so its choice goes with it and the chat comes back untranslated,
/// as before the choice was shared; in a forum the other topics, in other languages, keep translating.
public func chatTranslationDiscardsPeerChoice(peer: EnginePeer?, threadId: Int64?) -> Bool {
    if threadId != nil {
        return false
    }
    if let peer, peer._asPeer().isForum {
        return false
    }
    return true
}

public extension ChatTranslationState {
    /// The state with the peer's choice in place of the location's own one, if the peer has a choice.
    func withPeerChoice(_ peerChoice: ChatTranslationPeerChoice?) -> ChatTranslationState {
        guard let peerChoice else {
            return self
        }
        return self.withToLang(peerChoice.toLang).withIsEnabled(peerChoice.isEnabled)
    }
}

/// A location's state under the peer's choice. When the choice's target language is the language the location is
/// detected to be in (a topic already in the language the forum is translated into), the location has nothing to
/// translate into it: it is shown untranslated, offering the base language, so its bar still lets the user translate it
/// or pick another language.
public func effectiveChatTranslationState(_ locationState: ChatTranslationState, peerChoice: ChatTranslationPeerChoice?) -> ChatTranslationState {
    guard let peerChoice else {
        return locationState
    }
    let toLang = normalizeTranslationTargetLanguage(peerChoice.toLang ?? locationState.baseLang) // MARK: Regram
    if toLang == normalizeTranslationLanguage(locationState.fromLang) {
        return locationState.withToLang(nil).withIsEnabled(false)
    }
    return locationState.withPeerChoice(peerChoice)
}

/// A location's state: the peer's own chat, or one of its threads.
func chatTranslationStateKey(peerId: EnginePeer.Id, threadId: Int64?) -> EngineDataBuffer {
    let key: EngineDataBuffer
    if let threadId {
        key = EngineDataBuffer(length: 16)
        key.setInt64(0, value: peerId.id._internalGetInt64Value())
        key.setInt64(8, value: threadId)
    } else {
        key = EngineDataBuffer(length: 8)
        key.setInt64(0, value: peerId.id._internalGetInt64Value())
    }
    return key
}

/// The peer's `ChatTranslationPeerChoice`, in the same collection (so resetting translation states clears it too), under
/// a key length no location's key has.
func chatTranslationPeerChoiceKey(peerId: EnginePeer.Id) -> EngineDataBuffer {
    let key = EngineDataBuffer(length: 12)
    key.setInt64(0, value: peerId.id._internalGetInt64Value())
    key.setInt32(8, value: peerId.namespace._internalGetInt32Value())
    return key
}

private func cachedChatTranslationState(engine: TelegramEngine, peerId: EnginePeer.Id, threadId: Int64?) -> Signal<ChatTranslationState?, NoError> {
    let key = chatTranslationStateKey(peerId: peerId, threadId: threadId)
    
    return engine.data.subscribe(TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key))
    |> map { entry -> ChatTranslationState? in
        return entry?.get(ChatTranslationState.self)
    }
}

private func updateChatTranslationState(engine: TelegramEngine, peerId: EnginePeer.Id, threadId: Int64?, state: ChatTranslationState?) -> Signal<Never, NoError> {
    let key = chatTranslationStateKey(peerId: peerId, threadId: threadId)
    
    if let state {
        return engine.itemCache.put(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key, item: state)
    } else {
        return engine.itemCache.remove(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key)
    }
}

private func cachedChatTranslationPeerChoice(engine: TelegramEngine, peerId: EnginePeer.Id) -> Signal<ChatTranslationPeerChoice?, NoError> {
    return engine.data.subscribe(TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: chatTranslationPeerChoiceKey(peerId: peerId)))
    |> map { entry -> ChatTranslationPeerChoice? in
        return entry?.get(ChatTranslationPeerChoice.self)
    }
    |> distinctUntilChanged
}

private func updateChatTranslationPeerChoice(engine: TelegramEngine, peerId: EnginePeer.Id, choice: ChatTranslationPeerChoice) -> Signal<Never, NoError> {
    return engine.itemCache.put(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: chatTranslationPeerChoiceKey(peerId: peerId), item: choice)
}

public func updateChatTranslationStateInteractively(engine: TelegramEngine, peerId: EnginePeer.Id, threadId: Int64?, _ f: @escaping (ChatTranslationState?) -> ChatTranslationState?) -> Signal<Never, NoError> {
    return engine.data.get(
        TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: chatTranslationStateKey(peerId: peerId, threadId: threadId)),
        TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: chatTranslationPeerChoiceKey(peerId: peerId)),
        TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)
    )
    |> mapToSignal { entry, peerChoiceEntry, peer -> Signal<Never, NoError> in
        if let current = entry?.get(ChatTranslationState.self) {
            let sharesPeerChoice = chatTranslationSharesPeerChoice(peer: peer)
            let peerChoice = sharesPeerChoice ? peerChoiceEntry?.get(ChatTranslationPeerChoice.self) : nil
            let updated = f(effectiveChatTranslationState(current, peerChoice: peerChoice))
            // The choice is written first: readers take it over the location's own, so the toggle shows at once.
            if sharesPeerChoice, let updated {
                return updateChatTranslationPeerChoice(engine: engine, peerId: peerId, choice: ChatTranslationPeerChoice(updated))
                |> then(updateChatTranslationState(engine: engine, peerId: peerId, threadId: threadId, state: updated))
            } else if sharesPeerChoice, chatTranslationDiscardsPeerChoice(peer: peer, threadId: threadId) {
                // The location goes first, so that no reader sees it still enabled with no choice and migrates it back.
                return updateChatTranslationState(engine: engine, peerId: peerId, threadId: threadId, state: updated)
                |> then(engine.itemCache.remove(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: chatTranslationPeerChoiceKey(peerId: peerId)))
            } else {
                return updateChatTranslationState(engine: engine, peerId: peerId, threadId: threadId, state: updated)
            }
        } else {
            return .never()
        }
    }
}


public func translateMessageIds(context: AccountContext, messageIds: [EngineMessage.Id], fromLang: String?, toLang: String, viaText: Bool = false, forQuickTranslate: Bool = false) -> Signal<Never, NoError> {
    return context.account.postbox.transaction { transaction -> Signal<Never, NoError> in
        var messageDictToTranslate: [EngineMessage.Id: String] = [:]
        var messageIdsToTranslate: [EngineMessage.Id] = []
        var messageIdsSet = Set<EngineMessage.Id>()
        for messageId in messageIds {
            if let message = transaction.getMessage(messageId) {
                if let replyAttribute = message.attributes.first(where: { $0 is ReplyMessageAttribute }) as? ReplyMessageAttribute, let replyMessage = message.associatedMessages[replyAttribute.messageId] {
                    if !replyMessage.text.isEmpty {
                        if let translation = replyMessage.attributes.first(where: { $0 is TranslationMessageAttribute }) as? TranslationMessageAttribute, translation.toLang == toLang {
                        } else {
                            if !messageIdsSet.contains(replyMessage.id) {
                                messageIdsToTranslate.append(replyMessage.id)
                                messageIdsSet.insert(replyMessage.id)
                                messageDictToTranslate[replyMessage.id] = replyMessage.text
                            }
                        }
                    }
                }
                // MARK: Regram
                guard forQuickTranslate || message.author?.id != context.account.peerId else {
                    continue
                }
                if let translation = message.attributes.first(where: { $0 is TranslationMessageAttribute }) as? TranslationMessageAttribute, translation.toLang == toLang {
                    continue
                }
                
                if !message.text.isEmpty {
                    if !messageIdsSet.contains(messageId) {
                        messageIdsToTranslate.append(messageId)
                        messageIdsSet.insert(messageId)
                        messageDictToTranslate[messageId] = message.text
                    }
                } else if let _ = message.richText {
                    if !messageIdsSet.contains(messageId) {
                        messageIdsToTranslate.append(messageId)
                        messageIdsSet.insert(messageId)
                        messageDictToTranslate[messageId] = message.text
                    }
                } else if let _ = message.richText {
                    if !messageIdsSet.contains(messageId) {
                        messageIdsToTranslate.append(messageId)
                        messageIdsSet.insert(messageId)
                        messageDictToTranslate[messageId] = message.text
                    }
                // TODO(regram): Translate polls
                } else if let _ = message.media.first(where: { $0 is TelegramMediaPoll }), !viaText {
                    if !messageIdsSet.contains(messageId) {
                        messageIdsToTranslate.append(messageId)
                        messageIdsSet.insert(messageId)
                    }
                } else if let audioTranscription = message.attributes.first(where: { $0 is AudioTranscriptionMessageAttribute }) as? AudioTranscriptionMessageAttribute, !audioTranscription.text.isEmpty && !audioTranscription.isPending {
                    if !messageIdsSet.contains(messageId) {
                        messageIdsToTranslate.append(messageId)
                        messageIdsSet.insert(messageId)
                    }
                }
            } else {
                if !messageIdsSet.contains(messageId) {
                    messageIdsToTranslate.append(messageId)
                    messageIdsSet.insert(messageId)
                }
            }
        }
        
        let translationConfiguration = TranslationConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
        var enableLocalIfPossible = false
        switch translationConfiguration.auto {
        case .system:
            if #available(iOS 18.0, *) {
                enableLocalIfPossible = true
            }
        default:
            break
        }
        // MARK: Regram — when Apple translation has both languages, use it before any text fallback.
        if viaText && (!enableLocalIfPossible || fromLang == nil) {
        return context.engine.messages.translateMessagesViaText(messagesDict: messageDictToTranslate, fromLang: fromLang, toLang: toLang, generateEntitiesFunction: { text in
            generateTextEntities(text, enabledTypes: .all)
        }, enableLocalIfPossible: enableLocalIfPossible) //context.sharedContext.immediateExperimentalUISettings.enableLocalTranslation)
        |> `catch` { _ -> Signal<Never, NoError> in
            return .complete()
        }
        } else {
        if forQuickTranslate && messageIdsToTranslate.isEmpty { return .complete() } // Otherwise Telegram's API will return .never()
        return context.engine.messages.translateMessages(messageIds: messageIdsToTranslate, fromLang: fromLang, toLang: toLang, enableLocalIfPossible: enableLocalIfPossible)
        |> `catch` { _ -> Signal<Never, NoError> in
            return translateMessageIds(context: context, messageIds: messageIdsToTranslate, fromLang: fromLang, toLang: toLang, viaText: true, forQuickTranslate: forQuickTranslate)
        }
        }
    } |> switchToLatest
}

public func chatTranslationState(context: AccountContext, peerId: EnginePeer.Id, threadId: Int64?, forcePredict: Bool = false) -> Signal<ChatTranslationState?, NoError> {
    let sharesPeerChoice = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    |> map { peer -> Bool in
        return chatTranslationSharesPeerChoice(peer: peer)
    }
    
    return chatTranslationLocationState(context: context, peerId: peerId, threadId: threadId, forcePredict: forcePredict)
    |> mapToSignal { state -> Signal<ChatTranslationState?, NoError> in
        guard let state else {
            return .single(nil)
        }
        return combineLatest(sharesPeerChoice, cachedChatTranslationPeerChoice(engine: context.engine, peerId: peerId))
        |> map { sharesPeerChoice, peerChoice -> ChatTranslationState? in
            guard sharesPeerChoice else {
                return state
            }
            if let migratedChoice = chatTranslationPeerChoiceToMigrate(locationState: state, peerChoice: peerChoice) {
                // Every subscriber of the chat (its bar, its history) may write the same choice; the writes are idempotent.
                let _ = updateChatTranslationPeerChoice(engine: context.engine, peerId: peerId, choice: migratedChoice).start()
            }
            return effectiveChatTranslationState(state, peerChoice: peerChoice)
        }
    }
    |> distinctUntilChanged
}

private func chatTranslationLocationState(context: AccountContext, peerId: EnginePeer.Id, threadId: Int64?, forcePredict: Bool = false) -> Signal<ChatTranslationState?, NoError> {
    if peerId.id == EnginePeer.Id.Id._internalFromInt64Value(777000) {
        return .single(nil)
    }
    
    guard canTranslateChats(context: context) else {
        return .single(nil)
    }
    
    let loggingEnabled = context.sharedContext.immediateExperimentalUISettings.logLanguageRecognition
    
    if #available(iOS 12.0, *) {
        let baseLang = translationInterfaceLanguage(strings: context.sharedContext.currentPresentationData.with { $0 }.strings) // MARK: Regram

        return combineLatest(
            context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.translationSettings])
            |> map { sharedData -> TranslationSettings in
                return sharedData.entries[ApplicationSpecificSharedDataKeys.translationSettings]?.get(TranslationSettings.self) ?? TranslationSettings.defaultSettings
            },
            context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.AutoTranslateEnabled(id: peerId))
        )
        |> mapToSignal { settings, autoTranslateEnabled in
            if !settings.translateChats && !autoTranslateEnabled && !forcePredict {
                return .single(nil)
            }
            
            let dontTranslateLanguages = effectiveIgnoredTranslationLanguages(interfaceLanguage: baseLang, ignoredLanguages: settings.ignoredLanguages) // MARK: Regram
            
            return cachedChatTranslationState(engine: context.engine, peerId: peerId, threadId: threadId)
            |> mapToSignal { cached in
                let currentTime = Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970)
                // MARK: Regram — old Chinese detections could guess a script from shared characters.
                if let cached, !cached.fromLang.hasPrefix("zh") || cached.detectionVersion == ChatTranslationState.currentDetectionVersion,
                   let timestamp = cached.timestamp, cached.baseLang == baseLang && currentTime - timestamp < 60 * 60 {
                    if !isIgnoredTranslationLanguage(cached.fromLang, ignoredLanguages: dontTranslateLanguages) || forcePredict {
                        return .single(cached)
                    } else {
                        return .single(nil)
                    }
                } else {
                    return .single(nil)
                    |> then(
                        context.account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: peerId, threadId: threadId), index: .upperBound, anchorIndex: .upperBound, count: 32, fixedCombinedReadStates: nil)
                        |> filter { messageHistoryView -> Bool in
                            return messageHistoryView.0.entries.count > 1
                        }
                        |> take(1)
                        |> map { messageHistoryView, _, _ -> ChatTranslationState? in
                            let messages = messageHistoryView.entries.map(\.message)
                            
                            if loggingEnabled {
                                Logger.shared.log("ChatTranslation", "Start language recognizing for \(peerId)")
                            }
                            var fromLangs: [String: Int] = [:]
                            var count = 0
                            for message in messages {
                                if message.effectivelyIncoming(context.account.peerId), message.text.count >= 10 {
                                    let summaryLanguage = (message.attributes.first(where: { $0 is SummarizationMessageAttribute }) as? SummarizationMessageAttribute).map { normalizeTranslationLanguage($0.fromLang) }
                                    if let fromLang = summaryLanguage, !fromLang.isEmpty, !fromLang.hasPrefix("zh") { // MARK: Regram
                                        if supportedTranslationLanguages.contains(fromLang) {
                                            fromLangs[fromLang] = (fromLangs[fromLang] ?? 0) + message.text.count
                                            count += 1
                                        }
                                    } else {
                                        var text = String(message.text.prefix(256))
                                        if var entities = message.textEntitiesAttribute?.entities.filter({ entity in
                                            switch entity.type {
                                            case .Pre, .Code, .Url, .Email, .Mention, .Hashtag, .BotCommand:
                                                return true
                                            default:
                                                return false
                                            }
                                        }) {
                                            entities = entities.sorted(by: { $0.range.lowerBound > $1.range.lowerBound })
                                            var ranges: [Range<String.Index>] = []
                                            for entity in entities {
                                                if entity.range.lowerBound > text.count || entity.range.upperBound > text.count {
                                                    continue
                                                }
                                                ranges.append(text.index(text.startIndex, offsetBy: entity.range.lowerBound) ..< text.index(text.startIndex, offsetBy: entity.range.upperBound))
                                            }
                                            for range in ranges {
                                                if range.upperBound < text.endIndex {
                                                    text.removeSubrange(range)
                                                }
                                            }
                                        }
                                        
                                        if message.text.count < 10 {
                                            continue
                                        }
                                        
                                        if let fromLang = recognizedTranslationLanguage(in: text, supportedLanguages: supportedTranslationLanguages) { // MARK: Regram
                                            if loggingEnabled && !["en", "ru"].contains(fromLang) && !isIgnoredTranslationLanguage(fromLang, ignoredLanguages: dontTranslateLanguages) {
                                                Logger.shared.log("ChatTranslation", "\(text)")
                                                Logger.shared.log("ChatTranslation", "Recognized as: \(fromLang)")
                                            }
                                            fromLangs[fromLang] = (fromLangs[fromLang] ?? 0) + message.text.count
                                            count += 1
                                        }
                                    }
                                }
                                if count >= 16 {
                                    break
                                }
                            }
                                                        
                            // MARK: Regram — count shared characters towards Chinese without using them to choose a script.
                            let simplifiedCount = fromLangs.removeValue(forKey: "zh-hans") ?? 0
                            let traditionalCount = fromLangs.removeValue(forKey: "zh-hant") ?? 0
                            let chineseCount = simplifiedCount + traditionalCount + (fromLangs.removeValue(forKey: "zh") ?? 0)
                            if chineseCount > 0 {
                                let script: String
                                if simplifiedCount > traditionalCount {
                                    script = "zh-hans"
                                } else if traditionalCount > simplifiedCount {
                                    script = "zh-hant"
                                } else {
                                    script = "zh"
                                }
                                fromLangs[script] = chineseCount
                            }
                            var mostFrequent: (String, Int)?
                            for (lang, count) in fromLangs {
                                if let current = mostFrequent {
                                    if count > current.1 {
                                        mostFrequent = (lang, count)
                                    }
                                } else {
                                    mostFrequent = (lang, count)
                                }
                            }
                            let fromLang = mostFrequent?.0 ?? ""
                            if loggingEnabled {
                                Logger.shared.log("ChatTranslation", "Ended with: \(fromLang)")
                            }
                            
                            let isEnabled: Bool
                            if let currentIsEnabled = cached?.isEnabled {
                                isEnabled = currentIsEnabled
                            } else if autoTranslateEnabled {
                                isEnabled = true
                            } else {
                                isEnabled = false
                            }
                            
                            let state = ChatTranslationState(
                                baseLang: baseLang,
                                fromLang: fromLang,
                                timestamp: currentTime,
                                toLang: cached?.toLang,
                                isEnabled: isEnabled
                            )
                            let _ = updateChatTranslationState(engine: context.engine, peerId: peerId, threadId: threadId, state: state).start()
                            if !isIgnoredTranslationLanguage(fromLang, ignoredLanguages: dontTranslateLanguages) || forcePredict {
                                return state
                            } else {
                                return nil
                            }
                        }
                    )
                }
            }
        }
    } else {
        return .single(nil)
    }
}
