#!/usr/bin/env python3
"""Run the production username detector and nickname builder on macOS, without a simulator.
The Telegram entity scanner is unchanged; account/UI model adapters supply deterministic fixtures.
"""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = (root / 'submodules/TextFormat/Sources/GenerateTextEntities.swift').read_text()
parser = parser[:parser.index('public func generateChatInputTextEntities')]+parser[parser.index('public func generateTextEntities'):parser.index('public func addLocallyGeneratedEntities')]+parser[parser.index('public func parseTimecodeString'):]
parser = 'import Foundation\n' + '\n'.join(line for line in parser.splitlines() if not line.startswith('import '))
source = (root / 'submodules/TelegramUI/Sources/RGNicknameMentions.swift').read_text()
source = 'import Foundation\n' + source[source.index('func rgNicknameMentionText'):source.index('/// Debounce typing')]
fixtures = r'''
import Foundation
public typealias PeerId = Int64
public enum MessageTextEntityType {
    case Mention, Hashtag, BotCommand, Url, Email, PhoneNumber, Code, Bold, Italic, Spoiler
    case Pre(language: String?), TextUrl(url: String), TextMention(peerId: PeerId)
    case CustomEmoji, BlockQuote, Custom(type: Int32)
}
public struct MessageTextEntity { public var range: Range<Int>; public let type: MessageTextEntityType }
struct ChatTextInputState { let inputText: NSAttributedString; let selectionRange: Range<Int> }
enum ChatTextInputAttributes {
    static let textMention = NSAttributedString.Key("Attribute__TextMention")
    static let bold = NSAttributedString.Key("Attribute__Bold")
    static let monospace = NSAttributedString.Key("Attribute__Monospace")
    static let textUrl = NSAttributedString.Key("Attribute__TextUrl")
}
final class ChatTextInputTextMentionAttribute: NSObject {
    let peerId: PeerId
    init(peerId: PeerId) { self.peerId = peerId }
}
struct User { let firstName: String?; let lastName: String? }
enum EnginePeer {
    case user(User), channel
    var compactDisplayTitle: String { "Fallback" }
    var id: PeerId { 12345 }
}
final class RGSimpleSettings {
    static let shared = RGSimpleSettings()
    var mentionAsUserIdLink = true
}
func generateChatInputTextEntities(_ text: NSAttributedString) -> [MessageTextEntity] {
    var entities: [MessageTextEntity] = []
    text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
        for (key, _) in attributes {
            let type: MessageTextEntityType
            switch key {
            case ChatTextInputAttributes.bold: type = .Bold
            case ChatTextInputAttributes.monospace: type = .Code
            case ChatTextInputAttributes.textMention: type = .TextMention(peerId: 12345)
            case ChatTextInputAttributes.textUrl: type = .TextUrl(url: "https://example.com")
            default: continue
            }
            entities.append(MessageTextEntity(range: range.location..<NSMaxRange(range), type: type))
        }
    }
    return entities
}
'''
checks = r'''
@main enum LiveMentionInputChecks {
    private static func candidates(_ text: NSAttributedString, caret: Int? = nil) -> [RGMentionCandidate] {
        let offset = caret ?? text.length
        return rgMentionCandidates(state: ChatTextInputState(inputText: text, selectionRange: offset..<offset))
    }
    static func main() {
        let plain = NSAttributedString(string: "@someone")
        assert(candidates(plain).map(\.username) == ["someone"])
        let bold = NSAttributedString(string: "@someone", attributes: [ChatTextInputAttributes.bold: true])
        assert(candidates(bold).map(\.username) == ["someone"], "Formatting must not suppress detection")
        assert(candidates(NSAttributedString(string: "@someone", attributes: [ChatTextInputAttributes.monospace: true])).isEmpty)
        assert(candidates(NSAttributedString(string: "@someone", attributes: [ChatTextInputAttributes.textUrl: true])).isEmpty)
        assert(candidates(NSAttributedString(string: "@someone", attributes: [ChatTextInputAttributes.textMention: true])).isEmpty)
        assert(candidates(NSAttributedString(string: "test@someone.com")).isEmpty)
        assert(candidates(NSAttributedString(string: "https://example.com/@someone")).isEmpty)
        assert(candidates(NSAttributedString(string: "/command@somebot")).isEmpty)
        assert(candidates(plain, caret: 4).isEmpty, "Typing in the middle of a token must not trigger replacement")
        let mixed = NSAttributedString(string: "😀 中文 @Someone 和 @other_user")
        let found = candidates(mixed)
        assert(found.map(\.username) == ["someone", "other_user"])
        assert(found[0].range == (mixed.string as NSString).range(of: "@Someone"), "Ranges must use UTF-16")
        let nickname = rgNicknameMentionText(peer: .user(User(firstName: "测试", lastName: "昵称")), suffix: " ")!
        assert(nickname.string == "测试 昵称 ")
        assert((nickname.attribute(ChatTextInputAttributes.textMention, at: 0, effectiveRange: nil) as? ChatTextInputTextMentionAttribute)?.peerId == 12345)
        assert(nickname.attribute(ChatTextInputAttributes.textMention, at: nickname.length - 1, effectiveRange: nil) == nil, "Following text must not extend the mention")
        assert(rgNicknameMentionText(peer: .channel, suffix: " ") == nil)
        RGSimpleSettings.shared.mentionAsUserIdLink = false
        assert(rgNicknameMentionText(peer: .user(User(firstName: "Name", lastName: nil)), suffix: " ") == nil)
        print("Live mention input checks passed: usernames, bold spans, code/link exclusions, UTF-16 and native nickname attributes")
    }
}
'''.replace('\\.', '\\.')
with tempfile.TemporaryDirectory(prefix='regram-live-mention-tests-') as directory:
    path = Path(directory)
    (path / 'Models.swift').write_text(fixtures)
    (path / 'Scanner.swift').write_text(parser)
    (path / 'Mentions.swift').write_text(source + checks)
    compiler = subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip()
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    compile_result = subprocess.run([compiler, '-swift-version', '5', '-sdk', sdk, '-target', os.uname().machine + '-apple-macosx15.0'] + [str(path / name) for name in ['Models.swift', 'Scanner.swift', 'Mentions.swift']] + ['-o', str(path / 'checks')], capture_output=True, text=True)
    if compile_result.returncode:
        print(compile_result.stderr)
        raise SystemExit(compile_result.returncode)
    result = subprocess.run([str(path / 'checks')], capture_output=True, text=True)
    print(result.stdout, end='')
    if result.returncode:
        print(result.stderr)
        raise SystemExit(result.returncode)
