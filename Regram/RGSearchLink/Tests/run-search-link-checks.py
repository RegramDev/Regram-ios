#!/usr/bin/env python3
"""Exercise the production search-link parser without accounts, UI or network requests."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
fixture = r'''
import Foundation
@main enum Checks {
    static func main() {
        func link(_ query: String) -> RGSearchLink? { rgFeatureSearchLink(query: query, appSpecificScheme: "regram") }
        let explicit = link("  https://t.me/example/123  ")!
        precondition(explicit.kind == .message && !explicit.isInferred && explicit.resolvableUrl == "https://t.me/example/123")
        let inferred = link("example/123")!
        precondition(inferred.kind == .message && inferred.isInferred && inferred.url == "https://t.me/example/123")
        precondition(link("c/12345/678")?.kind == .message)
        precondition(link("+AbcDef123456")?.kind == .invite)
        precondition(link("t.me/joinchat/AbcDef123456")?.kind == .invite)
        precondition(link("tg://resolve?domain=example&post=123")?.kind == .message)
        precondition(link("regram://resolve?domain=example&post=123")?.kind == .message)
        for query in ["", "ordinary search words", "example", "https://example.com/test", "https://t.me.evil.org/example/123", "javascript:alert(1)", "file:///tmp/test", "tg://user:password@resolve?domain=example", String(repeating: "a", count: 2049)] {
            precondition(link(query) == nil, "Must not infer a Telegram link: \(query.prefix(50))")
        }
        precondition(explicit.displayUrl == "t.me/example/123")
        print("Search link checks passed: explicit/inferred messages, invites, app aliases, normal searches, spoofed hosts, credentials and unsupported schemes.")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-search-link-') as temporary:
    work = Path(temporary)
    source = work / 'Checks.swift'; source.write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors', str(root/'Regram/RGSearchLink/Sources/RGSearchLink.swift'), str(source), '-o', str(work/'checks')], check=True)
    subprocess.run([str(work/'checks')], check=True)
