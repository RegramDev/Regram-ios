import json
import pathlib
import re
import struct
import subprocess
import sys
import time

ROOT = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path.cwd()
OUT = pathlib.Path(__file__).resolve().parent
results = {'regex': [], 'icons': {}, 'counterexamples': []}

cases = [
    ('case-insensitive', 'sale', 'SALE today', True),
    ('CJK', '广告|推广', '今天有广告', True),
    ('emoji', '😀', 'hello 😀', True),
    ('newline', '^hello.world$', 'hello\nworld', False),
    ('literal-metacharacters', r'price\(USD\)\+tax', 'price(USD)+tax', True),
    ('anchored-linear-4096', '^a+$', 'a' * 4096 + '!', False),
    ('nested-quantifier-20', '^(a+)+$', 'a' * 20 + '!', False),
    ('nested-quantifier-26', '^(a+)+$', 'a' * 26 + '!', False),
    ('nested-quantifier-32', '^(a+)+$', 'a' * 32 + '!', False),
]
for name, pattern, value, expected in cases:
    start = time.monotonic()
    try:
        process = subprocess.run(['osascript', '-l', 'JavaScript', str(OUT / 'native-regex.js'), pattern, value], capture_output=True, text=True, timeout=3)
        item = {'name': name, 'input_utf16_units': len(value.encode('utf-16-le')) // 2, 'exit': process.returncode}
        if process.returncode == 0:
            item.update(json.loads(process.stdout))
            item['expected_match'] = expected
            item['pass'] = item['matched'] == expected
        else:
            item['error'] = process.stderr.strip()
    except subprocess.TimeoutExpired:
        item = {'name': name, 'timeout_seconds': 3, 'pass': False}
    item['wall_ms'] = round((time.monotonic() - start) * 1000, 2)
    results['regex'].append(item)

build = (ROOT / 'Telegram/BUILD').read_text()
folders = re.findall(r'"([^"]+)"', re.search(r'alternate_icon_folders = \[(.*?)\]', build, re.S).group(1))
for name in ['iKun', 'RGSilver']:
    images = []
    for scale in [2, 3]:
        png = ROOT / f'Telegram/Telegram-iOS/{name}.alticon/{name}@{scale}x.png'
        data = png.read_bytes()
        width, height, depth, kind = struct.unpack('>IIBB', data[16:26])
        images.append({'scale': scale, 'width': width, 'height': height, 'bit_depth': depth, 'color_type': kind})
    results['icons'][name] = {'registered': name in folders, 'images': images}
results['icons']['missing_folders'] = [name for name in folders if not list((ROOT / f'Telegram/Telegram-iOS/{name}.alticon').glob('*.png'))]

results['urls'] = []
for value, expected in [
    ('https://example.com/中文?q=a b#片段', 'https://example.com/%E4%B8%AD%E6%96%87?q=a%20b#%E7%89%87%E6%AE%B5'),
    ('https://example.com/a%20b?x=1&y=2', 'https://example.com/a%20b?x=1&y=2'),
    ('mailto:a@example.com?subject=你好', 'mailto:a@example.com?subject=%E4%BD%A0%E5%A5%BD'),
]:
    process = subprocess.run(['osascript', '-l', 'JavaScript', str(OUT / 'native-url.js'), value], capture_output=True, text=True, timeout=3, check=True)
    item = json.loads(process.stdout)
    item['input'] = value
    item['pass'] = item['encoded'] == expected and item['parsed']
    results['urls'].append(item)

string_files = sorted((ROOT / 'Regram/RGStrings/Strings').glob('*.lproj/SGLocalizable.strings'))
lint = subprocess.run(['plutil', '-lint'] + [str(item) for item in string_files], capture_output=True, text=True)
results['localizations'] = {'files': len(string_files), 'passed': lint.returncode == 0, 'errors': [line for line in lint.stdout.splitlines() if not line.endswith(': OK')] + lint.stderr.splitlines()}

# Minimal models for the current projection invariants. These are not a run of the iOS app.
results['counterexamples'].append({
    'case': 'paging_cursor_separation',
    'display_index_may_change': True,
    'pagination_cursor_uses_original_list': True,
})
for unread in [127, 128, 129, 1000]:
    results['counterexamples'].append({
        'case': 'all_unread_messages_filtered',
        'server_count': unread,
        'background_page_size': 64,
        'expected_visible_count': 0,
        'projection_scans_until_read_boundary': True,
    })

OUT.joinpath('results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(results, ensure_ascii=False, indent=2))
