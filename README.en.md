# Regram

English · [简体中文](README.md)

Regram is an unofficial Telegram client maintained on top of Telegram for iOS, with message management, privacy controls, translation and speech recognition, appearance customization, and in-app updates.

## Features

### Messages and chats

- Unlimited locally pinned chats and ordering in the main list and archive. Pins beyond the Telegram account limit remain local.
- Recent chats, saved per account, with quick navigation and an option to clear the history.
- Local group remarks: set a display name from the group profile, saved per account and used in chat lists, titles and local search. Clear it to restore the original name.
- Message bookmarks and tags: open the manager below Saved Messages on the outer Settings page, filter and edit local tags, and jump back to the original message.
- Opt-in message summaries through a separate OpenAI/Anthropic endpoint, model, prompt and Keychain credential. Load text from the current chat or topic over the last hour, today, last day or a custom interval, or summarize selected messages. Review text before uploading.
- Configurable message double-tap actions: react, show reactions, reply, repeat, repeat without attribution, translate, edit, or disable. Messages without editing permission can use a separate action.
- Message menu visibility and ordering, based on actions available for the message and account.
- A separate paginated page for a sender's messages in the current chat or topic, opened from the avatar menu, with navigation to the original message.
- Locally observed edit history for text, captions, entities, and replaced photos, with image preview and zoom.
- Optional automatic reveal of spoiler text, photos and videos in chats and gallery captions; disabled by default.
- Message IDs in groups/channels, seconds in timestamps, and the original time of forwarded messages.
- Folder selection after joining a group/channel, remembered folders, and chat list customization.

### Filters and privacy

- Keyword and regular-expression filters, hide/allow rules, global or chat-specific scope, and rule import/export.
- Hide selected senders, disable filtering in a chat, or temporarily reveal hidden content.
- Anti-revoke controls and a revoked-message archive, per-chat settings, and selected deletion/media-saving controls.
- Ghost mode controls for story read reporting, online presence, and typing activity.
- User-ID mention links, hidden phone numbers in settings, profile IDs, data center details, and locally estimated registration dates.
- Notification filtering and separate policies for pins, mentions, and replies.

Anti-revoke and edit history retain content already received or observed on this device. They cannot recover unseen versions or grant permissions enforced by Telegram's servers.

### Translation and speech recognition

- Telegram, Apple, and external translation routes, including Google, Google CN, Microsoft, Yandex, and Tencent TranSmart.
- LLM translation using OpenAI Chat Completions or Anthropic Messages formats, configurable endpoints, model lists and tests, prompts, temperature, and optional context.
- Message, chat, and pre-send translation with links, code, and text formatting preserved.
- Webpage translation from the in-app browser menu, with cancellation and original-page restoration.
- Audio transcription through Telegram, Apple, or a custom OpenAI-compatible Transcriptions API.
- Custom recognition for voice messages and round-video audio, with endpoint, model, language, prompt, and built-in audio testing.
- Transcripts appear in the original message and can be copied, translated, canceled, or recognized again.

Custom recognition uploads only messages explicitly selected by the user. Secret chats and view-once media are excluded. Audio is converted to M4A with a 25 MB upload limit. API keys remain in the local Keychain and are excluded from settings backups. Availability and API charges depend on the chosen provider.

### Media and links

- Preview repair rules for X/Twitter, Instagram, TikTok, Reddit, Bluesky, Pixiv, and other supported domains, with cached rules and updates.
- Preview requests can be repaired without changing the original message links. X/Instagram preview service domains are configurable.
- Save static stickers as PNG and animated/video stickers as GIF to Photos.
- Export a sticker pack as ZIP with original WebP/PNG, TGS and WebM files plus ordering and emoji metadata.
- Capture a single message with its avatar, text and media on a flat background. Keep an existing sender name once, or add it when consecutive messages omit it. Save or send through the system share sheet.
- Inspect media resolution, format/codec, bitrate, frame rate, duration, and file size.
- Photo quality and large-image sending; pasted photos default to HD, maximum JPEG quality, and up to 2560 px.
- Sticker sizing and history, recording, and camera options.
- Upload, download, playback, default video quality, and experimental media loading settings.
- Bottom video controls for rewind/forward by 15 seconds and play/pause; picture-in-picture, speed and quality are available in the top-right menu.

