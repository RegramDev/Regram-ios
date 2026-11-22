#!/usr/bin/env python3
"""Run account-free Reza regressions on macOS, without starting a simulator or publishing."""
import argparse
import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build-input/local-feature-checks')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    results = []

    def run(name, command):
        begin = time.monotonic()
        try:
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180)
            text = result.stdout + result.stderr
            code = result.returncode
        except subprocess.TimeoutExpired:
            text, code = 'Check exceeded 180 seconds.\n', 124
        (output / (name + '.log')).write_text(text)
        results.append({'check': name, 'passed': code == 0, 'seconds': round(time.monotonic() - begin, 3), 'log': name + '.log'})
        print(f'{name}: {"PASS" if code == 0 else "FAIL"}', flush=True)
        return code == 0

    simple = 'Reza/RGSimpleSettings/'
    content_filter = (ROOT / 'submodules/AccountContext/Sources/RGContentFilter.swift').read_text()
    content_filter = content_filter[:content_filter.index('/// Emits on every message-filter')]
    for module in ['SwiftSignalKit', 'TelegramCore', 'RGSimpleSettings']:
        content_filter = content_filter.replace('import ' + module + '\n', '')
    content_source = output / 'ProductionContentFilter.swift'
    content_source.write_text(content_filter)
    suites = [
        ('quote-selection', [simple+'Sources/RGFeaturePangu.swift', simple+'Sources/RGMessageQuoteSelection.swift', simple+'Tests/MessageQuoteSelectionTests.swift'], []),
        ('local-gifts', [simple+'Sources/LocalGifts.swift', simple+'Tests/LocalGiftsTests.swift'], []),
        ('filter', [simple+'Sources/MessageFilter.swift', simple+'Tests/MessageFilterTests.swift'], []),
        ('diagnostics', [simple+'Sources/MessageFilter.swift', simple+'Sources/TransferStatistics.swift', simple+'Sources/FilterBenchmark.swift', simple+'Tests/DiagnosticsTests.swift'], []),
        ('content-filter-cache', [simple+'Sources/MessageFilter.swift', simple+'Sources/GroupMemberSelection.swift', str(content_source), simple+'Tests/ContentFilterStateTests.swift'], []),
        ('translation', ['Reza/RGGTranslate/Sources/RGTranslationLinkPlan.swift', 'Reza/RGGTranslate/Tests/LinkPlanTests.swift'], []),
        ('datacenter-statistics', [simple+'Sources/RGDatacenterStatistics.swift', simple+'Tests/DatacenterStatisticsTests.swift'], []),
        ('bottom-bar', [simple+'Sources/RGBottomBarSettings.swift', simple+'Sources/TabBarLayoutPolicy.swift', simple+'Sources/RGDatacenterLocation.swift', simple+'Tests/BottomBarSettingsTests.swift'], []),
        ('appearance', [simple+'Sources/TabBarLayoutPolicy.swift', simple+'Sources/FontSettings.swift', simple+'Tests/AppearancePolicyTests.swift'], []),
        ('mentions', [simple+'Sources/MentionReplacementPolicy.swift', simple+'Sources/FontSettings.swift', simple+'Tests/MentionReplacementPolicyTests.swift'], []),
        ('media-notifications', [simple+'Sources/'+name+'.swift' for name in ['MediaLoadingPolicy', 'MessageProcessingPolicy', 'VideoLoadingPolicy', 'VideoQualityPolicy', 'NotificationPolicy']] + [simple+'Tests/MediaLoadingPolicyTests.swift'], []),
        ('media-experiment-default', [simple+'Sources/'+name+'.swift' for name in ['MediaLoadingPolicy', 'MessageProcessingPolicy', 'VideoLoadingPolicy', 'VideoQualityPolicy', 'NotificationPolicy']] + [simple+'Tests/MediaLoadingPolicyTests.swift'], []),
        ('font-cascade', ['Reza/RGTypography/Sources/RGFontCascade.swift', 'Reza/RGTypography/Tests/FontCascadeTests.swift'], ['Reza/RGTypography/Fonts']),
        ('settings-catalog', ['Reza/RGStrings/Sources/RGSettingsLink.swift', 'Reza/RGStrings/Sources/RGSettingsCatalog.swift', 'Reza/RGStrings/Sources/RGProSearchIndex.swift', 'Reza/RGStrings/Tests/SettingsCatalogTests.swift'], ['Reza/RGStrings/Strings']),
        ('settings-search', ['Reza/RGStrings/Sources/RGProSearchIndex.swift', 'Reza/RGStrings/Tests/SettingsSearchTests.swift'], ['Reza/RGStrings/Strings']),
        ('local-app-links', ['Reza/RGSettingsUI/Sources/RGLocalAppLink.swift', 'Reza/RGSettingsUI/Tests/LocalAppLinkTests.swift'], []),
        ('common-group-search-policy', ['Reza/RGCommonGroupMessagesUI/Sources/RGCommonGroupSearchPolicy.swift', 'Reza/RGCommonGroupMessagesUI/Tests/SearchPolicyTests.swift'], []),
    ]
    for name, sources, arguments in suites:
        binary = output / name
        # Debug assertion configuration is intentional: the translation suite uses assert().
        flags = ['-DREZA_MEDIA_LOADING_EXPERIMENT'] if name == 'media-experiment-default' else []
        if run(name+'-compile', ['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors'] + flags + sources + ['-o', str(binary)]):
            run(name, [str(binary)] + arguments)
    run('rich-message-tools', ['python3', 'Reza/RGProUI/Tests/run-rich-message-checks.py'])
    run('rich-edit-history-codec', ['python3', 'Reza/RGProUI/Tests/run-edit-history-checks.py'])
    run('translation-chunk-sequencing', ['python3', 'Reza/RGGTranslate/Tests/run-chunk-sequencing-checks.py'])
    run('summary-range-failures', ['python3', 'Reza/RGProUI/Tests/run-summary-range-checks.py'])
    run('message-retention', ['python3', 'build-system/check-reza-retention.py'])
    run('story-flag-persistence', ['python3', 'build-system/check-reza-story-flags.py'])
    run('local-gift-boundary', ['python3', 'Reza/RGLocalGifts/Tests/run-boundary-checks.py'])
    run('local-phone-display', ['python3', 'Reza/RGLocalGifts/Tests/run-phone-display-checks.py'])
    run('local-profile-projection', ['python3', 'Reza/RGLocalGifts/Tests/run-profile-projection-checks.py'])
    run('local-appearance-projection', ['python3', 'Reza/RGLocalGifts/Tests/run-appearance-projection-checks.py'])
    run('localization-manager', ['python3', 'Reza/RGStrings/Tests/run-localization-checks.py'])
    run('settings-search-transitions', ['python3', 'Reza/RGProUI/Tests/run-settings-search-checks.py'])
    run('common-group-pagination', ['python3', 'Reza/RGCommonGroupMessagesUI/Tests/run-search-failure-checks.py'])
    run('anti-revoke-senders', ['python3', 'Reza/RGSimpleSettings/Tests/run-anti-revoke-checks.py'])
    run('font-store', ['python3', 'Reza/RGTypography/Tests/run-store-checks.py'])
    run('common-group-table-navigation', ['python3', 'Reza/RGCommonGroupMessagesUI/Tests/run-table-navigation-checks.py'])
    run('settings-focus', ['python3', 'Reza/RGSettingsUI/Tests/run-settings-focus-checks.py'])
    run('group-member-ui-flow', ['python3', 'Reza/RGSettingsUI/Tests/run-group-member-ui-checks.py'])
    run('settings-import-menu', ['python3', 'Reza/RGSettingsUI/Tests/run-settings-import-menu-checks.py'])
    run('startup-folder', ['python3', 'Reza/RGSettingsUI/Tests/run-startup-folder-checks.py'])
    run('settings-row-touch', ['python3', 'Reza/RGSettingsUI/Tests/run-settings-row-touch-checks.py'])
    run('root-settings-gesture', ['python3', 'Reza/RGSimpleSettings/Tests/run-root-settings-gesture-checks.py'])
    run('root-tab-transition', ['python3', 'Reza/RGSimpleSettings/Tests/run-root-tab-transition-checks.py'])
    run('navigation-capsules', ['python3', 'Reza/RGSimpleSettings/Tests/run-navigation-capsule-checks.py'])
    run('profile-navigation-colors', ['python3', 'Reza/RGSettingsUI/Tests/run-profile-navigation-color-checks.py'])
    run('settings-runtime', ['python3', 'Reza/RGSimpleSettings/Tests/run-settings-runtime-checks.py'])
    run('group-member-notifications', ['python3', 'Reza/RGSimpleSettings/Tests/run-group-notification-checks.py'])
    run('chat-action-policies', ['python3', 'Reza/RGSimpleSettings/Tests/run-chat-action-checks.py'])
    run('remark-search', ['python3', 'Reza/RGSimpleSettings/Tests/run-group-remark-search-checks.py'])
    run('search-typing', ['python3', 'Reza/RGSimpleSettings/Tests/run-search-typing-checks.py'])
    run('search-rendering', ['python3', 'Reza/RGSimpleSettings/Tests/run-search-rendering-checks.py'])
    run('ui-cache-regressions', ['python3', 'Reza/RGSimpleSettings/Tests/run-ui-cache-regression-checks.py'])
    run('tab-selection-regressions', ['python3', 'Reza/RGSimpleSettings/Tests/run-tab-selection-checks.py'])
    run('native-photo-regressions', ['python3', 'Reza/RGSimpleSettings/Tests/run-native-photo-checks.py'])
    run('permission-warning-badges', ['python3', 'Reza/RGFeatureSignals/Tests/run-permission-warning-checks.py'])
    run('llm-endpoint-urls', ['python3', 'Reza/RGGTranslate/Tests/run-url-checks.py'])
    run('transcription-routing', ['python3', 'Reza/RGTranscription/Tests/run-routing-checks.py'])
    run('visible-mention-reads', ['python3', 'Reza/RGChatHistoryProcessing/Tests/run-visible-read-checks.py'])
    run('filtered-mention-reads', ['python3', 'Reza/RGChatHistoryProcessing/Tests/run-filtered-mention-checks.py'])
    run('settings-storage', ['python3', 'Reza/RGAppGroupIdentifier/Tests/run-storage-checks.py'])
    run('build-configuration', ['python3', 'build-system/ci/test_configuration.py'])
    run('gallery-playback', ['python3', 'Reza/RGGalleryUI/Tests/run-playback-checks.py'])
    run('album-video-duration', ['python3', 'Reza/RGGalleryUI/Tests/run-album-duration-checks.py'])
    run('gallery-media-save', ['python3', 'Reza/RGGalleryUI/Tests/run-save-checks.py'])
    run('local-pinned-chats', ['python3', 'Reza/RGSimpleSettings/Tests/run-local-pinned-chats-checks.py'])
    run('search-links', ['python3', 'Reza/RGSearchLink/Tests/run-search-link-checks.py'])
    run('inline-bot-queries', ['python3', 'Reza/RGLinkMetadata/Tests/run-inline-query-checks.py'])
    run('invite-revocation', ['python3', 'Reza/RGSimpleSettings/Tests/run-invite-revocation-checks.py'])
    run('revoked-history', ['python3', 'Reza/RGProUI/Tests/run-archive-checks.py'])
    run('localizations', ['plutil', '-lint'] + [f'Reza/RGStrings/Strings/{lang}.lproj/RGLocalizable.strings' for lang in ['en', 'zh-Hans', 'zh-Hant']])
    run('release-offline-mocks', ['python3', 'build-system/ci/test_release.py'])
    run('patch-format', ['git', 'diff', '--check'])
    report = {'scope': 'Production Foundation/CoreText/storage paths and offline release mocks; no simulator, device, accounts or uploads.', 'passed': all(result['passed'] for result in results), 'results': results}
    (output / 'results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
