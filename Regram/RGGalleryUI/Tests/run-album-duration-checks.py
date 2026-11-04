#!/usr/bin/env python3
"""Exercise the production album badge override and duration formatter without accounts or media."""
from pathlib import Path
import subprocess, tempfile

root = Path(__file__).resolve().parents[3]
source = (root / "submodules/TelegramUI/Components/Chat/ChatMessageInteractiveMediaNode/Sources/ChatMessageInteractiveMediaNode.swift").read_text()
start = source.index("        // MARK: Regram — every video tile in an album")
end = source.index("        if isPreview, let file", start)
block = source[start:end]
adapter = r'''
import Foundation
class Media {}
final class TelegramMediaFile: Media {
    var isVideo = true, isAnimated = false, isVideoSticker = false
    var duration: Double? = 65
}
struct EngineMedia { let media: Media; func _asMedia() -> Media { media } }
enum Calculation { case unconstrained, constrained }
enum Badge {
    case text(inset: CGFloat, backgroundColor: Int, foregroundColor: Int, text: NSAttributedString, iconName: String?)
    case mediaDownload(backgroundColor: Int, foregroundColor: Int, duration: String, size: String?, muted: Bool, active: Bool)
    var duration: String {
        switch self { case let .text(_, _, _, text, _): return text.string; case let .mediaDownload(_, _, duration, _, _, _): return duration }
    }
}
struct Theme { let mediaDateAndStatusFillColor = 1; let mediaDateAndStatusTextColor = 2 }
final class Fixture {
    var media: EngineMedia?
    func update(_ initial: Badge? = nil, grouped: Bool = true, secret: Bool = false) -> Badge? {
        var badgeContent = initial
        let sizeCalculation: Calculation = grouped ? .unconstrained : .constrained
        let isSecretMedia = secret
        let messageTheme = Theme()
'''
tests = r'''
        return badgeContent
    }
}
@main enum Checks {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
    static func main() {
        let fixture = Fixture(), video = TelegramMediaFile()
        fixture.media = EngineMedia(media: video)
        expect(fixture.update()?.duration == "1:05", "A remote HLS album tile must show a duration before a resource status produces a badge")
        let compact = Badge.text(inset: 12, backgroundColor: 3, foregroundColor: 4, text: NSAttributedString(string: "73%"), iconName: nil)
        guard case let .text(inset, background, foreground, text, icon)? = fixture.update(compact) else { fatalError("Missing compact duration") }
        expect(inset == 12 && background == 3 && foreground == 4 && text.string == "1:05" && icon == nil, "Fetching a compact tile must retain the control inset and theme while showing time")
        let downloading = Badge.mediaDownload(backgroundColor: 3, foregroundColor: 4, duration: "4 MB / 8 MB", size: "4 MB / 8 MB", muted: true, active: true)
        guard case let .mediaDownload(_, _, duration, size, muted, active)? = fixture.update(downloading) else { fatalError("Missing download badge") }
        expect(duration == "1:05" && size == "4 MB / 8 MB" && muted && active, "A wide tile must keep download controls, size and mute state")
        expect(fixture.update(compact, grouped: false)?.duration == "73%", "Single-video status behavior must remain intact")
        expect(fixture.update(compact, secret: true)?.duration == "73%", "Secret countdown and view-once badges must remain intact")
        for seconds in [0.0, 1, 59, 60, 3599, 3600, 10801, 2147483647] {
            video.duration = seconds
            expect(fixture.update()?.duration == stringForDuration(Int32(seconds)), "Every tile uses its own media duration, including hours")
        }
        for invalid in [Double.nan, .infinity, -1] {
            video.duration = invalid
            expect(fixture.update() == nil, "Invalid metadata must not crash or invent a duration")
        }
        video.duration = nil
        expect(fixture.update() == nil, "Missing metadata stays unknown")
        video.duration = 65; video.isAnimated = true
        expect(fixture.update() == nil, "GIF labels must remain intact")
        video.isAnimated = false; video.isVideoSticker = true
        expect(fixture.update() == nil, "Video stickers must not gain a duration")
        video.isVideoSticker = false; video.isVideo = false
        expect(fixture.update() == nil, "Non-video files must not gain a duration")
        fixture.media = EngineMedia(media: Media())
        expect(fixture.update() == nil, "Photos must not gain a duration")
        print("Album duration checks passed: remote, fetching, local, compact/wide controls, independent durations, secret media and invalid metadata")
    }
}
'''
with tempfile.TemporaryDirectory(prefix="regram-album-duration-") as directory:
    work = Path(directory)
    production = work / "ProductionAlbumBadge.swift"
    production.write_text(adapter + block + tests)
    binary = work / "checks"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-warnings-as-errors", str(root / "submodules/TelegramStringFormatting/Sources/StringForDuration.swift"), str(production), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
