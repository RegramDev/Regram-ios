#!/usr/bin/env python3
"""Check raw story flag persistence independently of the live local UI override."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
raw = (root / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift').read_text().splitlines()
projection = (root / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/StoryListContext.swift').read_text().splitlines()
constructor = next(line for line in raw if 'self.isForwardingDisabled = isForwardingDisabled' in line)
decoder = next(line for line in raw if 'self.isForwardingDisabled =' in line and 'decodeIfPresent' in line)
encoder = next(line for line in raw if 'try container.encode(self.isForwardingDisabled,' in line)
effective = next(line.strip() for line in projection if 'public var isForwardingDisabled: Bool {' in line)
source = '''import Foundation
final class RGSimpleSettings { static let shared = RGSimpleSettings(); var allowDownloadingStories = false }
struct RawStory: Codable {
 enum CodingKeys: String, CodingKey { case isForwardingDisabled }
 let isForwardingDisabled: Bool
 init(isForwardingDisabled: Bool) {
''' + constructor + '''
 }
 init(from decoder: Decoder) throws { let container = try decoder.container(keyedBy: CodingKeys.self)
''' + decoder + '''
 }
 func encode(to encoder: Encoder) throws { var container = encoder.container(keyedBy: CodingKeys.self)
''' + encoder + '''
 }
}
struct Projection {
 let serverForwardingDisabled: Bool
''' + effective + '''
}
@main enum Checks {
 static func main() throws {
  let settings = RGSimpleSettings.shared, encoder = JSONEncoder(), decoder = JSONDecoder()
  let original = try encoder.encode(RawStory(isForwardingDisabled: true))
  let live = Projection(serverForwardingDisabled: true)
  precondition(live.isForwardingDisabled)
  settings.allowDownloadingStories = true
  precondition(!live.isForwardingDisabled)
  let incoming = try encoder.encode(RawStory(isForwardingDisabled: true))
  let reread = try decoder.decode(RawStory.self, from: original)
  let rewritten = try encoder.encode(reread)
  precondition(reread.isForwardingDisabled)
  settings.allowDownloadingStories = false
  for data in [original, incoming, rewritten] {
   let value = try decoder.decode(RawStory.self, from: data)
   precondition(value.isForwardingDisabled)
  }
  precondition(live.isForwardingDisabled && !Projection(serverForwardingDisabled: false).isForwardingDisabled)
  print("Story protection passed: raw flags survive parse/save/reopen with the override enabled; existing UI projections honor on/off changes without a refetch.")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-story-flags-') as temporary:
    work = Path(temporary)
    (work / 'Checks.swift').write_text(source)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-warnings-as-errors', str(work / 'Checks.swift'), '-o', str(work / 'checks')], check=True)
    subprocess.run([str(work / 'checks')], check=True, timeout=10)
