# Regram

English · [简体中文](README.md)

Regram is an unofficial Telegram client maintained on top of Telegram for iOS, with message management, privacy controls, translation and speech recognition, and appearance customization.

This is **regram-beta / 13.1.2 / b34643**, the TestFlight branch. It includes the current mainline updates, Telegram 13.1.2, and chat-list search typing fixes. See [TestFlight](build-system/ci/TESTFLIGHT.md), the [beta sync record](docs/beta-sync-20261031.md), [feature list](docs/features.md), and [changelog](docs/changelog.md). Sideload packages and GitHub Releases use `master`.

## Features

### Messages and chats

- Unlimited locally pinned chats and ordering in the main list and archive. Pins beyond the Telegram account limit remain local.
- The last 50 opened chats per account, with quick navigation and history clearing.
- Local group and channel remarks: set a display name from the group or channel profile, saved per account and used in lists, titles and local search. Clear it to restore the original name.
- Message bookmarks and tags: add from a message menu, manage below Saved Messages on the outer Settings page, filter and edit tags, and return to the original message.
- Double-tap actions: react, show reactions, reply, repeat, repeat without attribution, translate, edit, or disable. Messages without editing permission can use a separate action.
- Enable, hide and reorder available message-menu actions, respecting message types and account permissions.
- A separate paginated page for a sender's messages in the current chat or topic, opened from the avatar menu, with keyword search, clear-to-restore and navigation to the original message.
- Messages in common groups: open from a person’s profile More menu, browse searchable messages in native grouped lists, filter by group and load more. Returning preserves avatars and list state; opening a result highlights the original message. Search concurrency adapts to Low Power Mode and device temperature.
- Locally observed edit history for text, captions, entities and replaced photos, including image previews, zoom and persistent storage of saved images.
- Optional automatic spoiler reveal, disabled by default; group/channel message IDs, timestamp seconds and original forwarding timestamps.
- Folder selection after joining groups/channels, remembered folders, and folder/list display options; local folder-tag visibility survives restart.
- Independent daily first-launch tasks in the scheduled-send repeat menu: configure once, then silently send on the first launch each day from the chosen date. Tasks stay on this device per account, support editing/deletion/Send Now, and skip missed days. Premium daily/weekly server schedules retain their existing behavior.

The [implementation checklist](docs/chat-and-interface-tools.md) lists share-sheet folders, group management shortcuts, bulk invite revocation, search links and independent privacy options. The existing formatting toolbar is preserved.

### Filters and privacy

- Keyword and regex filters with hide/allow rules, global or per-chat scope, testing, import and export.
- Hide selected senders, disable rule filtering for a chat, or temporarily reveal hidden content.
- Global/per-chat anti-revoke, an optional exclusion for newly revoked bot messages, a local revoked-message archive, and selected deletion and media-saving controls.
- Deleted-message markers as icons, custom text or hidden, with a custom color and immediate refresh of visible messages.
- Ghost controls for story read reporting, online presence and typing activity.
- User-ID mention links, hidden phone numbers in settings, profile IDs, DC regions and estimated registration dates.
- Notification content filtering, pin/mention/reply policies, empty-notification recovery and entitlement diagnostics.
- Experimental notification recovery in Regram Pro → Notifications, off by default and retaining existing preferences, with search, settings links and notification-category backup support. `tg://rg/rgdebug` retains the cache cleanup tool, keeping accounts, databases, settings.

Anti-revoke and edit history retain content already received or observed on this device. Ghost mode does not suppress ordinary chat read receipts. Client preferences cannot grant permissions enforced by Telegram or iOS.

### Translation, summaries and speech recognition

- Telegram, Apple, Google, Google CN, Microsoft, Yandex and Tencent TranSmart translation routes.
- LLM translation using OpenAI Chat Completions or Anthropic Messages formats, custom endpoints, model lists/tests, prompts, temperature and optional chat context.
- Message, chat, pre-send and in-app webpage translation, preserving links, code and formatting. Web translation can be canceled or reverted.
- Summaries are off by default and use a separate endpoint, model, prompt and credential. Collect text from the last hour, today, last day or a custom interval, or use single/selected messages. Review the upload before submitting.
- Time-range summaries allow up to 5000 messages and 64,000 text bytes; selected-message requests allow up to 100 messages. Oversized requests require a smaller scope rather than silent truncation. No media uploads; secret chats, ephemeral and protected content are excluded.
- Telegram, Apple or custom OpenAI-compatible Transcriptions API for voice messages and round-video audio, with configuration tests, language and prompt settings.
- Transcripts appear in the original message and can be copied, translated, canceled or recognized again.

Custom recognition is user initiated, excludes secret chats and view-once media, and converts audio to M4A with a 25 MB upload limit. API keys stay in the local Keychain and are excluded from settings backups. Connectivity, quotas and charges depend on the provider.

### Media and links

