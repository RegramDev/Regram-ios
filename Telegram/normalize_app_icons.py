#!/usr/bin/env python3
"""Keep Icon Composer names alongside legacy PNG fallback declarations before codesigning."""
from pathlib import Path
import plistlib
import sys


def normalize(archive):
    apps = [path for path in archive.glob('Payload/*.app') if path.is_dir()]
    if not apps:
        apps = [path for path in archive.glob('*.app') if path.is_dir()]
    if len(apps) != 1:
        raise ValueError('Expected one main application bundle')
    path = apps[0] / 'Info.plist'
    info = plistlib.loads(path.read_bytes())
    for family in ('CFBundleIcons', 'CFBundleIcons~ipad'):
        metadata = info.get(family, {})
        for name, definition in metadata.get('CFBundleAlternateIcons', {}).items():
            # iOS keeps a previous identifier across upgrades. Its composer asset uses RG.
            canonical = 'RG' + name[2:] if name.startswith('SG') else name
            definition['CFBundleIconName'] = canonical
    path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY, sort_keys=False))


if __name__ == '__main__':
    normalize(Path(sys.argv[1]))