Preview availability depends on Telegram and the preview services. Unavailable media fields are shown as unknown.

### Appearance and input

- App icons, settings entry artwork, and screenshot badges; the Regram Pro entry follows the selected app icon.
- Bottom bar layout using upstream Telegram glass, animations and gestures, with a live preview, drag ordering, button visibility, standalone buttons, and automatic or manual width. Chats and Settings stay selected, and the complete bar is centered.
- Chat-list separator visibility.
- Separate Latin and CJK fonts, downloadable fonts, TTF/OTF/TTC import, previews, management, and missing-glyph fallback.
- Chat list lines, compact layouts, and colors.
- Input tools, default text formatting, per-chat input preferences, Pangu spacing, and Return-to-send.
- Rich-text editing and rendering for headings, quotes, code, lists, tables, links, media, and drafts.
- Profile role badges for developers, core testers, and sponsors.

### Login, backups, and updates

- Colored QR login, token refresh, data center migration, two-step verification, and retry handling.
- No local account-count cap; Telegram server login rules still apply.
- Category-based JSON settings backup and restore, excluding login sessions, chat databases, certificates, and API keys.
- DC1–DC5 connection tests on a separate page: initial connection request, three subsequent samples, average/minimum latency, variation and failures. Copied results contain only the five DC average ping values.
- Built-in HTTPS DNS, system DNS or opt-in custom DoH, with automatic, IPv4 only, prefer IPv4, prefer IPv6 and IPv6 only policies. Preferred modes allow fallback; only modes enforce the selected address family.
- Hostname proxies retain multiple IPv4/IPv6 candidates, try them in policy order and rotate after failure or four seconds without a response. Each attempt starts a fresh handshake; successful addresses are remembered briefly.
- Media/filter diagnostics, font cache management, and local data cleanup.
- Update checks and IPA downloads from this repository's GitHub Releases, with size and SHA-256 validation.
- TrollStore updates: reuse GitHub downloads and verification, then hand the IPA to TrollStore for installation without certificates. Supports automatic checks and optional automatic downloads.
- Local certificate/profile storage and on-device re-signing, followed by installation through LCSign's manifest service and iOS.
- Verified downloads and signed packages persist across restarts and can be reused after failures.
- Updates use system background downloads and support Lock Screen and Dynamic Island Live Activities for download, validation, signing and installation readiness. Tap to return to the update page; this display can be disabled in update settings.

## Settings

Regram feature preferences are under **Settings → Regram Pro**, whose home page shows only these categories:

| Category | Contents |
| --- | --- |
| Chats & Messages | Message summary API, message actions, chat list, and folders |
| Input & Sending | Input tools, default formatting, send controls, and per-chat input settings |
| Translation & Speech | Translation providers, LLM configuration, custom recognition, and transcription routes |
| Privacy & Filters | Rules, hidden senders, anti-revoke, archived messages, ghost mode, and stories |
| Media & Links | Preview repair, photos, stickers, recording, and playback |
| Appearance & Interface | Fonts, icons, badges, tab bar, and profile display |
| Notifications & Alerts | Filtering, pins, mentions, and replies |
| Network & Transfers | Upload/download parameters, call connections, diagnostics, and DC tests |
| Management & Tools | Local Premium, backups, updates, and data cleanup |

Each feature has one settings entry. Larger categories use subpages. Only the Regram Pro home page has search across all settings; results open their destination and scroll to the setting. Category pages and subpages do not add settings search or frequently used shortcuts. Long-press a setting to copy its deep link, containing only the page and setting identifier.

