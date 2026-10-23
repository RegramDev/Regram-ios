#!/usr/bin/env python3
"""Check the exact text allowed across the automatic bot-query boundary."""
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[3]
fixture=r'''
import Foundation
@main enum Checks {
 static func main() {
  let url="https://x.com/example/status/123?ref=test"
  precondition(rgInlineBotQueryText("  "+url+"\n")==url)
  precondition(rgInlineBotQueryText("http://www.pixiv.net/artworks/123")=="http://www.pixiv.net/artworks/123")
  for value in ["private note "+url, url+"\nprivate draft", url+" another word", "tg://resolve?domain=example", "file:///tmp/image", "https://user:password@x.com/example/status/123", "javascript:alert(1)", "https://x.com/"+String(repeating:"a",count:2048)] {
   precondition(rgInlineBotQueryText(value)==nil, "Unexpected automatic query: \(value.prefix(60))")
  }
  print("Inline query checks passed: one normalized HTTP(S) link, unchanged query parameters, no surrounding draft text, credentials or oversized input.")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-inline-query-') as temporary:
 work=Path(temporary);source=work/'Checks.swift';source.write_text(fixture)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-swift-version','5','-warnings-as-errors',str(root/'Regram/RGLinkMetadata/Sources/RGInlineBotQuery.swift'),str(source),'-o',str(work/'checks')],check=True)
 subprocess.run([str(work/'checks')],check=True)
