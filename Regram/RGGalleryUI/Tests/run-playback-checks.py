#!/usr/bin/env python3
"""Exercise production gallery state handlers with account-free layout/player adapters."""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()


def source(path):
    if args.baseline:
        return subprocess.check_output(['git', 'show', 'HEAD:' + path], cwd=ROOT, text=True)
    return (ROOT / path).read_text()


def block(text, start):
    begin = text.index(start)
    opening = text.index('{', begin)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[begin:end]


footer = source('submodules/GalleryUI/Sources/ChatItemGalleryFooterContentNode.swift')
video = source('submodules/GalleryUI/Sources/Items/UniversalVideoGalleryItem.swift')
content = block(footer, 'var content: ChatItemGalleryFooterContent')
content_enum = block(footer, 'enum ChatItemGalleryFooterContent:')
panel = block(footer[footer.index('// MARK: Regram — one bottom capsule'):], 'if self.rgVideoControlsEnabled')
foreground = 'var rgApplicationInForeground = true'
pause = 'func rgPauseVideoInBackground() {}'
late_status = ''
if 'private func rgPauseVideoInBackground()' in video:
    foreground = block(video, 'private var rgApplicationInForeground =').removeprefix('private ')
    pause = block(video, 'private func rgPauseVideoInBackground()').removeprefix('private ')
    late_status = block(video[video.index('// MARK: Regram — stop a delayed playback'):], 'switch value.status')

