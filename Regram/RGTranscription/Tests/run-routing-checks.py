#!/usr/bin/env python3
"""Compile actual voice/video routing gates and provider signals with account-free inputs."""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
service = (ROOT / 'Regram/RGTranscription/Sources/RGTranscriptionService.swift').read_text()
settings = (ROOT / 'Regram/RGSimpleSettings/Sources/SimpleSettings.swift').read_text()
backend = re.search(r'public enum TranscriptionBackend:.*?\n    }', settings, re.S)[0]
enabled = re.search(r'public static var isEnabled: Bool \{[^\n]+', service)[0]
provider = service[service.index('public func rgTranscriptionProviderSignal()'):]
provider_flags = re.search(r'let backend = RGSimpleSettings.shared.transcriptionBackendEnum\n.*?\n        let local = [^\n]+', service, re.S)[0]
functions = []
for kind, node in [('voice', 'ChatMessageInteractiveFileNode'), ('video', 'ChatMessageInteractiveInstantVideoNode')]:
    source = (ROOT / f'submodules/TelegramUI/Components/Chat/{node}/Sources/{node}.swift').read_text()
    source = source[source.index('    private func transcribe()'):]
    custom = re.search(r'let useCustomTranscription = [^\n]+', source)[0]
    managed = re.search(r'let useManagedTranscription = [^\n]+', source)[0]
    gate = re.search(r'if (!useCustomTranscription && transcriptionText == nil[^\n]+) \{', source)[1]
    premium_gate = re.search(r'if (!useCustomTranscription && ![^,\n]+), case \.inProgress', source)[1]
    guard = re.search(r'if useManagedTranscription \{\s*(guard .*?\n            })', source, re.S)[1]
    guard = guard.replace('return\n', 'return false\n').replace('self.media?', 'media?')
    functions.append(f'''
func {kind}Route(_ clientTranscription: Transcript?, _ premium: Bool, _ boost: Bool, _ hasText: Bool) -> (Bool, Bool, Bool) {{
    let context = Context(isPremium: premium)
    let item = Item(context: context, boost: boost)
    let arguments = item
    _ = arguments
    let transcriptionText: String? = hasText ? "cached" : nil
    {custom}
    {managed}
    return (useManagedTranscription, {gate}, {premium_gate})
}}
func {kind}Eligible(secret: Bool, once: Bool, preview: Bool, audio: Bool) -> Bool {{
    let message = Message(secret: secret, once: once)
    let item = Item(message: message, preview: preview, audio: audio)
    let arguments = item
    let media: Media? = item.file
    _ = (arguments, media)
    let useManagedTranscription = true
    if useManagedTranscription {{ {guard} }}
    return true
}}
''')

