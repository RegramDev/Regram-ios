import json
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path.cwd()
entry_paths = [
    'Regram/RGSettingsUI/Sources/RGSettingsController.swift',
    'Regram/RGProUI/Sources/RGProUI.swift',
    'Regram/RGProUI/Sources/RGPrivacyToolsController.swift',
]
settings_path = 'Regram/RGSimpleSettings/Sources/SimpleSettings.swift'
properties = set(re.findall(r'public (?:var|let) (\w+)', (root / settings_path).read_text()))
names = set()
for name in entry_paths:
    text = '\n'.join(line for line in (root / name).read_text().splitlines() if not line.lstrip().startswith('//'))
    names.update(re.findall(r'(?:RGSimpleSettings\.shared|settings)\.(\w+)', text))
names &= properties
pattern = r'\.(' + '|'.join(sorted(names)) + r')\b'
process = subprocess.run(['rg', '--json', '-n', '--glob', '*.swift', pattern, 'Regram', 'submodules', 'Telegram'], cwd=root, capture_output=True, text=True, check=False)
refs = {name: set() for name in names}
for raw in process.stdout.splitlines():
    item = json.loads(raw)
    if item.get('type') != 'match':
        continue
    data = item['data']
    filename = data['path']['text']
    if filename in entry_paths or filename == settings_path:
        continue
    for name in re.findall(pattern, data['lines']['text']):
        refs[name].add(f"{filename}:{data['line_number']}")
result = {'ui_properties': len(names), 'properties': {name: sorted(items) for name, items in sorted(refs.items())}, 'without_external_reference': sorted(name for name, items in refs.items() if not items)}
pathlib.Path(__file__).resolve().with_name('feature-references.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'ui_properties': result['ui_properties'], 'without_external_reference': result['without_external_reference'], 'reference_counts': {name: len(items) for name, items in sorted(refs.items())}}, ensure_ascii=False, indent=2))
