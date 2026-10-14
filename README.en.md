# Regram

English · [简体中文](README.md)

Regram is an unofficial Telegram client maintained on top of Telegram for iOS, with message management, privacy controls, translation and speech recognition, appearance customization, and in-app updates.

## Features

### Messages and chats

- Unlimited locally pinned chats and ordering in the main list and archive. Pins beyond the Telegram account limit remain local.
- Recent chats, saved per account, with quick navigation and an option to clear the history.
- Local group remarks: set a display name from the group profile, saved per account and used in chat lists, titles and local search. Clear it to restore the original name.
- Message bookmarks and tags: bookmark a message from its menu, filter and edit tags per account, and jump back to the original message.
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
- Inspect media resolution, format/codec, bitrate, frame rate, duration, and file size.
- Photo quality and large-image sending; pasted photos default to HD, maximum JPEG quality, and up to 2560 px.
- Sticker sizing and history, recording, and camera options.
- Upload, download, playback, default video quality, and experimental media loading settings.
- Bottom video controls for rewind/forward by 15 seconds and play/pause; picture-in-picture, speed and quality are available in the top-right menu.

Preview availability depends on Telegram and the preview services. Unavailable media fields are shown as unknown.

### Appearance and input

- App icons, settings entry artwork, and screenshot badges; the Regram Pro entry follows the selected app icon.
- Bottom bar layout with a live preview, drag ordering, button visibility, standalone buttons, and automatic or manual width. Chats and Settings stay selected, and the complete bar is centered.
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
- Media/filter diagnostics, font cache management, and local data cleanup.
- Update checks and IPA downloads from this repository's GitHub Releases, with size and SHA-256 validation.
- TrollStore updates: reuse GitHub downloads and verification, then hand the IPA to TrollStore for installation without certificates. Supports automatic checks and optional automatic downloads.
- Local certificate/profile storage and on-device re-signing, followed by installation through LCSign's manifest service and iOS.
- Verified downloads and signed packages persist across restarts and can be reused after failures.

## Settings

All Regram preferences are under **Settings → Regram Pro**, whose home page shows only these categories:

| Category | Contents |
| --- | --- |
| Chats & Messages | Bookmarks and tags, message actions, chat list, and folders |
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

Bookmarks are under **Chats & Messages → Message Bookmarks & Tags**. DC testing is under **Network & Transfers → Performance & Transfers → DC1–DC5 Connection Tests**. Each installed identity selects its matching IPA from the shared GitHub Release, with size, SHA-256 and installation identity checks.
