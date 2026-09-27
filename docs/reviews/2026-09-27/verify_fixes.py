"""No compilation: Foundation probes, boundary models, and source integration assertions."""
import json
import pathlib
import random
import subprocess
import unicodedata

root = pathlib.Path.cwd()
folder = pathlib.Path(__file__).resolve().parent
checks = []

def check(name, condition, detail=None):
    checks.append({'name': name, 'passed': bool(condition), 'detail': detail})

for pattern, value, expect in [('广告|spam', 'SPAM 😀', True), ('^(a+)+$', 'a' * 32 + '!', False)]:
    process = subprocess.run(['osascript', '-l', 'JavaScript', str(folder / 'bounded-regex.js'), pattern, value], capture_output=True, text=True, timeout=2, check=True)
    data = json.loads(process.stdout)
    check('bounded_foundation:' + pattern, data['first']['matched'] == expect and data['first']['ms'] < 300 and data['cancelled']['skipped'], data)
    if not expect:
        check('slow_rule_is_skipped_after_timeout', data['paused'] and data['second']['skipped'], data['second'])

# Exercise the shared projection's invariants against an independently selected expected set.
random.seed(27)
for size in [0, 1, 63, 64, 65, 127, 128, 129, 1000, 10000]:
    for marked in [False, True]:
        for mode in ['all', 'alternating', 'random']:
            ids = list(range(1, size + 1))
            hidden = set(ids) if mode == 'all' else {i for i in ids if (i % 2 == 0 if mode == 'alternating' else random.random() < 0.3)}
            seen = set()
            newest = list(reversed(ids))
            for offset in range(0, len(newest), 64):
                seen.update(i for i in newest[offset:offset + 64] if i in hidden)
            displayed = max(0, size - len(seen))
            check(f'projection:{size}:{marked}:{mode}', displayed == len(set(ids) - hidden) and (displayed > 0 or marked) == (bool(set(ids) - hidden) or marked))

def key(rule):
    return rule['pattern'], rule['isRegex'], tuple(sorted(set(rule['peerIds'])))
existing = [{'pattern': 'spam', 'isRegex': True, 'peerIds': [1]}]
incoming = [{'pattern': 'spam', 'isRegex': True, 'peerIds': [2]}, {'pattern': 'spam', 'isRegex': True, 'peerIds': [1, 1]}, {'pattern': 'spam', 'isRegex': True, 'peerIds': []}]
keys = {key(rule) for rule in existing}
merged = list(existing)
for rule in incoming:
    if key(rule) not in keys:
        keys.add(key(rule)); merged.append(rule)
check('dedup_preserves_scope', len(merged) == 3)
check('stale_page_id_update_preserves_import', len([rule for rule in merged if rule['peerIds'] != [1]]) == 2)

# Gesture direction no longer needs a virtual list's first item to exist.
hidden, anchor = False, 0
for offset in [0, 10, 26, 2000, 1980]:
    delta = offset - anchor
    if delta > 24 and not hidden: hidden, anchor = True, offset
    elif delta < -18 and hidden: hidden, anchor = False, offset
    elif (delta < 0 and not hidden) or (delta > 0 and hidden): anchor = offset
check('deep_scroll_reveals_bar', not hidden)