- Preview repair for X/Twitter, Instagram, TikTok, Reddit, Bluesky, Pixiv and other supported rules, with caching, updates and configurable X/Instagram preview domains. Original message links are preserved.
- Save static stickers as PNG and animated/video stickers as GIF to Photos.
- Sticker-pack ZIP backups with original WebP/PNG, TGS and WebM files, ordering and emoji metadata. Limits: 500 files, 32 MiB per file and 256 MiB per pack.
- Single-message screenshots: avatar on the left, sender name above the body on the right, media preserved and no bubble background. Avoid missing or duplicate names, then save or send through the system share sheet.
- Media resolution, format/codec, bitrate, frame rate, duration and size; unavailable fields are shown as unknown.
- Photo quality and large-image sending. Pasted photos default to HD, maximum JPEG quality and up to 2560 px.
- Sticker size/history, camera and recording, transfer and default-video-quality options.
- Bottom video controls for rewind/forward by 15 seconds and play/pause. Picture-in-picture, speed and quality are in the top-right menu.
- Ordinary full-screen video pauses on Home or screen locking and retains its position; the play/pause icon follows playback state, while active picture-in-picture keeps playing.
- Optional media-loading experiments for prefetching, playback admission, player reuse and first-frame handoff, allowing comparison within the same app.

Preview availability depends on Telegram and third-party services. A sticker archive cannot recreate a deleted server-side pack. Media-loading benefits require device comparison.

### Appearance and input

- Settings and Regram feature pages share Telegram themes, grouped lists and glass navigation while preserving back gestures. Older systems use the upstream fallback.
- App icons and screenshot App Badges. The Regram Pro entry follows the selected app icon; login artwork uses Regram artwork.
- Confirmed icon selections persist across launches and restore the Pro entry and Appearance selection while delayed system reads reconcile. Failed changes and stale callbacks do not replace the saved choice.
- Upstream Telegram bottom-bar components, animations and gestures, with live preview, drag ordering, label visibility, standalone buttons and automatic/manual width.
- Chats and Settings must remain visible. The centered bar automatically narrows with fewer navigation items. Search is an opt-in control under Display Items, using the Swiftgram native right-side button and expanding field for the current page; Calls opens the new-call picker. Settings remains reachable while hidden. Swipe right from the Settings content area to return to Chats with finger-tracked motion and cancellation; unhiding applies immediately.
- Chat-list separators, compact display, one/two body-preview lines and colors. Older three-line preferences and backups migrate to two lines.
- Separate Latin/CJK fonts, downloads, TTF/OTF/TTC import, previews, management and missing-glyph fallback.
- Input tools, default formatting, Pangu spacing, Return-to-send and per-chat input preferences.
- Rich-text editing and rendering for headings, quotes, code, lists, tables, links, media and drafts. Some entry points depend on upstream configuration.
- Profile role badges for developers, core testers and sponsors.

### Network and diagnostics

- DC1–DC5 tests on a separate page: initial connection request, three latency samples, average/minimum latency, variation and failures, plus the current connection route and DC.
- DC region labels: DC1/3 Miami, DC2/4 Amsterdam and DC5 Singapore. Copy exports only five average ping values and immediately confirms completion.
- Built-in HTTPS DNS, system DNS or custom DoH. Custom DoH is off by default; one resolution-mode setting avoids conflicting DNS switches.
- Five IP policies: automatic, IPv4 only, prefer IPv4, prefer IPv6 and IPv6 only. Preferred modes allow fallback; only modes enforce one family.
- Built-in Google/Cloudflare HTTPS resolution. Custom DNS supports JSON and wire-format compatibility for address lookups, plus backup-DC TXT lookups with signature and validity checks retained.
- Hostname proxies keep multiple candidates, rotate after failure or four seconds without a response, start a fresh handshake and briefly cache successful addresses.
- A separate cancelable A/AAAA test page reports addresses, policy filtering and lookup duration without the app DNS cache. Media transfer statistics and filter-performance tests remain available.

IP policies apply to native Telegram DC and SOCKS5/MTProto proxy connections. Webpages, HTTP APIs and Web proxies use the system network. Custom DoH failures do not downgrade to system resolution; resolver hostnames still need system bootstrap. DNS time is not DC Ping, and DC labels do not identify a user's location.

### Login and backups

- Colored QR login with token refresh, DC migration, two-step verification and retries. Telegram connectivity is still required.
- No local account-count cap; Telegram login and abuse-prevention rules still apply.
- Category-based JSON settings backup/restore with an import preview, excluding sessions, chat databases, certificates, API keys and font files.
- Local Premium display, cache management, five-second auto-lock after leaving, and confirmed local-data erasure, with startup handling to avoid blank screens and disappearing prompts.

Local customization is in **Settings → Regram Pro → Show Off**: local Premium display, Stars/TON, gifts and appearance, phone display, signed ratings and the TON profile card. Gift purchases keep direct checkout; limited local gifts can be upgraded in the native details sheet. Quote colors and the chat-list gift status follow the same local appearance. These settings only affect this device.

## Settings

Feature preferences are under **Settings → Regram Pro**, organized into nine categories and the Show Off section:

