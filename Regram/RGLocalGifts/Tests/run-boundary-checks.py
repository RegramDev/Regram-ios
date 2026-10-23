#!/usr/bin/env python3
"""Guard the local-only gift boundary and native UI routing; ledger behavior has Swift tests."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[3]
module = root / 'Regram/RGLocalGifts/Sources'
source = '\n'.join(p.read_text() for p in module.glob('*.swift'))
for forbidden in [r'\.network\b', r'\.request\s*\(', r'\bURLSession\b', r'\bfetchedResource\b', r'\bkeepStarGiftsUpdated\b', r'\bsendStarsPaymentForm\b', r'\btransferStarGift\b', r'\bconvertStarGift\b', r'\bupdateStarGiftAddedToProfile\b']:
    assert not re.search(forbidden, source), forbidden
projection = (module / 'LocalGifts.swift').read_text()
assert 'peerId == context.account.peerId, profileGifts.collectionId == nil, !canSelect' in projection
assert 'reference: nil' in projection and 'canUpgrade: false' in projection
assert 'completedResourcePath' in projection and 'LocalFileReferenceMediaResource' in projection
assert 'cachedStarGifts()' in source
setup = (root / 'submodules/TelegramUI/Components/Gifts/GiftSetupScreen/Sources/GiftSetupScreen.swift').read_text()
method = setup.split('private func proceedWithStarGift() {', 1)[1].split('let context = component.context', 1)[0]
assert method.index('rgLocalGiftsEnabled') < method.index('let starsContext')
assert 'guard !self.inProgress, let controller = self.environment?.controller() else { return }' in method
assert 'rgPresentLocalGiftPurchase' in method and 'return' in method.split('rgPresentLocalGiftPurchase', 1)[1]
list_view = (root / 'submodules/TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/GiftsListView.swift').read_text()
assert 'rgLocalGiftProfileState' in list_view
assert list_view.index('let purchase = rgLocalPurchase') < list_view.index('let controller = GiftViewScreen')
assert 'serverProducts.map' in list_view
pane = (root / 'submodules/TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/PeerInfoGiftsPaneNode.swift').read_text()
context_action = pane.split('private func contextAction(gift:', 1)[1]
assert context_action.index('rgLocalPurchase') < context_action.index('var items: [ContextMenuItem]')
links = (root / 'submodules/TelegramUI/Sources/Chat/ChatControllerOpenLinkContextMenu.swift').read_text()
assert links.count('makeShareScreen(context: self.context, params: ShareControllerParams(subject: .url(url), externalShare: true, immediateExternalShare: false))') == 2
assert links.count('immediateExternalShareOverridingRGBehaviour: true') == 2
print('Local-only gift boundary and link-forward UI routing checks passed (source guards; not a device/network test)')