Voice-to-text is under **Translation & Speech → Voice-to-Text**; LLM configuration is under **Translation & Speech → Translation → LLM Translation**; link-preview repair is under **Media & Links**; updates are under **Management & Tools → Regram Updates**.

Update checks work without certificates. A separate GitHub Release button opens the release only when tapped. Automatic checks are off by default, and reminders require opting in. Certificate users can enable automatic exit after the system receives the complete installation package.

## Building

Use macOS, full Xcode, Python 3, and Git. Tool versions are listed in [versions.json](versions.json). The app target is **//Telegram:Regram**.

```sh
git clone --recursive https://github.com/RegramDev/Regram-ios.git
cd Regram-ios
git submodule update --init --recursive
```

Check and apply the rules_apple compatibility patch as described in the [patch documentation](build-system/patches/README.md):

```sh
git -C build-system/bazel-rules/rules_apple apply --check ../../patches/rules_apple-local.patch
git -C build-system/bazel-rules/rules_apple apply ../../patches/rules_apple-local.patch
```

Copy the configuration template into ignored `build-input/` and supply your own Bundle ID, Telegram API credentials, and Team ID. Obtain Telegram API credentials from [my.telegram.org](https://my.telegram.org/apps).

```sh
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
- [Documentation index](docs/README.md)
- [Updates and installation](docs/app-updates.md)
- [Rich-text input](docs/richtext-composer.md)
- [UI testing](docs/ui-testing.md)
- [Contributing](.github/CONTRIBUTING.md)

Regram is not affiliated with the official Telegram project. Follow this repository's and its dependencies' licenses when distributing a modified client, and identify it clearly as unofficial.

Bookmarks are under **Settings → below Saved Messages → Message Bookmarks & Tags**. DC testing is under **Network & Transfers → Performance & Transfers → DC1–DC5 Connection Tests**. Releases provide one Regram IPA. In-app updates use `Regram-version-bbuild.ipa`, with size, SHA-256 and installation identity checks.

Configure summaries under **Regram Pro → Chats & Messages → Message summary API**. The feature is off by default and its menu and selection-toolbar buttons stay hidden while disabled. Time-range collection is limited to 5000 messages and 64 KB text; exceeding a limit requires a smaller interval instead of silently truncating. Selected-message requests allow at most 100 messages. Attachments are excluded. Secret chats, ephemeral media and protected messages are excluded. Sticker archives are limited to 500 files, 32 MiB per file and 256 MiB per pack. Temporary files are removed after cancellation, failure or sharing. An archive does not recreate a deleted server-side pack.

**Regram Pro → Network & Transfers → DNS and IP policy** configures built-in HTTPS DNS (Google/Cloudflare), system resolution or custom DoH. Custom resolvers use DNS JSON with wire-format compatibility for address queries, and also serve backup-DC TXT lookups. Backup configurations retain signature and validity checks; additional backup discovery can be disabled. Native DC addresses and proxy endpoints obey the IP policy. Webpages, HTTP APIs and Web proxies use the system network. Custom resolver failures never downgrade to system DNS; resolver hostnames still use system DNS to bootstrap.

DC average-copy and summary-copy buttons immediately show a copied confirmation. DNS and IP policy includes an on-demand A/AAAA diagnostic page showing resolved addresses and elapsed lookup time, bypassing the app DNS cache without family fallback. This measures DNS lookup time, not DC Ping. The resolution-mode picker replaces the duplicate proxy-page DNS switch; saving reconnects the native transport immediately.

Automatic bottom-bar width balances readable labels, native selection effects and comfortable tap targets. More tabs use the available width; the bar remains centered. Manual percentage width is preserved.

Retained deleted messages support an icon, a custom text marker or no marker, with a custom marker color or the theme’s timestamp color. Configure this under **Privacy & Filters → Anti-deletion & Restrictions → Deleted-message marker**.
