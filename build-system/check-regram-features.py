#!/usr/bin/env python3
"""Run account-free Regram regressions on macOS, without starting a simulator or publishing."""
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

    simple = 'Regram/RGSimpleSettings/'
    content_filter = (ROOT / 'submodules/AccountContext/Sources/RGContentFilter.swift').read_text()
    content_filter = content_filter[:content_filter.index('/// Emits on every message-filter')]
    for module in ['SwiftSignalKit', 'TelegramCore', 'RGSimpleSettings']:
        content_filter = content_filter.replace('import ' + module + '\n', '')
    content_source = output / 'ProductionContentFilter.swift'
    content_source.write_text(content_filter)
    suites = [
        ('filter', [simple+'Sources/MessageFilter.swift', simple+'Tests/MessageFilterTests.swift'], []),
        ('content-filter-cache', [simple+'Sources/MessageFilter.swift', str(content_source), simple+'Tests/ContentFilterStateTests.swift'], []),
        ('translation', ['Regram/RGGTranslate/Sources/RGTranslationLinkPlan.swift', 'Regram/RGGTranslate/Tests/LinkPlanTests.swift'], []),
        ('appearance', [simple+'Sources/TabBarLayoutPolicy.swift', simple+'Sources/FontSettings.swift', simple+'Tests/AppearancePolicyTests.swift'], []),
        ('mentions', [simple+'Sources/MentionReplacementPolicy.swift', simple+'Sources/FontSettings.swift', simple+'Tests/MentionReplacementPolicyTests.swift'], []),
        ('media-notifications', [simple+'Sources/'+name+'.swift' for name in ['MediaLoadingPolicy', 'MessageProcessingPolicy', 'VideoLoadingPolicy', 'VideoQualityPolicy', 'NotificationPolicy']] + [simple+'Tests/MediaLoadingPolicyTests.swift'], []),
        ('media-experiment-default', [simple+'Sources/'+name+'.swift' for name in ['MediaLoadingPolicy', 'MessageProcessingPolicy', 'VideoLoadingPolicy', 'VideoQualityPolicy', 'NotificationPolicy']] + [simple+'Tests/MediaLoadingPolicyTests.swift'], []),
        ('font-cascade', ['Regram/RGTypography/Sources/RGFontCascade.swift', 'Regram/RGTypography/Tests/FontCascadeTests.swift'], ['Regram/RGTypography/Fonts']),
        ('settings-search', ['Regram/RGStrings/Sources/RGProSearchIndex.swift', 'Regram/RGStrings/Tests/SettingsSearchTests.swift'], ['Regram/RGStrings/Strings']),
    ]
    for name, sources, arguments in suites:
        binary = output / name
        # Debug assertion configuration is intentional: the translation suite uses assert().
        flags = ['-DREGRAM_MEDIA_LOADING_EXPERIMENT'] if name == 'media-experiment-default' else []
        if run(name+'-compile', ['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors'] + flags + sources + ['-o', str(binary)]):
            run(name, [str(binary)] + arguments)
    run('font-store', ['python3', 'Regram/RGTypography/Tests/run-store-checks.py'])
    run('settings-runtime', ['python3', 'Regram/RGSimpleSettings/Tests/run-settings-runtime-checks.py'])
    run('revoked-history', ['python3', 'Regram/RGProUI/Tests/run-archive-checks.py'])
    run('localizations', ['plutil', '-lint'] + [f'Regram/RGStrings/Strings/{lang}.lproj/SGLocalizable.strings' for lang in ['en', 'zh-Hans', 'zh-Hant']])
    run('release-offline-mocks', ['python3', 'build-system/ci/test_release.py'])
    run('patch-format', ['git', 'diff', '--check'])
    report = {'scope': 'Production Foundation/CoreText/storage paths and offline release mocks; no simulator, device, accounts or uploads.', 'passed': all(result['passed'] for result in results), 'results': results}
    (output / 'results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
