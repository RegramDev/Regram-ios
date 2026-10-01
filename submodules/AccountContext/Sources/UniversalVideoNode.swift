import Foundation
import UIKit
import AsyncDisplayKit
import Postbox
import SwiftSignalKit
import TelegramCore
import Display
import TelegramAudio
import UniversalMediaPlayer
import AVFoundation
import RangeSet
// MARK: Regram
import RGSimpleSettings

public enum UniversalVideoContentVideoQuality: Equatable {
    case auto
    case quality(Int)
}

public protocol UniversalVideoContentNode: AnyObject {
    var ready: Signal<Void, NoError> { get }
    // MARK: Regram — decoded frame readiness is separate from thumbnail readiness.
    var rgDisplayReady: Signal<Void, NoError> { get }
    var rgStreamingOwnerId: Int64? { get }
    func rgSetRetainedLoadingSuspended(_ suspended: Bool)
    var status: Signal<MediaPlayerStatus, NoError> { get }
    var bufferingStatus: Signal<(RangeSet<Int64>, Int64)?, NoError> { get }
    var isNativePictureInPictureActive: Signal<Bool, NoError> { get }
        
    func updateLayout(size: CGSize, actualSize: CGSize, transition: ContainedViewLayoutTransition)
    
    func play()
    func pause()
    func togglePlayPause()
    func setSoundEnabled(_ value: Bool)
    func seek(_ timestamp: Double)
    func playOnceWithSound(playAndRecord: Bool, seek: MediaPlayerSeek, actionAtEnd: MediaPlayerPlayOnceWithSoundActionAtEnd)
    func setSoundMuted(soundMuted: Bool)
    func continueWithOverridingAmbientMode(isAmbient: Bool)
    func setForceAudioToSpeaker(_ forceAudioToSpeaker: Bool)
    func continuePlayingWithoutSound(actionAtEnd: MediaPlayerPlayOnceWithSoundActionAtEnd)
    func setContinuePlayingWithoutSoundOnLostAudioSession(_ value: Bool)
    func setBaseRate(_ baseRate: Double)
    func setVideoQuality(_ videoQuality: UniversalVideoContentVideoQuality)
    func videoQualityState() -> (current: Int, preferred: UniversalVideoContentVideoQuality, available: [Int])?
    func videoQualityStateSignal() -> Signal<(current: Int, preferred: UniversalVideoContentVideoQuality, available: [Int])?, NoError>
    func addPlaybackCompleted(_ f: @escaping () -> Void) -> Int
    func removePlaybackCompleted(_ index: Int)
    func fetchControl(_ control: UniversalVideoNodeFetchControl)
    func notifyPlaybackControlsHidden(_ hidden: Bool)
    func setCanPlaybackWithoutHierarchy(_ canPlaybackWithoutHierarchy: Bool)
    func enterNativePictureInPicture() -> Bool
    func exitNativePictureInPicture()
    func setNativePictureInPictureIsActive(_ value: Bool)
}

// MARK: Regram — preserve the behavior of other player implementations.
public extension UniversalVideoContentNode {
    var rgDisplayReady: Signal<Void, NoError> { return self.ready }
    var rgStreamingOwnerId: Int64? { return nil }
    func rgSetRetainedLoadingSuspended(_ suspended: Bool) {
        if suspended { self.pause() }
    }
}

public protocol UniversalVideoContent {
    var id: AnyHashable { get }
    var dimensions: CGSize { get }
    var duration: Double { get }
    
    func makeContentNode(context: AccountContext, postbox: Postbox, audioSession: ManagedAudioSession) -> UniversalVideoContentNode & ASDisplayNode
    
    func isEqual(to other: UniversalVideoContent) -> Bool
}

public extension UniversalVideoContent {
    func isEqual(to other: UniversalVideoContent) -> Bool {
        return false
    }
}

public protocol UniversalVideoDecoration: AnyObject {
    var backgroundNode: ASDisplayNode? { get }
    var contentContainerNode: ASDisplayNode { get }
    var foregroundNode: ASDisplayNode? { get }
    
    func setStatus(_ status: Signal<MediaPlayerStatus?, NoError>)
    
    func updateContentNode(_ contentNode: (UniversalVideoContentNode & ASDisplayNode)?)
    func updateContentNodeSnapshot(_ snapshot: UIView?)
    func updateLayout(size: CGSize, actualSize: CGSize, transition: ContainedViewLayoutTransition)
    func tap()
}

public enum UniversalVideoPriority: Int32, Comparable {
    case minimal = 0
    case secondaryOverlay = 1
    case embedded = 2
    case gallery = 3
    case overlay = 4
    
