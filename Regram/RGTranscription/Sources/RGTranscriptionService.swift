// MARK: Regram — custom transcription; adapted from the Nagram reference.
import AccountContext
import AppBundle
import Foundation
import LocalAudioTranscription
import RGSimpleSettings
import RGStrings
import SwiftSignalKit
import TelegramCore

public enum RGTranscriptionState: Equatable {
    case inProgress
    case completed
    case failed(String)
}

public final class RGTranscriptionService {
    public static let shared = RGTranscriptionService()
    /// Both client providers use the shared download, cancellation and persistence lifecycle.
    public static var isEnabled: Bool { RGSimpleSettings.shared.transcriptionBackendEnum != .default }

    private struct Key: Hashable {
        let accountId: AccountRecordId
        let messageId: EngineMessage.Id
    }

    private final class Job {
        let context: AccountContext
        let key: Key
        let requestId = Int64.random(in: 1 ... Int64.max)
        let state = ValuePromise<RGTranscriptionState>(.inProgress)
        let work = MetaDisposable()
        let lifecycle = DisposableSet()
        var source: AudioTranscriptionMessageAttribute.Source = .telegram
        var finishing = false
        init(context: AccountContext, key: Key) { self.context = context; self.key = key }
        deinit { self.work.dispose(); self.lifecycle.dispose() }
    }

    // Accessed only on the main queue. Cell subscriptions do not own the request.
    private var jobs: [Key: Job] = [:]
    private init() {}

    public func isTranscribing(context: AccountContext, messageId: EngineMessage.Id) -> Bool {
        assert(Queue.mainQueue().isCurrent())
        return self.jobs[Key(accountId: context.account.id, messageId: messageId)] != nil
    }

    public func transcribe(context: AccountContext, messageId: EngineMessage.Id, force: Bool = false) -> Signal<RGTranscriptionState, NoError> {
        return Signal { subscriber in
            let observation = MetaDisposable()
            Queue.mainQueue().async {
                let key = Key(accountId: context.account.id, messageId: messageId)
                let job: Job
                let isNew: Bool
                if let current = self.jobs[key] {
                    job = current
                    isNew = false
                } else {
                    job = Job(context: context, key: key)
                    self.jobs[key] = job
                    isNew = true
                }
                observation.set(job.state.get().start(next: { state in
                    subscriber.putNext(state)
                    if state != .inProgress { subscriber.putCompletion() }
                }))
                if isNew { self.start(job: job, force: force) }
            }
            return observation
        }
    }

    public func cancel(context: AccountContext, messageId: EngineMessage.Id) {
        Queue.mainQueue().async {
            if let job = self.jobs[Key(accountId: context.account.id, messageId: messageId)] {
                self.fail(job: job, error: .cancelled)
            }
        }
    }