def read(name): return (root / name).read_text()
matcher = read('Regram/RGSimpleSettings/Sources/MessageFilter.swift')
context = read('submodules/TelegramCore/Sources/Utils/RGFilteredUnreadContext.swift')
projection = read('submodules/ChatListUI/Sources/Node/RGChatListPreviewFilter.swift')
history = read('submodules/TelegramUI/Sources/ChatHistoryListNode.swift')
notification = read('Telegram/NotificationService/Sources/NotificationService.swift')
settings_icons = read('submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift')
check('matcher_progress_callback', '.reportProgress' in matcher and 'stop.pointee = true' in matcher and 'regex.firstMatch' not in matcher)
check('single_regex_budget_per_message', 'let deadline = ProcessInfo.processInfo.systemUptime + RGMessageFilter.maximumMatchDuration' in matcher)
check('bounded_import', 'maximumImportBytes + 1' in matcher and 'maximumRuleCount' in matcher)
check('atomic_import_includes_scope', 'Set(existing.map(RuleKey.init))' in matcher and 'peerIds = Array(Set(rule.peerIds)).sorted()' in matcher)
check('full_unread_paging', 'limit: 64' in context and 'before: last.index' in context and 'withAllMessages' not in context)
check('pagination_uses_original_indices', 'paginationList: update.paginationList' in projection and 'originalList: update.paginationList' in read('submodules/ChatListUI/Sources/Node/ChatListNode.swift'))
check('projection_does_not_blank_before_ready', 'guard snapshot.isReady else { return update }' in projection)
check('forum_topic_mute_is_preserved', 'counters.isMuted = muted' in context)
check('unfiltered_next_channel_keeps_fast_path', 'needsFilteredSearch' in read('submodules/TelegramCore/Sources/TelegramEngine/Peers/TelegramEnginePeers.swift') and 'stopOnFirstMatch: !needsFilteredSearch' in read('submodules/TelegramCore/Sources/TelegramEngine/Peers/TelegramEnginePeers.swift'))
check('no_filtered_read_receipts', 'applyMaxReadIndexInteractively' not in projection and 'preparedVerdict' in history)
check('global_counters_wired', 'visibility.adjustedTotal' in read('submodules/TelegramUIPreferences/Sources/RenderedTotalUnreadCount.swift') and 'visibility.adjustedTotal' in read('submodules/ChatListUI/Sources/TabBarChatListFilterController.swift'))
check('native_navigation_for_both_pages', all('bindNativeNavigation' in read('Regram/RGProUI/Sources/' + name) for name in ['MessageFilterController.swift', 'SessionBackupController.swift']))
check('containment_parent', 'controller.didMove(toParent: self)' in read('Regram/RGSwiftUI/Sources/RGSwiftUI.swift'))
check('backup_no_blocking_overlay', 'OverlayStatusController' not in read('Regram/RGProUI/Sources/SessionBackupController.swift'))
check('notification_targeted_delayed_removal', 'request.identifier == requestId' in read('Telegram/NotificationService/Sources/NotificationService.swift') and 'asyncAfter' in read('Telegram/NotificationService/Sources/NotificationService.swift'))
check('notification_badge_stays_lightweight', 'RGFilteredUnreadContext' not in notification and 'accountPeerId: PeerId' not in notification[notification.index('private func getCurrentRenderedTotalUnreadCount'):notification.index('@available(iOSApplicationExtension 10.0')])
check('filtered_messages_keep_system_notifications', 'RGContentFilterState' not in notification and 'RGMessageFilter' not in notification)
check('icon_failure_does_not_change_selection', 'if success {' in settings_icons and 'currentAppIconName.set(icon.name)' in settings_icons)
check('translation_sequential', 'rgTranslateSequentially(translationSignals)' in read('Regram/RGGTranslate/Sources/RGGTranslate.swift') and 'offsetBy: limit' in read('Regram/RGGTranslate/Sources/RGGTranslate.swift'))

strings = list((root / 'Regram/RGStrings/Strings').glob('*.lproj/SGLocalizable.strings'))
lint = subprocess.run(['plutil', '-lint', *map(str, strings)], capture_output=True, text=True)
check('localizations', lint.returncode == 0, {'files': len(strings)})
summary = {'checks': len(checks), 'failed': [item for item in checks if not item['passed']], 'foundation': checks[:3], 'details': checks, 'scope': 'Independent Foundation and model/static checks; not a Swift build or device test.'}
folder.joinpath('fix-verification.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({key: summary[key] for key in ['checks', 'failed', 'foundation', 'scope']}, ensure_ascii=False, indent=2))
raise SystemExit(bool(summary['failed']))