    public static func <(lhs: UniversalVideoPriority, rhs: UniversalVideoPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

public enum UniversalVideoNodeFetchControl {
    case fetch
    case cancel
}

public final class UniversalVideoNode: ASDisplayNode {
    private let context: AccountContext
    private let postbox: Postbox
    private let audioSession: ManagedAudioSession
    private let manager: UniversalVideoManager
    private let content: UniversalVideoContent
    private let priority: UniversalVideoPriority
    public let decoration: UniversalVideoDecoration
    private let autoplay: Bool
    private let snapshotContentWhenGone: Bool
    
    private(set) var contentNode: (UniversalVideoContentNode & ASDisplayNode)?
    private var contentNodeId: Int32?
    
    private var playbackCompletedIndex: Int?
    private var contentRequestIndex: (AnyHashable, Int32)?
    // MARK: Regram
    private let rgGlobalQualityDisposable = MetaDisposable()
    private var rgQualitySettingsObserver: NSObjectProtocol?
    private var rgManualVideoQuality: UniversalVideoContentVideoQuality?
    
    public var playbackCompleted: (() -> Void)?
    
    public private(set) var ownsContentNode: Bool = false
    public var ownsContentNodeUpdated: ((Bool) -> Void)?
    
    public var duration: Double {
        return self.content.duration
    }
    
    private let _status = Promise<MediaPlayerStatus?>()
    public var status: Signal<MediaPlayerStatus?, NoError> {
        return self._status.get()
    }
    
    private let _bufferingStatus = Promise<(RangeSet<Int64>, Int64)?>()
    public var bufferingStatus: Signal<(RangeSet<Int64>, Int64)?, NoError> {
        return self._bufferingStatus.get()
    }
    
    private let _isNativePictureInPictureActive = Promise<Bool>()
    public var isNativePictureInPictureActive: Signal<Bool, NoError> {
        return self._isNativePictureInPictureActive.get()
    }
    
    private let _ready = Promise<Void>()
    public var ready: Signal<Void, NoError> {
        return self._ready.get()
    }

    // MARK: Regram
    private let rgDisplayReadyPromise = Promise<Void>()
    public var rgDisplayReady: Signal<Void, NoError> { return self.rgDisplayReadyPromise.get() }
    public var rgContentId: AnyHashable { return self.content.id }
    public var rgStreamingOwnerId: Int64? { return self.contentNode?.rgStreamingOwnerId }
    public var rgInlineAutoplaySessionId: Int64? {
        didSet {
            if let (id, index) = self.contentRequestIndex {
                self.manager.rgSetInlineVideoRetention(id: id, index: index, sessionId: self.rgInlineAutoplaySessionId)
            }
        }
    }
    
    public var canAttachContent: Bool = false {
        didSet {
            if self.canAttachContent != oldValue {
                if self.canAttachContent {
                    assert(self.contentRequestIndex == nil)
                    
                    let context = self.context
                    let content = self.content
                    let postbox = self.postbox
                    let audioSession = self.audioSession
                    self.contentRequestIndex = self.manager.attachUniversalVideoContent(content: self.content, priority: self.priority, create: {
                        return content.makeContentNode(context: context, postbox: postbox, audioSession: audioSession)
                    }, update: { [weak self] contentNodeAndFlags in
                        if let strongSelf = self {
                            strongSelf.updateContentNode(contentNodeAndFlags)
                        }
                    })
                    // MARK: Regram
                    if let (id, index) = self.contentRequestIndex, let sessionId = self.rgInlineAutoplaySessionId {
                        self.manager.rgSetInlineVideoRetention(id: id, index: index, sessionId: sessionId)
                    }
                } else {
                    assert(self.contentRequestIndex != nil)
                    if let (id, index) = self.contentRequestIndex {
                        self.contentRequestIndex = nil
                        self.manager.detachUniversalVideoContent(id: id, index: index)
                    }
                }
            }
        }
    }
    
    public var hasAttachedContext: Bool {
        return self.contentNode != nil
    }
    
    public init(context: AccountContext, postbox: Postbox, audioSession: ManagedAudioSession, manager: UniversalVideoManager, decoration: UniversalVideoDecoration, content: UniversalVideoContent, priority: UniversalVideoPriority, autoplay: Bool = false, snapshotContentWhenGone: Bool = false) {
        self.context = context
        self.postbox = postbox
        self.audioSession = audioSession
        self.manager = manager
        self.content = content
        self.priority = priority
        self.decoration = decoration
        self.autoplay = autoplay
        self.snapshotContentWhenGone = snapshotContentWhenGone
        
        super.init()
        // MARK: Regram — apply after qualities become available, including cold HLS.
        self.rgQualitySettingsObserver = NotificationCenter.default.addObserver(forName: RGVideoQualityPreference.settingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rgApplyGlobalVideoQuality(forceAutomatic: true)
        }
        
        self.playbackCompletedIndex = self.manager.addPlaybackCompleted(id: self.content.id, { [weak self] in
            self?.playbackCompleted?()
        })
        
        self._status.set(self.manager.statusSignal(content: self.content))
        self._bufferingStatus.set(self.manager.bufferingStatusSignal(content: self.content))
        self._isNativePictureInPictureActive.set(self.manager.isNativePictureInPictureActiveSignal(content: self.content))
        
        self.decoration.setStatus(self.status)
        
        if let backgroundNode = self.decoration.backgroundNode {
            self.addSubnode(backgroundNode)
        }
        
        self.addSubnode(self.decoration.contentContainerNode)
        
        if let foregroundNode = self.decoration.foregroundNode {
            self.addSubnode(foregroundNode)
        }
    }
    
    override public func didLoad() {
        super.didLoad()
        
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))
    }
    
