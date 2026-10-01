import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramUIPreferences
import AccountContext
import PhotoResources
import UniversalMediaPlayer
import ChatMessageInteractiveMediaNode
// MARK: Regram
import RGSimpleSettings

private final class PrefetchMediaContext {
    let fetchDisposable = MetaDisposable()
    // MARK: Regram — validate a reused task and cancel its pending removal timer.
    let resourceId: String
    let mode: Int
    var removalTimer: SwiftSignalKit.Timer?

    init(resourceId: String, mode: Int) {
        self.resourceId = resourceId
        self.mode = mode
    }
}

// MARK: Regram — ignore equivalent list emissions, but keep reference/version changes.
private struct RGChatPrefetchInput: Equatable {
    let messageId: MessageId
    let stableVersion: UInt32
    let mediaId: MediaId?
    let resourceId: String?
}

private func rgPrefetchResource(_ media: Media) -> MediaResource? {
    if let image = media as? TelegramMediaImage { return largestRepresentationForPhoto(image)?.resource }
    if let file = media as? TelegramMediaFile { return file.resource }
    return nil
}

struct InChatPrefetchOptions: Equatable {
    let networkType: MediaAutoDownloadNetworkType
    let peerType: MediaAutoDownloadPeerType
}

final class InChatPrefetchManager {
    private let context: AccountContext
    private var settings: MediaAutoDownloadSettings
    private var options: InChatPrefetchOptions?
    
    private var messages: [(Message, Media)] = []
    private var directionIsToLater: Bool = true
    
    private var contexts: [MediaId: PrefetchMediaContext] = [:]
    // MARK: Regram
    private let rgPriorityOwner = Int64.random(in: Int64.min ... Int64.max)
    private var rgVisibleResourceIds: [String] = []
    private var rgInput: [RGChatPrefetchInput]?
    private var rgExperimentEnabled = RGSimpleSettings.shared.mediaLoadingExperiment
    private var rgIsActive = false
    private var rgRetention = RGMediaPreloadRetention<MediaId>()
    private var rgSettingsObserver: NSObjectProtocol?
    
    init(context: AccountContext) {
        self.context = context
        self.settings = context.sharedContext.currentAutomaticMediaDownloadSettings
        // MARK: Regram — switching the experiment flushes timers and stale requests.
        self.rgSettingsObserver = NotificationCenter.default.addObserver(forName: RGMediaLoadingPolicy.settingsChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.rgExperimentEnabled = RGSimpleSettings.shared.mediaLoadingExperiment
            self.rgInput = nil
            self.rgDisposeAll()
            self.update()
        }
    }
    
    deinit {
        // MARK: Regram
        if let observer = self.rgSettingsObserver { NotificationCenter.default.removeObserver(observer) }
        self.context.fetchManager.rgSetChatMediaPriority(owner: self.rgPriorityOwner, visibleResourceIds: [], preloadResourceIds: [])
        for (_, context) in self.contexts {
            context.removalTimer?.invalidate()
            context.fetchDisposable.dispose()
        }
    }
    
    func updateAutoDownloadSettings(_ settings: MediaAutoDownloadSettings) {
        if self.settings != settings {
            self.settings = settings
            // MARK: Regram — new permissions/limits must also apply to retained tasks.
            if self.rgExperimentEnabled { self.rgDisposeAll() }
            self.update()
        }
    }
    
    func updateOptions(_ options: InChatPrefetchOptions) {
        if self.options != options {
            self.options = options
            // MARK: Regram — never retain a Wi-Fi request across a cellular policy change.
            if self.rgExperimentEnabled { self.rgDisposeAll() }
            self.update()
        }
    }
    
    func updateMessages(_ messages: [(Message, Media)], directionIsToLater: Bool) {
        // MARK: Regram
        if self.rgExperimentEnabled {
            let input = messages.map { message, media in
                RGChatPrefetchInput(messageId: message.id, stableVersion: message.stableVersion, mediaId: media.id, resourceId: rgPrefetchResource(media)?.id.stringRepresentation)
            }
            if self.rgInput == input && self.directionIsToLater == directionIsToLater { return }
            self.rgInput = input
        }
        self.messages = messages
        self.directionIsToLater = directionIsToLater
        self.update()
    }
    