| Category | Contents |
| --- | --- |
| Chats & Messages | Summary API, message actions, chat list, folders |
| Input & Sending | Input tools, formatting, send controls, per-chat preferences |
| Translation & Speech | Translation providers, LLM, custom recognition, transcription routes |
| Privacy & Filters | Rules, hidden senders, anti-revoke, archives, ghost mode, stories |
| Media & Links | Preview repair, photos, stickers, recording, playback |
| Appearance & Interface | Fonts, icons, screenshot badges, tab bar, profile display |
| Notifications & Alerts | Experimental notification recovery, content filtering, pins, mentions and replies |
| Network & Transfers | DNS/IP, transfer parameters, call connections, performance and DC tests |
| Show Off | Local Premium, Stars/TON gifts and upgrades, appearance, phone display, ratings and the TON card |
| Management & Tools | Backups, data cleanup |

Basic controls appear within their category. Chats and media use the native chat-folder tab bar within the same screen; the bottom bar editor is under Regram Pro → Appearance & Interface → Bottom Bar Layout. Specialised editors remain separate pages.

Within Pro, global settings search is on the home page, covering categories and advanced pages. Results open and focus the setting; category pages do not duplicate search or frequently used shortcuts. Long-press a setting to copy a deep link containing only its page and control identifier. Bookmarks have a separate entry below Saved Messages on the outer Settings page.

The outer Settings search and Pro home search share the catalog, aliases and setting destinations. Empty results, clearing and IME composition are handled consistently. See the [follow-up record](docs/groups-settings-search-drag-fixes.md) for search, common-group pagination, drag previews and badge fixes.

## Build and package verification

This branch integrates applicable **13.1.2 / b34643** changes and continues to exclude in-app IPA updates. All builds use `dev.regram.ios` / `group.dev.regram.ios`, shared by the main application and all six extensions. See the [beta sync record](docs/beta-sync-20261031.md) for validation scope. Historical mainline package checks do not validate a beta package.

## Building

Use macOS, full Xcode 27.1, Python 3, and Git. Tool versions are listed in [versions.json](versions.json). The app target is **//Telegram:Regram**. See the [13.1.2 upstream integration record](docs/upstream-sync/13.1.2.md) for compatibility and verification scope.

```sh
git clone --branch regram-beta --recursive https://github.com/RegramDev/Regram-ios.git
cd Regram-ios
git submodule update --init --recursive
```

Check and apply the rules_apple compatibility patch as described in the [patch documentation](build-system/patches/README.md):

```sh
git -C build-system/bazel-rules/rules_apple apply --check ../../patches/rules_apple-local.patch
git -C build-system/bazel-rules/rules_apple apply ../../patches/rules_apple-local.patch
```

Copy the configuration template into ignored `build-input/`, retain this branch's Bundle ID `dev.regram.ios`, and supply your own Telegram API credentials and Team ID. Obtain Telegram API credentials from [my.telegram.org](https://my.telegram.org/apps).

```sh
mkdir -p build-input
cp build-system/template_minimal_development_configuration.json build-input/regram-development.json
```

Generate a simulator project:

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir="$PWD/build-input/bazel-cache" \
  generateProject \
  --configurationPath=build-input/regram-development.json \
  --xcodeManagedCodesigning --disableProvisioningProfiles
```

Build a device IPA with matching signing material for the main app and all six extensions:

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir="$PWD/build-input/bazel-cache" \
  build \
  --configurationPath=build-input/regram-development.json \
  --codesigningInformationPath=build-input/codesigning \
  --buildNumber=10001 --configuration=release_arm64 \
  --target=//Telegram:Regram
```

The output is `bazel-bin/Telegram/Regram.ipa`. Follow the [reference packaging guide](docs/lcsign-reference-packaging.md) when preparing an ad-hoc reference IPA for LCSign or another signing tool. Keep the application identity and data container unchanged for an in-place upgrade.

`--overrideXcodeVersion` skips the version check; it does not guarantee toolchain compatibility. Never commit API credentials, certificates, provisioning profiles, IPAs, or real account data.

## Documentation and contributions

- [Full feature list and limitations](docs/features.md)
- [Recent changes](docs/changelog.md)
- [Documentation index](docs/README.md)
- [Rich-text input](docs/richtext-composer.md)
- [UI testing](docs/ui-testing.md)
- [Contributing](.github/CONTRIBUTING.md)

Regram is not affiliated with the official Telegram project. Follow this repository's and its dependencies' licenses when distributing a modified client, and identify it clearly as unofficial.

This branch uses `dev.regram.ios` and `group.dev.regram.ios`. The application and six extensions share the declared App Group. Application update downloads, certificate imports and IPA installation are excluded.

The source baseline is [Telegram’s official master branch](https://github.com/TelegramMessenger/Telegram-iOS/tree/master), revision `279f89e4d4f63f17227bf877dc3d8990f22ecd58` (13.1.2), with Regram changes maintained on top. The `regram-beta` branch in this repository is a separate product branch.