    deinit {
        assert(Queue.mainQueue().isCurrent())
        self.rgGlobalQualityDisposable.dispose()
        if let observer = self.rgQualitySettingsObserver { NotificationCenter.default.removeObserver(observer) }
        
        if let playbackCompletedIndex = self.playbackCompletedIndex {
            self.manager.removePlaybackCompleted(id: self.content.id, index: playbackCompletedIndex)
        }
        
        if let (id, index) = self.contentRequestIndex {
            self.contentRequestIndex = nil
            self.manager.detachUniversalVideoContent(id: id, index: index)
        }
    }
    
    private func updateContentNode(_ contentNode: ((UniversalVideoContentNode & ASDisplayNode), Bool)?) {
        let previous = self.contentNode
        self.contentNode = contentNode?.0
        if previous !== contentNode?.0 {
            if let previous = previous, contentNode?.0 == nil && self.snapshotContentWhenGone {
                if let snapshotView = previous.view.snapshotView(afterScreenUpdates: false) {
                    self.decoration.updateContentNodeSnapshot(snapshotView)
                }
            }
            if let (contentNode, initiatedCreation) = contentNode {
                contentNode.layer.removeAllAnimations()
                self._ready.set(contentNode.ready)
                // MARK: Regram
                self.rgDisplayReadyPromise.set(contentNode.rgDisplayReady)
                self.rgApplyGlobalVideoQuality()
                if initiatedCreation && self.autoplay {
                    self.play()
                }
            }
            if contentNode?.0 != nil && self.snapshotContentWhenGone {
                self.decoration.updateContentNodeSnapshot(nil)
            }
            self.decoration.updateContentNode(contentNode?.0)
            
            let ownsContentNode = contentNode?.0 !== nil
            if self.ownsContentNode != ownsContentNode {
                self.ownsContentNode = ownsContentNode
                self.ownsContentNodeUpdated?(ownsContentNode)
            }
        }
        
        if contentNode == nil {
            self.rgGlobalQualityDisposable.set(nil)
            self._ready.set(.single(Void()))
            // MARK: Regram — detached content must not emit a thumbnail as a frame.
            self.rgDisplayReadyPromise.set(.never())
        }
    }
    
    public func updateLayout(size: CGSize, actualSize: CGSize? = nil, transition: ContainedViewLayoutTransition) {
        self.decoration.updateLayout(size: size, actualSize: actualSize ?? size, transition: transition)
    }
    
