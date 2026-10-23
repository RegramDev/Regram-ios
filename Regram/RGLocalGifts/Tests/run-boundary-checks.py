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
ui = (module / 'LocalGiftsController.swift').read_text()
assert 'cachedStarGifts()' not in ui and 'LazyVGrid' not in ui, 'Purchases belong in the native Telegram screens'
assert 'case let .unique(unique)' in projection and 'case .originalInfo:' in projection
assert 'slug: "", owner: .peerId(owner)' in projection and 'giftAddress: nil, resellAmounts: nil' in projection
assert 'case let .unique(gift)' in projection and 'state.filter.contains(.unique)' in projection
setup = (root / 'submodules/TelegramUI/Components/Gifts/GiftSetupScreen/Sources/GiftSetupScreen.swift').read_text()
method = setup.split('private func proceedWithStarGift() {', 1)[1].split('let context = component.context', 1)[0]
assert method.index('rgLocalGiftsEnabled') < method.index('let starsContext')
assert 'guard !self.inProgress, let controller = self.environment?.controller() else { return }' in method
assert 'rgPresentLocalGiftPurchase' in method and 'return' in method.split('rgPresentLocalGiftPurchase', 1)[1]
buy = (root / 'submodules/TelegramUI/Components/Gifts/GiftViewScreen/Sources/GiftViewBuyGift.swift').read_text()
local = buy.split('if beganLocally || rgLocalGiftsEnabled(context: context) {', 1)[1].split('let proceed: () -> Void', 1)[0]
assert 'finalPrice.amount.nanos == 0' in local and 'currency: currency' in local
assert 'LocalGifts.StarsOnly' not in local
assert 'rgPresentLocalGiftPurchase' in local and 'return' in local.split('rgPresentLocalGiftPurchase', 1)[1]
assert buy.index('if beganLocally ||') < buy.index('context.engine.payments.buyStarGift') < buy.index('makeStarsPurchaseScreen')
viewer = (root / 'submodules/TelegramUI/Components/Gifts/GiftViewScreen/Sources/GiftViewScreen.swift').read_text()
assert 'arguments.resellAmounts, !isOwn, !rgLocalGiftsEnabled(context: context)' in viewer
assert 'self.buyForm != nil || rgLocalGiftsEnabled(context: context)' in viewer
assert 'giftPurchaseAlertController(' in buy, 'Keep the native collectible confirmation'
confirmation = (root / 'submodules/TelegramUI/Components/Gifts/GiftViewScreen/Sources/GiftPurchaseAlertController.swift').read_text()
assert 'useLocalGiftBalance: true' in confirmation
payment_alert = (root / 'submodules/TelegramUI/Components/Chat/ChatMessagePaymentAlertController/Sources/ChatMessagePaymentAlertController.swift').read_text()
assert 'useLocalGiftBalance: Bool = false' in payment_alert, 'Real message payments must not use the local balance'
assert 'self.useLocalGiftBalance, rgLocalGiftsEnabled(context: context)' in payment_alert
list_view = (root / 'submodules/TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/GiftsListView.swift').read_text()
assert 'rgLocalGiftProfileState' in list_view
assert list_view.index('rgLocalGiftPurchaseId(gift: product) != nil') < list_view.index('let controller = GiftViewScreen')
assert 'subject: .profileGift(self.peerId, product)' in list_view
assert 'purchaseId:' not in ui, 'Owned gifts belong in the native viewer'
assert 'serverProducts.map' in list_view
pane = (root / 'submodules/TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/PeerInfoGiftsPaneNode.swift').read_text()
context_action = pane.split('private func contextAction(gift:', 1)[1]
assert context_action.index('rgLocalGiftPurchaseId') < context_action.index('var items: [ContextMenuItem]')
links = (root / 'submodules/TelegramUI/Sources/Chat/ChatControllerOpenLinkContextMenu.swift').read_text()
assert links.count('makeShareScreen(context: self.context, params: ShareControllerParams(subject: .url(url), externalShare: true, immediateExternalShare: false))') == 2
assert links.count('immediateExternalShareOverridingRGBehaviour: true') == 2
print('Local-only gift boundary and link-forward UI routing checks passed (source guards; not a device/network test)')

appearance = (module / 'LocalGiftAppearance.swift').read_text()
assert 'cacheLocalGiftInlineStickers' in appearance and 'rgLocalAppearancePeer' in appearance
native_appearance = (root / 'submodules/TelegramUI/Components/Settings/PeerNameColorScreen/Sources/UserApperanceScreen.swift').read_text()
apply = native_appearance.split('private func applySettings()', 1)[1]
assert apply.index('rgSaveLocalGiftAppearance') < apply.index('updateNameColorAndEmoji')
assert apply.index('rgIsLocalGiftAppearance') < apply.index('setStarGiftStatus')
assert 'localPurchaseId == nil else { return }' in viewer
assert 'rgDeleteLocalGift' in viewer and 'rgSetLocalGiftVisibility' in viewer
assert 'rgLocalGiftPurchaseId(gift: gift) == nil ? gift.text : nil' in viewer
assert 'model.localPremium = $0; RGSimpleSettings.shared.localPremium = $0' in ui
assert 'setPhone(account: model.account' in ui
