#!/usr/bin/env python3
"""Check explicit light/dark artwork, adaptive badges and retired-artwork removal.

This inspects source resources only; it does not build or launch the application.
"""
from pathlib import Path
import argparse
import json
import plistlib
import struct
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / 'Regram/RGBranding'
VECTOR_NAMES = ('RGConversation', 'RGAzure', 'RGIris', 'RGMint', 'RGGathering', 'RGAmber', 'RGNebula', 'RGJade')
NAMES = VECTOR_NAMES + ('RGClassic',)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compiled-icons-plist', type=Path, help='Optional actool partial Info.plist to validate iPhone/iPad icon declarations')
parser.add_argument('--compiled-catalog', type=Path, help='Optional Assets.car to validate the compiled appearance renditions')
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
assert {path.stem for path in badge_root.glob('*.imageset')} == {name + 'Badge' for name in VECTOR_NAMES} | {'RegramAppBadge', 'ZhiqiuAppBadge'}

for name in NAMES:
    iconset = BRAND / 'AppIcons.xcassets' / (name + '.appiconset')
    for image in catalog(iconset, {'light', 'dark'}):
        width, height, depth, kind = png(iconset / image['filename'])
        assert (width, height, depth, kind) == (1024, 1024, 8, 2), (name, image)
    preview = BRAND / 'Images.xcassets' / (name + 'Preview.imageset')
    for image in catalog(preview, {'light', 'dark'}):
        assert png(preview / image['filename'])[:2] == (256, 256)
    assert (iconset / f'{name}-light.png').read_bytes() != (iconset / f'{name}-dark.png').read_bytes(), name
    if name == 'RGClassic':
        continue
    badge = badge_root / (name + 'Badge.imageset')
    images = catalog(badge, {'light', 'dark'})
    assert {(appearance(image), image['scale']) for image in images} == {
        (mode, f'{scale}x') for mode in ('light', 'dark') for scale in (1, 2, 3)
    }
    for image in images:
        scale = int(image['scale'][0])
        width, height, depth, kind = png(badge / image['filename'])
        assert (width, height, depth, kind) == (112 * scale, 28 * scale, 8, 6), image

    for mode, expected in [('light', '#F3EADC'), ('dark', '#E5E5EA')]:
        vector = ET.parse(BRAND / f'Artwork/{name}-{mode}.svg').getroot()
        background = next(element.attrib['fill'] for element in vector if element.tag.endswith('rect'))
        assert background == expected, (name, mode, 'background must use the requested palette')

assert {path.name for path in (BRAND / 'Artwork').glob('*.svg')} == {f'{name}-{mode}.svg' for name in VECTOR_NAMES for mode in ('light', 'dark')}
for name, size in [('Regram', (261, 66)), ('Zhiqiu', (235, 66))]:
    imageset = badge_root / f'{name}AppBadge.imageset'
    images = json.loads((imageset / 'Contents.json').read_text())['images']
    files = [entry for entry in images if 'filename' in entry]
    assert len(files) == 1 and files[0]['scale'] == '3x'
    assert png(imageset / files[0]['filename'])[:2] == size

for folder in ('Regram/RGSettingsUI/Images.xcassets/RegramPro.imageset',
               'Regram/RGSettingsUI/Images.xcassets/RegramSettings.imageset',
               'Telegram/WidgetKitWidget/WidgetImages.xcassets/RegramUpdateIcon.imageset'):
    catalog(ROOT / folder, {'light', 'dark'})

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
        assert set(icons['CFBundleAlternateIcons']) == set(NAMES[1:]), family
        for name in NAMES[1:]:
            assert icons['CFBundleAlternateIcons'][name]['CFBundleIconName'] == name, (family, name)
    print('Compiled iPhone/iPad icon declarations match the actual primary and alternate asset names.')

if args.compiled_catalog is not None:
    renditions = json.loads(subprocess.check_output(['/usr/bin/assetutil', '--info', str(args.compiled_catalog)]))
    for name in NAMES:
        for idiom in ('phone', 'pad'):
            icons = [r for r in renditions if r.get('Name') == name and r.get('AssetType') == 'Icon Image' and r.get('Idiom') == idiom]
            assert {r.get('Appearance', 'UIAppearanceAny') for r in icons} == {'UIAppearanceAny', 'UIAppearanceDark'}, (name, idiom)
            for rendition in icons:
                mode = 'dark' if rendition.get('Appearance') == 'UIAppearanceDark' else 'light'
                assert rendition['RenditionName'] == f'{name}-{mode}.png', (name, rendition)
    print('Compiled iPhone/iPad app icons contain distinct default and dark renditions for all nine styles.')

for lang in ('en', 'zh-hans', 'zh-hant'):
    strings = (ROOT / f'Regram/RGStrings/Strings/{lang}.lproj/RGLocalizable.strings').read_text()
    for kind in ('conversation', 'azure', 'iris', 'mint', 'gathering', 'amber', 'nebula', 'jade'):
        assert f'"AppIcon.Name.{kind}"' in strings and f'"AppBadge.Name.{kind}"' in strings
    for key in ('AppIcon.Name.classic', 'AppBadge.Name.regram', 'AppBadge.Name.zhiqiu'):
        assert f'"{key}"' in strings
    assert '"AppBadge.Name.default"' not in strings

print('Branding checks passed: nine app icons with explicit light/dark slots from shared sources, '
      'opaque 1024px icons, adaptive 112×28pt light/dark alpha badges, matching preview/product assets, three languages '
      'and two preserved original badges. No app build or device run.')