fixture = r'''
import Foundation
enum Transition { case immediate }
struct UIColor: Equatable {
    static let white = UIColor()
    func withAlphaComponent(_ value: Double) -> UIColor { self }
}
struct Insets { static let zero = Insets() }
enum EngineMediaResource {
    enum FetchStatus: Equatable { case Local, Remote, Paused, Fetching(Bool, Float) }
}
enum RadialStatusNodeState: Equatable {
    case none
    case cloudProgress(color: UIColor, strokeBackgroundColor: UIColor, lineWidth: Double, value: CGFloat)
    case customIcon(Int)
}
enum PlayPauseIconNodeState { case play, pause }
final class Node {
    var isHidden = false
    var isUserInteractionEnabled = false
    func enqueueState(_ state: PlayPauseIconNodeState, animated: Bool) {}
    func transitionToState(_ state: RadialStatusNodeState, completion: () -> Void) { completion() }
}
final class TelegramMediaFile { var isAnimated = false }
final class Message { let media: [Any] = [] }
final class FileReference { let media = TelegramMediaFile() }
final class NativeVideoContent {
    let fileReference = FileReference()
    static func isHLSVideo(file: TelegramMediaFile) -> Bool { false }
}
final class HLSVideoContent { let fileReference = FileReference() }
struct Item { let content: Any }
let cloudFetchIcon: Int? = 1
struct RGGalleryPlaybackIconComponent {
    enum Icon { case play, pause, backward, forward }
    let icon: Icon
    init(_ icon: Icon) { self.icon = icon }
}
struct AnyComponent {
    let value: RGGalleryPlaybackIconComponent
    init(_ value: RGGalleryPlaybackIconComponent) { self.value = value }
}
enum GlassControlGroupComponent {
    struct Item {
        enum Content { case customIcon(id: String, component: AnyComponent, insets: Insets) }
        let id: String
        let content: Content
        let action: () -> Void
    }
}
CONTENT_ENUM
final class Footer {
    var rgVideoControlsEnabled = true
    var currentIsPaused = true
    var hasSeekControls = false
    var isAd = false
    var wasPlaying: Bool?
    var currentMessage: Message?
    let playbackControlButton = Node(), statusButtonNode = Node(), statusNode = Node(), playPauseIconNode = Node()
    var requestLayout: ((Transition) -> Void)?
    var layoutCount = 0
    var icons: [RGGalleryPlaybackIconComponent.Icon] = []
    CONTENT
    init() {
        requestLayout = { [weak self] _ in self?.render() }
        render()
    }
    func render() {
        layoutCount += 1
        var centerControlItems: [GlassControlGroupComponent.Item] = []
        PANEL
        icons = centerControlItems.map { item in
            switch item.content { case let .customIcon(_, component, _): return component.value.icon }
        }
    }
    func playbackControlPressed() {}
    func backwardButtonPressed() {}
    func forwardButtonPressed() {}
}
enum Status { case playing, paused, buffering(Int, Bool, Bool, Bool) }
struct PlayerStatus { let status: Status }
final class Player {
    var ownsContentNode = true
    var isPlaying = true
    var pauseCount = 0
    var timestamp = 42.0
    func pause() { isPlaying = false; pauseCount += 1 }
}
final class Manager { weak var currentPictureInPictureNode: Gallery? }
final class SharedContext { let mediaManager = Manager() }
final class Context { let sharedContext = SharedContext() }
final class Gallery {
    let context = Context()
    var videoNode: Player? = Player()
    var item: Item?
    var playOnContentOwnership = true
    var isLivePhotoPlaybackActive = false
    FOREGROUND
    PAUSE
    func resetLivePhotoPlayback() {
        if isLivePhotoPlaybackActive {
            isLivePhotoPlaybackActive = false
            videoNode?.timestamp = 0
        }
    }
    func statusChanged(_ status: Status) {
        let strongSelf = self
        let value = PlayerStatus(status: status)
        _ = strongSelf; _ = value
        LATE_STATUS
    }
}
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print(message); exit(1) }
}
func controls() {
    let footer = Footer()
    footer.content = .fetch(status: .Local, seekable: true)
    footer.render() // The initial gallery presentation lays out the footer before the first tap.
    expect(footer.icons == [.backward, .play, .forward], "Footer must render Play when a downloaded video becomes available")
    footer.content = .playback(paused: false, seekable: true)
    expect(footer.icons == [.backward, .pause, .forward], "Playing must immediately render Pause")
    footer.content = .playback(paused: true, seekable: true)
    expect(footer.icons == [.backward, .play, .forward], "Pausing must immediately render Play")
    footer.content = .playback(paused: false, seekable: false)
    expect(footer.icons == [.pause], "Short videos must update the icon without seek buttons")
    let count = footer.layoutCount
    footer.content = .playback(paused: false, seekable: false)
    expect(footer.layoutCount == count, "Repeated playback status must not trigger redundant footer layout")
    footer.content = .info
    expect(footer.icons.isEmpty, "Unavailable controls must disappear")
    footer.rgVideoControlsEnabled = false
    let imageCount = footer.layoutCount
    footer.content = .playback(paused: true, seekable: true)
    expect(footer.layoutCount == imageCount, "Image galleries must keep their existing layout behavior")
    print("PASS: footer state transitions, rendered icons, short videos and unchanged/image states")
}
func background() {
    for content in [NativeVideoContent() as Any, HLSVideoContent() as Any] {
        let regular = Gallery()
        regular.item = Item(content: content)
        regular.rgApplicationInForeground = false
        expect(!regular.videoNode!.isPlaying && regular.videoNode!.timestamp == 42, "Home/lock must pause ordinary gallery video, both native and HLS, at its current position")
    }
    let gallery = Gallery()
    let player = gallery.videoNode!
    gallery.rgApplicationInForeground = false
    expect(!player.isPlaying, "Home/lock must pause ordinary gallery video")
    expect(player.timestamp == 42, "Background pause must preserve the video position")
    expect(!gallery.playOnContentOwnership, "Background entry must cancel pending ownership autoplay")
    let paused = player.pauseCount
    gallery.rgApplicationInForeground = true
    expect(!player.isPlaying && player.pauseCount == paused, "Foreground return must preserve the paused state")
    player.isPlaying = true
    gallery.statusChanged(.playing)
    expect(player.isPlaying && player.pauseCount == paused, "User playback in the foreground must remain available")
    gallery.rgApplicationInForeground = false
    for status in [Status.playing, .buffering(0, true, false, true)] {
        player.isPlaying = true
        gallery.statusChanged(status)
        expect(!player.isPlaying, "Delayed playback/buffering must not restart background audio")
    }
    let stopped = player.pauseCount
    gallery.statusChanged(.paused)
    gallery.statusChanged(.buffering(0, false, false, true))
    expect(player.pauseCount == stopped, "Paused status must not cause a pause feedback loop")
    let pip = Gallery()
    pip.context.sharedContext.mediaManager.currentPictureInPictureNode = pip
    pip.rgApplicationInForeground = false
    pip.statusChanged(.playing)
    expect(pip.videoNode!.isPlaying && pip.videoNode!.pauseCount == 0, "Active PiP must retain playback")
    pip.context.sharedContext.mediaManager.currentPictureInPictureNode = nil
    pip.rgPauseVideoInBackground()
    expect(!pip.videoNode!.isPlaying, "Closing PiP in the background must stop its audio")
    let other = Gallery()
    other.context.sharedContext.mediaManager.currentPictureInPictureNode = pip
    other.rgApplicationInForeground = false
    expect(!other.videoNode!.isPlaying, "A different video in PiP must not exempt this gallery from background pause")
    let detached = Gallery()
    detached.videoNode!.ownsContentNode = false
    detached.rgApplicationInForeground = false
    expect(detached.videoNode!.isPlaying, "Detached gallery must not pause content owned by another view")
    expect(!detached.playOnContentOwnership, "Pending ownership must be cancelled even before attaching")
    detached.videoNode!.ownsContentNode = true
    detached.rgPauseVideoInBackground()
    expect(!detached.videoNode!.isPlaying, "Late ownership must respect the current background state")
    let live = Gallery()
    live.isLivePhotoPlaybackActive = true
    live.rgApplicationInForeground = false
    expect(!live.isLivePhotoPlaybackActive && !live.videoNode!.isPlaying, "Home/lock must also stop a live photo")
    for animation in [NativeVideoContent() as Any, HLSVideoContent() as Any] {
        if let native = animation as? NativeVideoContent { native.fileReference.media.isAnimated = true }
        if let hls = animation as? HLSVideoContent { hls.fileReference.media.isAnimated = true }
        let animated = Gallery()
        animated.item = Item(content: animation)
        animated.rgApplicationInForeground = false
        expect(animated.videoNode!.pauseCount == 0, "Looping animations without a Play button must retain their lifecycle")
    }
    print("PASS: Home/lock, position, foreground return, delayed status/ownership, PiP, live photo and animations")
}
@main enum Tests {
    static func main() {
        if CommandLine.arguments[1] == "controls" { controls() } else { background() }
    }
}
'''
for key, value in [('CONTENT_ENUM', content_enum), ('CONTENT', content), ('PANEL', panel),
                   ('FOREGROUND', foreground), ('PAUSE', pause), ('LATE_STATUS', late_status)]:
    fixture = fixture.replace(key, value)

env = os.environ.copy()
with tempfile.TemporaryDirectory(prefix='regram-gallery-playback-') as directory:
    folder = Path(directory)
    (folder / 'Tests.swift').write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-parse-as-library',
                    str(folder / 'Tests.swift'), '-o', str(folder / 'tests')], env=env, check=True)
    for case, failure in [('controls', 'Playing must immediately render Pause'), ('background', 'Home/lock must pause')]:
        result = subprocess.run([str(folder / 'tests'), case], capture_output=True, text=True)
        if args.baseline:
            if result.returncode == 0 or failure not in result.stdout:
                raise SystemExit('Baseline did not reproduce ' + case + ': ' + result.stdout + result.stderr)
            print('Confirmed baseline regression: ' + result.stdout.strip())
        else:
            print(result.stdout, end='')
            if result.returncode:
                raise SystemExit(result.stderr or result.returncode)