    public func play() {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.play()
            }
        })
    }
    
    public func pause() {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.pause()
            }
        })
    }
    
    public func togglePlayPause() {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.togglePlayPause()
            }
        })
    }
    
    public func setSoundEnabled(_ value: Bool) {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.setSoundEnabled(value)
            }
        })
    }
    
    public func seek(_ timestamp: Double) {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.seek(timestamp)
            }
        })
    }
    
    public func playOnceWithSound(playAndRecord: Bool, seek: MediaPlayerSeek = .start, actionAtEnd: MediaPlayerPlayOnceWithSoundActionAtEnd = .loopDisablingSound) {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.playOnceWithSound(playAndRecord: playAndRecord, seek: seek, actionAtEnd: actionAtEnd)
            }
        })
    }
    
    public func setSoundMuted(soundMuted: Bool) {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.setSoundMuted(soundMuted: soundMuted)
            }
        })
    }
    
    public func continueWithOverridingAmbientMode(isAmbient: Bool) {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.continueWithOverridingAmbientMode(isAmbient: isAmbient)
            }
        })
    }
    
    public func setContinuePlayingWithoutSoundOnLostAudioSession(_ value: Bool) {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.setContinuePlayingWithoutSoundOnLostAudioSession(value)
            }
        })
    }
    
    public func setForceAudioToSpeaker(_ forceAudioToSpeaker: Bool) {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.setForceAudioToSpeaker(forceAudioToSpeaker)
            }
        })
    }
    
    public func setBaseRate(_ baseRate: Double) {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.setBaseRate(baseRate)
            }
        })
    }
    
    public func setVideoQuality(_ videoQuality: UniversalVideoContentVideoQuality) {
        // MARK: Regram — a manual choice must not be replaced by a delayed default.
        self.rgManualVideoQuality = videoQuality
        self.rgGlobalQualityDisposable.set(nil)
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.setVideoQuality(videoQuality)
            }
        })
    }

    // MARK: Regram
    private func rgApplyGlobalVideoQuality(forceAutomatic: Bool = false) {
        self.rgGlobalQualityDisposable.set(nil)
        if forceAutomatic { self.rgManualVideoQuality = nil }
        guard let node = self.contentNode else { return }
        if let quality = self.rgManualVideoQuality {
            node.setVideoQuality(quality)
            return
        }
        let preference = RGVideoQualityPreference(rawValue: RGSimpleSettings.shared.defaultVideoQuality) ?? .automatic
        if preference == .automatic {
            if forceAutomatic { node.setVideoQuality(.auto) }
            return
        }
        self.rgGlobalQualityDisposable.set((node.videoQualityStateSignal()
        |> deliverOnMainQueue
        |> filter { ($0?.available.count ?? 0) > 1 }
        |> take(1)).start(next: { [weak self, weak node] state in
            guard let self, let node, self.contentNode === node, let state,
                  let quality = preference.selectedQuality(available: state.available) else { return }
            node.setVideoQuality(.quality(quality))
        }))
    }
    
    public func videoQualityState() -> (current: Int, preferred: UniversalVideoContentVideoQuality, available: [Int])? {
        var result: (current: Int, preferred: UniversalVideoContentVideoQuality, available: [Int])?
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode {
                result = contentNode.videoQualityState()
            }
        })
        return result
    }
    
    public func videoQualityStateSignal() -> Signal<(current: Int, preferred: UniversalVideoContentVideoQuality, available: [Int])?, NoError> {
        var result: Signal<(current: Int, preferred: UniversalVideoContentVideoQuality, available: [Int])?, NoError>?
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode {
                result = contentNode.videoQualityStateSignal()
            }
        })
        return result ?? .single(nil)
    }
    
    public func continuePlayingWithoutSound(actionAtEnd: MediaPlayerPlayOnceWithSoundActionAtEnd = .loopDisablingSound) {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.continuePlayingWithoutSound(actionAtEnd: actionAtEnd)
            }
        })
    }
    
    public func fetchControl(_ control: UniversalVideoNodeFetchControl) {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.fetchControl(control)
            }
        })
    }
    
    public func notifyPlaybackControlsHidden(_ hidden: Bool) {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.notifyPlaybackControlsHidden(hidden)
            }
        })
    }
    
    @objc private func tapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.decoration.tap()
        }
    }

    public func getVideoLayer() -> AVSampleBufferDisplayLayer? {
        guard let contentNode = self.contentNode else {
            return nil
        }

        func findVideoLayer(layer: CALayer) -> AVSampleBufferDisplayLayer? {
            if let layer = layer as? AVSampleBufferDisplayLayer {
                return layer
            }

            if let sublayers = layer.sublayers {
                for sublayer in sublayers {
                    if let result = findVideoLayer(layer: sublayer) {
                        return result
                    }
                }
            }

            return nil
        }

        return findVideoLayer(layer: contentNode.layer)
    }

    public func setCanPlaybackWithoutHierarchy(_ canPlaybackWithoutHierarchy: Bool) {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.setCanPlaybackWithoutHierarchy(canPlaybackWithoutHierarchy)
            }
        })
    }
    
    public func enterNativePictureInPicture() -> Bool {
        var result = false
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                result = contentNode.enterNativePictureInPicture()
            }
        })
        return result
    }
    
    public func exitNativePictureInPicture() {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.exitNativePictureInPicture()
            }
        })
    }
    
    public func setNativePictureInPictureIsActive(_ value: Bool) {
        self.manager.withUniversalVideoContent(id: self.content.id, { contentNode in
            if let contentNode = contentNode {
                contentNode.setNativePictureInPictureIsActive(value)
            }
        })
    }
}
