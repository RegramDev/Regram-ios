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
assert 'reference: nil' in projection and 'canUpgrade: canUpgrade' in projection
assert 'rgUpgradeLocalGift' in projection and 'expectedGift: upgrading.gift' in projection
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
upgrade = viewer.split('func commitUpgrade()', 1)[1].split('func openUpgradePricePreview()', 1)[0]
assert upgrade.index('rgUpgradeLocalGift') < upgrade.index('upgradeStarGift('), 'Local upgrades must return before the server mutation'
assert 'self.subject.localPurchaseId == nil else { return }' in viewer.split('private func fetchUpgradeForm()', 1)[1].split('private(set) var effectiveUpgradePrice', 1)[0]
assert 'rgDeleteLocalGift' in viewer and 'rgSetLocalGiftVisibility' in viewer
assert 'rgLocalGiftPurchaseId(gift: gift) == nil ? gift.text : nil' in viewer
assert 'model.localPremium = $0; RGSimpleSettings.shared.localPremium = $0' in ui
assert 'setPhone(account: model.account' in ui

cover = (root / 'submodules/TelegramUI/Components/PeerInfo/PeerInfoCoverComponent/Sources/PeerInfoGiftsCoverComponent.swift').read_text()
assert 'rgLocalGiftProfileState' in cover and 'rgLocalAppearancePeer' in cover
assert 'rgLocalGiftPurchaseId(gift: gift)' in cover and 'id = localId' in cover
assert 'rgSetLocalGiftPinned' in viewer and 'rgSetLocalGiftPinned' in pane
wallet = (module / 'LocalWallet.swift').read_text()
assert 'state.enabled && state.walletCardEnabled' in wallet and '$0.savedToProfile && $0.pinnedToTop' in wallet
assert 'WalletNftItem(' not in wallet and 'giftSlug:' not in wallet, 'Local artwork must not impersonate a transferable NFT'
native_wallet = (root / 'submodules/TelegramUI/Components/Wallet/PeerWalletScreen/Sources/PeerWalletScreen.swift').read_text()
qr = native_wallet.split('let openQr: () -> Void =', 1)[1].split('let contentWidth', 1)[0]
assert qr.index('state?.isLocal == true') < qr.index('makeWalletReceiveScreen')
assert 'rgPresentLocalWalletNotice' in qr and 'return' in qr.split('rgPresentLocalWalletNotice', 1)[1]
assert 'showsWalletInfo || state.isLocal' in native_wallet
assert 'rgLocalProfileCachedData' in native_wallet and 'localStickers: self.isLocal ?' in native_wallet
print('Local profile decoration and wallet payment/QR boundary checks passed')

# Local buying must be intercepted before all server availability and auction branches.
options = (root / 'submodules/TelegramUI/Components/Gifts/GiftOptionsScreen/Sources/GiftOptionsScreen.swift').read_text()
open_gift = options.split('private func openGift(gift:', 1)[1].split('private var isInAttachmentMenu', 1)[0]
assert open_gift.index('if rgLocalGiftsEnabled') < open_gift.index('checkCanSendStarGift') < open_gift.index('makeGiftAuctionBidScreen')
assert 'self.localPurchaseOnly = rgLocalGiftsEnabled(context: context)' in setup
assert 'component.localPurchaseOnly || rgLocalGiftsEnabled' in method
auction = (root / 'submodules/TelegramUI/Components/Gifts/GiftViewScreen/Sources/GiftAuctionBidScreen.swift').read_text()
commit = auction.split('private func commitBid(value:', 1)[1].split('private func ', 1)[0]
assert commit.index('component.localPurchaseOnly || rgLocalGiftsEnabled') < commit.index('starsTopUpOptions') < commit.index('sendStarsPaymentForm')
assert 'guard !rgLocalGiftsEnabled(context: component.context)' in commit
print('Local generic/auction entry, pinned purchase mode and in-flight payment-form boundaries passed.')
