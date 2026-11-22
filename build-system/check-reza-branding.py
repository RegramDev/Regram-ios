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
BRAND = ROOT / 'Reza/RGBranding'
VECTOR_NAMES = ('RGConversation', 'RGAzure', 'RGIris', 'RGMint', 'RGGathering', 'RGAmber', 'RGNebula', 'RGJade')
LEGACY_NAMES = VECTOR_NAMES + ('RGClassic', 'RGXChat', 'RGTelegram')
CAT_NAMES = ('RGCatOrange', 'RGCatCalico', 'RGCatSiamese', 'RGCatTuxedo')
NAMES = CAT_NAMES + LEGACY_NAMES
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
assert {path.stem for path in (BRAND / 'Images.xcassets').glob('*.imageset')} == {name + 'Preview' for name in NAMES}
badge_root = ROOT / 'Reza/RGAppBadgeAssets/Images.xcassets'
assert {path.stem for path in badge_root.glob('*.imageset')} == {name + 'Badge' for name in VECTOR_NAMES} | {'RGRezaBadge', 'RegramAppBadge', 'ZhiqiuAppBadge'}
reza_badge = badge_root / 'RGRezaBadge.imageset'
peek_master = ET.parse(BRAND / 'Artwork/PeekingTabby.svg').getroot()
assert peek_master.get('viewBox') == '0 0 48 28' and not any(node.tag.endswith('}text') for node in peek_master.iter())
peek_slots = catalog(reza_badge, {'light', 'dark'})
assert {(appearance(entry), entry['scale']) for entry in peek_slots} == {
    (mode, f'{scale}x') for mode in ('light', 'dark') for scale in (1, 2, 3)
}
for entry in peek_slots:
    scale = int(entry['scale'][0])
    assert png(reza_badge / entry['filename']) == (48 * scale, 28 * scale, 8, 6)

for name in CAT_NAMES:
    assert (BRAND / 'Artwork' / f'{name}-original.png').is_file()
    for folder, size in [(f'AppIcons.xcassets/{name}.appiconset', 1024), (f'Images.xcassets/{name}Preview.imageset', 256)]:
        path = BRAND / folder
        for image in catalog(path, {'light', 'dark'}):
            assert png(path / image['filename']) == (size, size, 8, 2), (name, image)
        assert (path / f'{name}-light.png').read_bytes() == (path / f'{name}-dark.png').read_bytes(), path

for name in LEGACY_NAMES:
    iconset = BRAND / 'AppIcons.xcassets' / (name + '.appiconset')
    for image in catalog(iconset, {'light', 'dark'}):
        width, height, depth, kind = png(iconset / image['filename'])
        assert (width, height, depth, kind) == (1024, 1024, 8, 2), (name, image)
    preview = BRAND / 'Images.xcassets' / (name + 'Preview.imageset')
    for image in catalog(preview, {'light', 'dark'}):
        assert png(preview / image['filename'])[:2] == (256, 256)
    if name in ('RGXChat', 'RGTelegram'):
        # These original icons use the same artwork in both appearances.
        for imageset in (iconset, preview):
            assert (imageset / f'{name}-light.png').read_bytes() == (imageset / f'{name}-dark.png').read_bytes(), imageset
        continue
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

    for mode, expected in [('light', '#F3EADC'), ('dark', '#242426')]:
        vector = ET.parse(BRAND / f'Artwork/{name}-{mode}.svg').getroot()
        background = next(element.attrib['fill'] for element in vector if element.tag.endswith('rect'))
        assert background == expected, (name, mode, 'background must use the requested palette')

assert {path.name for path in (BRAND / 'Artwork').glob('*.svg')} == {f'{name}-{mode}.svg' for name in VECTOR_NAMES for mode in ('light', 'dark')} | {'PeekingTabby.svg'}
for name, size in [('Regram', (261, 66)), ('Zhiqiu', (235, 66))]:
    imageset = badge_root / f'{name}AppBadge.imageset'
    images = json.loads((imageset / 'Contents.json').read_text())['images']
    files = [entry for entry in images if 'filename' in entry]
    assert len(files) == 1 and files[0]['scale'] == '3x'
    assert png(imageset / files[0]['filename'])[:2] == size

for folder in ('Reza/RGSettingsUI/Images.xcassets/RezaPro.imageset',
               'Reza/RGSettingsUI/Images.xcassets/RezaSettings.imageset',
               'Telegram/WidgetKitWidget/WidgetImages.xcassets/RezaUpdateIcon.imageset'):
    for entry in catalog(ROOT / folder, {'light', 'dark'}):
        role = 'AppIcons.xcassets/RGCatOrange.appiconset' if folder.endswith('/RezaPro.imageset') else 'Images.xcassets/RGCatOrangePreview.imageset'
        primary = BRAND / role / f'RGCatOrange-{appearance(entry)}.png'
        assert (ROOT / folder / entry['filename']).read_bytes() == primary.read_bytes(), folder

assert not list((ROOT / 'Telegram/Telegram-iOS').glob('*.alticon'))
for retired in ('Telegram/Telegram-iOS/DefaultAppIcon.xcassets', 'Telegram/Telegram-iOS/Regram.icon',
                'Telegram/Telegram-iOS/RegramLegacy.icon',
                'submodules/TelegramUI/Images.xcassets/Components/AppBadge.imageset'):
    assert not (ROOT / retired).exists(), retired

build = (ROOT / 'Telegram/BUILD').read_text()
assert 'primary_app_icon = "RGCatOrange"' in build and '"//Reza/RGBranding:AppIcons"' in build
assert '"//Reza/RGBranding:Images"' in build
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
    print(f'Compiled iPhone/iPad app icons contain default and dark renditions for all {len(NAMES)} styles.')

for lang in ('en', 'zh-hans', 'zh-hant'):
    strings = (ROOT / f'Reza/RGStrings/Strings/{lang}.lproj/RGLocalizable.strings').read_text()
    for kind in ('conversation', 'azure', 'iris', 'mint', 'gathering', 'amber', 'nebula', 'jade'):
        assert f'"AppIcon.Name.{kind}"' in strings and f'"AppBadge.Name.{kind}"' in strings
    for key in ('AppIcon.Name.classic', 'AppIcon.Name.xchat', 'AppIcon.Name.telegram', 'AppBadge.Name.regram', 'AppBadge.Name.zhiqiu', 'AppBadge.Enable', 'AppBadge.Preview'):
        assert f'"{key}"' in strings
    for key in ('AppIcon.Name.orangeTabby', 'AppIcon.Name.calico', 'AppIcon.Name.siamese', 'AppIcon.Name.tuxedo',
                'AppBadge.Name.reza', 'AdSamples.PerChat.Records', 'AdSamples.PerChat.Empty'):
        assert f'"{key}"' in strings
    assert '"AppBadge.Name.default"' not in strings

print(f'Branding checks passed: {len(NAMES)} app icons with explicit light/dark slots from shared sources, '
      'opaque 1024px icons, 48×28pt wordless tabby and 112×28pt classic light/dark badges, matching preview/product assets, three languages '
      'and both original badges. No app build or device run.')