fixture = '''
import Foundation
import SwiftSignalKit
public final class RGSimpleSettings {
    BACKEND
    static let shared = RGSimpleSettings()
    static let sttSettingsDidChangeNotification = Notification.Name("routing-test-provider")
    var transcriptionBackendEnum: TranscriptionBackend = .default
}
enum RGTranscriptionService { ENABLED }
struct Transcript {
    enum Source: CaseIterable { case telegram, local, external }
    let requestId: Int64?
    let source: Source
}
enum Namespaces {
    enum Message { static let Cloud = 1 }
    enum Peer { static let SecretChat = 2 }
}
let viewOnceTimeout: Int32 = 1
struct Message {
    struct Id { struct PeerId { let namespace: Int }; let namespace = 1; let peerId: PeerId }
    let id: Id
    let minAutoremoveOrClearTimeout: Int32?
    init(secret: Bool = false, once: Bool = false) {
        id = Id(peerId: Id.PeerId(namespace: secret ? 2 : 0))
        minAutoremoveOrClearTimeout = once ? 1 : nil
    }
}
struct Context { let isPremium: Bool }
struct Media { let isVoice: Bool; let isInstantVideo: Bool }
struct Item {
    struct AssociatedData { struct Boost { let providedByGroupBoost: Bool }; let alwaysDisplayTranscribeButton: Boost }
    struct PresentationData { let isPreview: Bool }
    let context: Context
    let associatedData: AssociatedData
    let message: Message
    let presentationData: PresentationData
    let file: Media
    init(context: Context = Context(isPremium: false), boost: Bool = false, message: Message = Message(), preview: Bool = false, audio: Bool = true) {
        self.context = context
        associatedData = AssociatedData(alwaysDisplayTranscribeButton: .init(providedByGroupBoost: boost))
        self.message = message
        presentationData = PresentationData(isPreview: preview)
        file = Media(isVoice: audio, isInstantVideo: audio)
    }
}
FUNCTIONS
PROVIDER
@main enum Tests {
    static func main() {
        var count = 0
        for backend in RGSimpleSettings.TranscriptionBackend.allCases {
            RGSimpleSettings.shared.transcriptionBackendEnum = backend
            PROVIDER_FLAGS
            precondition(external == (backend == .openAICompatible))
            precondition(local == (backend == .apple))
            for source in Transcript.Source.allCases { for request in [Int64?.none, 42] {
                for premium in [false, true] { for boost in [false, true] { for hasText in [false, true] {
                    let transcript = Transcript(requestId: request, source: source)
                    for route in [voiceRoute, videoRoute] {
                        let actual = route(transcript, premium, boost, hasText)
                        precondition(actual.0 == (backend != .default || (request != nil && source != .telegram)))
                        precondition(actual.1 == (backend == .default && !hasText && !boost))
                        precondition(actual.2 == (backend == .default && !premium))
                        count += 1
                    }
                }}}
            }}
            for secret in [false, true] { for once in [false, true] { for preview in [false, true] { for audio in [false, true] {
                for eligible in [voiceEligible, videoEligible] {
                    precondition(eligible(secret, once, preview, audio) == (!secret && !once && !preview && audio))
                    count += 1
                }
            }}}}
        }
        RGSimpleSettings.shared.transcriptionBackendEnum = .default
        var observed: [RGSimpleSettings.TranscriptionBackend] = []
        let disposable = rgTranscriptionProviderSignal().start(next: { observed.append($0) })
        for value in [RGSimpleSettings.TranscriptionBackend.apple, .openAICompatible, .openAICompatible, .apple, .default] {
            RGSimpleSettings.shared.transcriptionBackendEnum = value
            NotificationCenter.default.post(name: RGSimpleSettings.sttSettingsDidChangeNotification, object: nil)
        }
        precondition(observed == [.default, .apple, .openAICompatible, .apple, .default])
        disposable.dispose()
        RGSimpleSettings.shared.transcriptionBackendEnum = .apple
        NotificationCenter.default.post(name: RGSimpleSettings.sttSettingsDidChangeNotification, object: nil)
        precondition(observed.count == 5)
        print("Production transcription routing checks passed: \\(count) scenarios; all provider transitions and signal disposal")
    }
}
'''
replacements = {'BACKEND': backend, 'ENABLED': enabled, 'FUNCTIONS': '\n'.join(functions), 'PROVIDER': provider, 'PROVIDER_FLAGS': provider_flags}
for token in sorted(replacements, key=len, reverse=True):
    value = replacements[token]
    fixture = fixture.replace(token, value)

with tempfile.TemporaryDirectory(prefix='regram-transcription-routing-') as directory:
    work = Path(directory)
    signal_sources = sorted((ROOT / 'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'))
    signal_sources += sorted((ROOT / 'Regram/RGSwiftSignalKit/Sources').glob('*.swift'))
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-emit-library', '-emit-module', '-module-name', 'SwiftSignalKit', *map(str, signal_sources), '-emit-module-path', str(work / 'SwiftSignalKit.swiftmodule'), '-o', str(work / 'libSwiftSignalKit.dylib')], check=True)
    (work / 'Tests.swift').write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-parse-as-library', '-I', str(work), '-L', str(work), '-lSwiftSignalKit', '-Xlinker', '-rpath', '-Xlinker', str(work), str(work / 'Tests.swift'), '-o', str(work / 'tests')], check=True)
    subprocess.run([str(work / 'tests')], check=True, timeout=30)