    private func update() {
        // MARK: Regram — hidden chats do not keep the experiment's prefetch alive.
        if self.rgExperimentEnabled && !self.rgIsActive {
            self.rgDisposeAll()
            self.rgPublishPriorities()
            return
        }
        guard let options = self.options else {
            return
        }
        
        var validIds = Set<MediaId>()
        for (message, media) in self.messages {
            guard let id = media.id else {
                continue
            }
            if validIds.contains(id) {
                continue
            }
            
            var mediaResource: MediaResource?
            
            var automaticDownload: InteractiveMediaNodeAutodownloadMode = .none
            
            if let telegramImage = media as? TelegramMediaImage {
                mediaResource = largestRepresentationForPhoto(telegramImage)?.resource
                if shouldDownloadMediaAutomatically(settings: self.settings, peerType: options.peerType, networkType: options.networkType, authorPeerId: nil, contactsPeerIds: [], media: telegramImage) {
                    automaticDownload = .full
                }
            } else if let telegramFile = media as? TelegramMediaFile {
                mediaResource = telegramFile.resource
                if shouldDownloadMediaAutomatically(settings: self.settings, peerType: options.peerType, networkType: options.networkType, authorPeerId: nil, contactsPeerIds: [], media: telegramFile) {
                    automaticDownload = .full
                } else if shouldPredownloadMedia(settings: self.settings, peerType: options.peerType, networkType: options.networkType, media: telegramFile) {
                    automaticDownload = .prefetch
                }
            }
            
            if case .none = automaticDownload {
                continue
            }
            guard let resource = mediaResource else {
                continue
            }
            
            validIds.insert(id)
            // MARK: Regram
            let mode: Int
            if case .full = automaticDownload { mode = 0 } else { mode = 1 }
            if self.rgExperimentEnabled, let current = self.contexts[id], current.resourceId != resource.id.stringRepresentation || current.mode != mode {
                self.rgRemoveContext(id)
            }
            let context: PrefetchMediaContext
            if let current = self.contexts[id] {
                context = current
                // MARK: Regram — rescue the original request instead of restarting it.
                self.rgRetention.rescue(id)
                current.removalTimer?.invalidate()
                current.removalTimer = nil
            } else {
                context = PrefetchMediaContext(resourceId: resource.id.stringRepresentation, mode: mode)
                self.contexts[id] = context
                
                let priority: FetchManagerPriority = .foregroundPrefetch(direction: self.directionIsToLater ? .toLater : .toEarlier, localOrder: message.index)
                
                if case .full = automaticDownload {
                    if let image = media as? TelegramMediaImage {
                        context.fetchDisposable.set(messageMediaImageInteractiveFetched(fetchManager: self.context.fetchManager, messageId: message.id, messageReference: MessageReference(message), image: image, resource: resource, userInitiated: false, priority: priority, storeToDownloadsPeerId: nil).startStrict())
                    } else if let _ = media as? TelegramMediaWebFile {
                        //strongSelf.fetchDisposable.set(chatMessageWebFileInteractiveFetched(account: context.account, image: image).startStrict())
                    } else if let file = media as? TelegramMediaFile {
                        let fetchSignal = messageMediaFileInteractiveFetched(fetchManager: self.context.fetchManager, messageId: message.id, messageReference: MessageReference(message), file: file, userInitiated: false, priority: priority)
                        context.fetchDisposable.set(fetchSignal.startStrict())
                    }
                } else if case .prefetch = automaticDownload, message.id.peerId.namespace != Namespaces.Peer.SecretChat {
                    if let file = media as? TelegramMediaFile, let _ = file.size {
                        context.fetchDisposable.set(preloadVideoResource(postbox: self.context.account.postbox, userLocation: .peer(message.id.peerId), userContentType: MediaResourceUserContentType(file: file), resourceReference: FileMediaReference.message(message: MessageReference(message), media: file).resourceReference(file.resource), duration: 4.0).startStrict())
                    }
                }
            }
        }
        var removeIds: [MediaId] = []
        for key in self.contexts.keys {
            if !validIds.contains(key) {
                removeIds.append(key)
            }
        }
        for id in removeIds {
            // MARK: Regram — a short, bounded grace window smooths reverse scrolling.
            if self.rgExperimentEnabled {
                self.rgDeferRemoval(id)
            } else {
                self.rgRemoveContext(id)
            }
        }
        self.rgPublishPriorities()
    }

    // MARK: Regram
    func rgSetActive(_ value: Bool) {
        guard self.rgIsActive != value else { return }
        self.rgIsActive = value
        if self.rgExperimentEnabled {
            self.rgInput = nil
            self.update()
        }
    }

    func rgUpdateVisibleResources(_ resourceIds: [String]) {
        guard self.rgVisibleResourceIds != resourceIds else { return }
        self.rgVisibleResourceIds = resourceIds
        self.rgPublishPriorities()
    }

    private func rgPublishPriorities() {
        let enabled = self.rgExperimentEnabled && self.rgIsActive
        let preload = enabled ? self.messages.compactMap { rgPrefetchResource($0.1)?.id.stringRepresentation } : []
        self.context.fetchManager.rgSetChatMediaPriority(owner: self.rgPriorityOwner, visibleResourceIds: enabled ? self.rgVisibleResourceIds : [], preloadResourceIds: preload)
    }

    private func rgRemoveContext(_ id: MediaId) {
        self.rgRetention.rescue(id)
        if let current = self.contexts.removeValue(forKey: id) {
            current.removalTimer?.invalidate()
            current.fetchDisposable.dispose()
        }
    }

    private func rgDisposeAll() {
        for id in Array(self.contexts.keys) { self.rgRemoveContext(id) }
        self.rgRetention.reset()
        self.rgInput = nil
    }

    private func rgDeferRemoval(_ id: MediaId) {
        guard let current = self.contexts[id], self.rgRetention.pending[id] == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let removal = self.rgRetention.deferRemoval(id, now: now)
        for evicted in removal.evicted { self.rgRemoveContext(evicted) }
        let timer = SwiftSignalKit.Timer(timeout: RGMediaLoadingPolicy.removalGraceInterval, repeat: false, completion: { [weak self, weak current] in
            guard let self, let current, self.contexts[id] === current else { return }
            if self.rgRetention.expire(id, ticket: removal.ticket, now: ProcessInfo.processInfo.systemUptime) {
                self.rgRemoveContext(id)
            }
        }, queue: .mainQueue())
        current.removalTimer = timer
        timer.start()
    }
}
