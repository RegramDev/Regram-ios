#!/usr/bin/env python3
"""Check default-only app icons, adaptive badges and retired-artwork removal.

This inspects source resources only; it does not build or launch the application.
"""
from pathlib import Path
import argparse
import json
import plistlib
import struct
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / 'Regram/RGBranding'
NAMES = ('RGConversation', 'RGGathering')
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compiled-icons-plist', type=Path, help='Optional actool partial Info.plist to validate iPhone/iPad icon declarations')
args = parser.parse_args()


def png(path):
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path
    return struct.unpack('>IIBB', data[16:26])


def appearance(image):
    values = {item['appearance']: item['value'] for item in image.get('appearances', [])}
    return values.get('luminosity', 'light')


def catalog(path, modes):
    contents = json.loads((path / 'Contents.json').read_text())
    images = contents['images']
    assert {appearance(image) for image in images} == modes, path
    if modes == {'light'}:
        assert len(images) == 1 and 'appearances' not in images[0], (path, 'expected one default image')
    for image in images:
        filename = image['filename']
        # Keep the requested appearance mapping explicit, regardless of its palette.
        assert f'-{appearance(image)}' in filename, (path, image)
        assert (path / filename).is_file(), (path, filename)
    referenced = {image['filename'] for image in images}
    assert {p.name for p in path.iterdir() if p.suffix == '.png'} == referenced, path
    return images


assert {path.stem for path in (BRAND / 'AppIcons.xcassets').glob('*.appiconset')} == set(NAMES)
badge_root = ROOT / 'Regram/RGAppBadgeAssets/Images.xcassets'
assert {path.stem for path in badge_root.glob('*.imageset')} == {name + 'Badge' for name in NAMES}

for name in NAMES:
    iconset = BRAND / 'AppIcons.xcassets' / (name + '.appiconset')
    for image in catalog(iconset, {'light'}):
        width, height, depth, kind = png(iconset / image['filename'])
        assert (width, height, depth, kind) == (1024, 1024, 8, 2), (name, image)
    preview = BRAND / 'Images.xcassets' / (name + 'Preview.imageset')
    for image in catalog(preview, {'light'}):
        assert png(preview / image['filename'])[:2] == (256, 256)
    badge = badge_root / (name + 'Badge.imageset')
    images = catalog(badge, {'light', 'dark'})
    assert {(appearance(image), image['scale']) for image in images} == {
        (mode, f'{scale}x') for mode in ('light', 'dark') for scale in (1, 2, 3)
    }
    for image in images:
        scale = int(image['scale'][0])
        width, height, depth, kind = png(badge / image['filename'])
        assert (width, height, depth, kind) == (112 * scale, 28 * scale, 8, 6), image

    vector = ET.parse(BRAND / f'Artwork/{name}-light.svg').getroot()
    background = next(element.attrib['fill'] for element in vector if element.tag.endswith('rect'))
    assert background == '#F3EADC', (name, 'default background must use the requested beige')

assert {path.name for path in (BRAND / 'Artwork').glob('*.svg')} == {f'{name}-light.svg' for name in NAMES}

for folder in ('Regram/RGSettingsUI/Images.xcassets/RegramPro.imageset',
               'Regram/RGSettingsUI/Images.xcassets/RegramSettings.imageset',
               'Telegram/WidgetKitWidget/WidgetImages.xcassets/RegramUpdateIcon.imageset'):
    catalog(ROOT / folder, {'light'})

assert not list((ROOT / 'Telegram/Telegram-iOS').glob('*.alticon'))
for retired in ('Telegram/Telegram-iOS/DefaultAppIcon.xcassets', 'Telegram/Telegram-iOS/Regram.icon',
                'Telegram/Telegram-iOS/RegramLegacy.icon',
                'submodules/TelegramUI/Images.xcassets/Components/AppBadge.imageset'):
    assert not (ROOT / retired).exists(), retired

build = (ROOT / 'Telegram/BUILD').read_text()
assert 'primary_app_icon = "RGConversation"' in build and '"//Regram/RGBranding:AppIcons"' in build
assert '"//Regram/RGBranding:Images"' in build
assert 'rg_renamed_icon_folders' not in build and 'alternate_icon_folders' not in build
plist = plistlib.loads((ROOT / 'Telegram/Telegram-iOS/Info.plist').read_bytes())
assert 'CFBundleIcons' not in plist and 'CFBundleIcons~ipad' not in plist

if args.compiled_icons_plist is not None:
    compiled = plistlib.loads(args.compiled_icons_plist.read_bytes())
    for family in ('CFBundleIcons', 'CFBundleIcons~ipad'):
        icons = compiled[family]
        assert icons['CFBundlePrimaryIcon']['CFBundleIconName'] == NAMES[0], family
        assert set(icons['CFBundleAlternateIcons']) == {NAMES[1]}, family
        assert icons['CFBundleAlternateIcons'][NAMES[1]]['CFBundleIconName'] == NAMES[1], family
    print('Compiled iPhone/iPad icon declarations match the actual primary and alternate asset names.')

for lang in ('en', 'zh-hans', 'zh-hant'):
    strings = (ROOT / f'Regram/RGStrings/Strings/{lang}.lproj/RGLocalizable.strings').read_text()
    for kind in ('conversation', 'gathering'):
        assert f'"AppIcon.Name.{kind}"' in strings and f'"AppBadge.Name.{kind}"' in strings
    assert '"AppBadge.Name.default"' not in strings

print('Branding checks passed: two families, one default image per app icon with no custom dark/tinted slots, '
      'opaque 1024px icons, adaptive 112×28pt light/dark alpha badges, default-only preview/product assets, three languages '
      'and retired icon/badge resources removed. No app build or device run.')