    public func test(configuration: RGSTTConfiguration) -> Signal<String, RGTranscriptionError> {
        guard let path = getAppBundle().path(forResource: "RGSTTTest", ofType: "m4a") else {
            return .fail(.invalidAudio)
        }
        return rgPrepareTranscriptionAudio(path: path)
        |> mapToSignal { audio in
            return RGOpenAITranscriptionProvider.transcribe(configuration: configuration, audioURL: audio.url)
            |> afterDisposed { withExtendedLifetime(audio) {} }
        }
        |> timeout(180, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.timeout))
    }

    private func start(job: Job, force: Bool) {
        let context = job.context
        let messageId = job.key.messageId
        let backend = RGSimpleSettings.shared.transcriptionBackendEnum
        let external = backend == .openAICompatible
        let local = backend == .apple
        job.source = external ? .external : (local ? .local : .telegram)
        let configuration: RGSTTConfiguration?
        do {
            configuration = external ? try RGSTTConfiguration.current() : nil
        } catch {
            self.finish(job: job, state: .failed(self.errorText(error, context: context)))
            return
        }

        let signal: Signal<Void, RGTranscriptionError> = context.engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
        |> castError(RGTranscriptionError.self)
        |> mapToSignal { message -> Signal<Void, RGTranscriptionError> in
            guard let message, message.id.namespace == Namespaces.Message.Cloud,
                  message.id.peerId.namespace != Namespaces.Peer.SecretChat,
                  message._asMessage().minAutoremoveOrClearTimeout != viewOnceTimeout,
                  let file = message.media.first(where: { ($0 as? TelegramMediaFile).map { $0.isVoice || $0.isInstantVideo } ?? false }) as? TelegramMediaFile else {
                return .fail(.invalidAudio)
            }
            if !force, let attribute = message.attributes.first(where: { $0 is AudioTranscriptionMessageAttribute }) as? AudioTranscriptionMessageAttribute, !attribute.isPending, !attribute.text.isEmpty {
                return .single(())
            }
            if !external && !local {
                // Telegram remains authoritative for Premium, boost and trial eligibility.
                return context.engine.messages.transcribeAudio(messageId: messageId)
                |> castError(RGTranscriptionError.self)
                |> mapToSignal { result -> Signal<Void, RGTranscriptionError> in
                    switch result {
                    case .success: return .single(())
                    case .error: return .fail(.configuration(context.sharedContext.currentPresentationData.with { $0 }.strings.Message_AudioTranscription_ErrorEmpty))
                    }
                }
            }
            let begin = external
                ? context.engine.messages.beginExternalAudioTranscription(messageId: messageId, requestId: job.requestId)
                : context.engine.messages.beginLocalAudioTranscription(messageId: messageId, requestId: job.requestId)
            return begin
            |> castError(RGTranscriptionError.self)
            |> mapToSignal { started -> Signal<String, RGTranscriptionError> in
                guard started else { return .fail(.cancelled) }
                return self.download(context: context, message: message, file: file)
            }
            |> mapToSignal { path in rgPrepareTranscriptionAudio(path: path) }
            |> mapToSignal { audio -> Signal<String, RGTranscriptionError> in
                let recognition: Signal<String, RGTranscriptionError>
                if let configuration {
                    recognition = RGOpenAITranscriptionProvider.transcribe(configuration: configuration, audioURL: audio.url)
                } else {
                    recognition = transcribeAudio(path: audio.url.path, appLocale: context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode)
                    |> castError(RGTranscriptionError.self)
                    |> mapToSignal { result -> Signal<String, RGTranscriptionError> in
                        guard let result else { return .fail(.noSpeech) }
                        guard result.isFinal else { return .complete() }
                        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .fail(.noSpeech) }
                        return .single(result.text)
                    }
                    |> take(1)
                }
                return Signal { subscriber in
                    let disposable = recognition.start(next: subscriber.putNext, error: subscriber.putError, completed: subscriber.putCompletion)
                    return ActionDisposable {
                        disposable.dispose()
                        withExtendedLifetime(audio) {}
                    }
                }
            }
            |> mapToSignal { text -> Signal<Void, RGTranscriptionError> in
                if external {
                    return context.engine.messages.storeExternalAudioTranscription(messageId: messageId, requestId: job.requestId, text: text, error: nil)
                    |> castError(RGTranscriptionError.self)
                    |> mapToSignal { stored in stored ? .single(()) : .fail(.cancelled) }
                } else {
                    return context.engine.messages.storeLocalAudioTranscription(messageId: messageId, requestId: job.requestId, text: text, isFinal: true, error: nil)
                    |> castError(RGTranscriptionError.self)
                    |> mapToSignal { stored in stored ? .single(()) : .fail(.cancelled) }
                }
            }
        }
        |> timeout(300, queue: Queue.mainQueue(), alternate: .fail(.timeout))
        |> deliverOnMainQueue

        // Install the holder first: Signal.start may synchronously reenter fail() or finish().
        let work = MetaDisposable()
        job.work.set(work)
        work.set(signal.start(next: { _ in
            self.finish(job: job, state: .completed)
        }, error: { error in
            self.fail(job: job, error: error)
        }, completed: {
            // An empty recognition result must not leave a job alive after its timeout was disposed.
            self.fail(job: job, error: .noSpeech)
        }))
        if self.jobs[job.key] === job {
            job.lifecycle.add((context.sharedContext.applicationBindings.applicationInForeground
            |> filter { !$0 }
            |> take(1)
            |> deliverOnMainQueue).start(next: { _ in self.fail(job: job, error: .cancelled) }))
            job.lifecycle.add((context.sharedContext.activeAccountsWithInfo
            |> filter { value in !value.accounts.contains(where: { $0.account.id == job.key.accountId }) }
            |> take(1)
            |> deliverOnMainQueue).start(next: { _ in self.fail(job: job, error: .cancelled) }))
        }
    }

    private func download(context: AccountContext, message: EngineMessage, file: TelegramMediaFile) -> Signal<String, RGTranscriptionError> {
        return Signal { subscriber in
            let disposables = DisposableSet()
            let reference = FileMediaReference.message(message: MessageReference(message._asMessage()), media: file)
            disposables.add(context.engine.resources.fetch(reference: reference.resourceReference(file.resource), userLocation: .peer(message.id.peerId), userContentType: MediaResourceUserContentType(file: file)).start(error: { _ in subscriber.putError(.download) }))
            disposables.add((context.engine.resources.data(resource: EngineMediaResource(file.resource), waitUntilFetchStatus: true)
            |> filter { $0.isComplete }
            |> take(1)).start(next: { data in
                subscriber.putNext(data.path)
                subscriber.putCompletion()
            }))
            return disposables
        }
    }

    private func fail(job: Job, error: RGTranscriptionError) {
        guard self.jobs[job.key] === job, !job.finishing else { return }
        job.finishing = true
        job.work.set(nil)
        job.lifecycle.dispose()
        let stored: Signal<Never, NoError>
        switch job.source {
        case .external:
            stored = job.context.engine.messages.storeExternalAudioTranscription(messageId: job.key.messageId, requestId: job.requestId, text: "", error: .generic) |> ignoreValues
        case .local:
            stored = job.context.engine.messages.storeLocallyTranscribedAudio(messageId: job.key.messageId, text: "", isFinal: true, error: .generic, requestId: job.requestId)
        default:
            stored = .complete()
        }
        job.work.set((stored |> deliverOnMainQueue).start(completed: {
            self.finish(job: job, state: .failed(self.errorText(error, context: job.context)))
        }))
    }

    private func errorText(_ error: Error, context: AccountContext) -> String {
        let language = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        if let error = error as? RGSTTConfigurationError {
            return i18n(error.localizationKey, language)
        }
        if let error = error as? RGSTTKeychainError {
            return "\(i18n("RG.STT.Error.Keychain", language)) (\(error.status))"
        }
        guard let error = error as? RGTranscriptionError else {
            return error.localizedDescription
        }
        let key: String
        switch error {
        case .download: key = "RG.STT.Error.Download"
        case .invalidAudio: key = "RG.STT.Error.InvalidAudio"
        case .fileTooLarge: key = "RG.STT.Error.FileTooLarge"
        case .cancelled: key = "RG.STT.Error.Cancelled"
        case .timeout: key = "RG.STT.Error.Timeout"
        case .invalidResponse: key = "RG.STT.Error.InvalidResponse"
        case .noSpeech: key = "RG.STT.Error.NoSpeech"
        case .configuration, .http, .network: return error.localizedDescription
        }
        return i18n(key, language)
    }

    private func finish(job: Job, state: RGTranscriptionState) {
        guard self.jobs[job.key] === job else { return }
        self.jobs.removeValue(forKey: job.key)
        job.work.dispose()
        job.lifecycle.dispose()
        job.state.set(state)
    }
}

// MARK: Regram — switching providers updates visible voice and video message controls.
public func rgTranscriptionProviderSignal() -> Signal<RGSimpleSettings.TranscriptionBackend, NoError> {
    return Signal { subscriber in
        subscriber.putNext(RGSimpleSettings.shared.transcriptionBackendEnum)
        let names: [Notification.Name] = [UserDefaults.didChangeNotification, RGSimpleSettings.sttSettingsDidChangeNotification]
        let observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                subscriber.putNext(RGSimpleSettings.shared.transcriptionBackendEnum)
            }
        }
        return ActionDisposable { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    } |> distinctUntilChanged
}
