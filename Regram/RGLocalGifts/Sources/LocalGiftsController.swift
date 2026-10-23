// MARK: Regram — Telegram-themed UI over the local ledger, with no checkout service.
import Foundation
import UIKit
import SwiftUI
import ComponentFlow
import GiftItemComponent
import AccountContext
import Display
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import SwiftSignalKit
import RGSimpleSettings
import RGStrings
import RGSwiftUI

@MainActor private final class LocalGiftsModel: ObservableObject {
    @Published var state: RGLocalGiftsState
    @Published var catalog: [StarGift.Gift] = []
    @Published var balanceText: String
    private var stateDisposable: Disposable?
    private var catalogDisposable: Disposable?
    let context: AccountContext
    let account: String

    init(context: AccountContext) {
        self.context = context
        self.account = rgLocalGiftsAccount(context)
        let state = RGLocalGiftsStore.shared.state(account: self.account)
        self.state = state
        self.balanceText = String(state.balance)
        self.stateDisposable = rgLocalGiftsState(context: context).start(next: { [weak self] state in
            guard let self else { return }
            if self.state.balance != state.balance { self.balanceText = String(state.balance) }
            self.state = state
        })
        // Read the existing catalog cache only; a bundled gift is always available offline.
        self.catalogDisposable = (context.engine.payments.cachedStarGifts() |> deliverOnMainQueue).start(next: { [weak self] gifts in
            var catalog = rgLocalFallbackGift().map { [$0] } ?? []
            var ids = Set(catalog.map(\.id))
            for case let .generic(gift) in gifts ?? [] where gift.price > 0 {
                if ids.insert(gift.id).inserted, let local = rgCachedLocalGift(context: context, gift: gift) { catalog.append(local) }
            }
            self?.catalog = catalog
        })
        self.catalog = rgLocalFallbackGift().map { [$0] } ?? []
    }

    deinit { stateDisposable?.dispose(); catalogDisposable?.dispose() }
}

private final class GiftPreviewView: UIView {
    let component = ComponentView<Empty>()
    var updateContent: (() -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); updateContent?() }
}

private struct LocalGiftPreview: UIViewRepresentable {
    let accountContext: AccountContext
    let gift: StarGift.Gift
    let presentation: PresentationData
    var profile = false
    let action: () -> Void

    func makeUIView(context: Context) -> GiftPreviewView { GiftPreviewView() }
    func updateUIView(_ view: GiftPreviewView, context: Context) {
        view.updateContent = { [weak view] in
            guard let view, view.bounds.width > 0 else { return }
            let size = view.component.update(transition: .immediate,
                component: AnyComponent(GiftItemComponent(context: accountContext, style: .glass,
                    theme: presentation.theme, strings: presentation.strings,
                    subject: .starGift(gift: gift, price: String(gift.price)), mode: profile ? .profile : .generic,
                    action: action)), environment: {}, containerSize: view.bounds.size)
            if let content = view.component.view {
                if content.superview !== view { view.addSubview(content) }
                content.frame = CGRect(origin: .zero, size: size)
            }
        }
        view.setNeedsLayout()
    }
}

@MainActor private struct LocalGiftsView: View {
    @StateObject private var model: LocalGiftsModel
    @SwiftUI.Environment(\.lang) private var lang
    @SwiftUI.Environment(\.rgPresentationTheme) private var theme
    let selectedPurchase: UUID?
    let showMessage: (String) -> Void
    let buy: (StarGift.Gift) -> Void
    let remove: (RGLocalGiftPurchase) -> Void
    private var secondary: Color { Color(uiColor: theme?.list.itemSecondaryTextColor ?? .secondaryLabel) }

    init(context: AccountContext, selectedPurchase: UUID?, showMessage: @escaping (String) -> Void, buy: @escaping (StarGift.Gift) -> Void, remove: @escaping (RGLocalGiftPurchase) -> Void) {
        _model = StateObject(wrappedValue: LocalGiftsModel(context: context))
        self.selectedPurchase = selectedPurchase
        self.showMessage = showMessage
        self.buy = buy
        self.remove = remove
    }

    private func handle(_ result: Result<RGLocalGiftsState, RGLocalGiftsError>) {
        if case let .failure(error) = result { showMessage(rgLocalGiftError(error, language: lang)) }
    }

    var body: some View {
        RGSettingsForm {
            if selectedPurchase == nil || !model.state.enabled {
                RGSettingsSection(footer: Text("LocalGifts.Notice".i18n(lang)).foregroundColor(secondary)) {
                    Toggle("LocalGifts.Enabled".i18n(lang), isOn: Binding(get: { model.state.enabled }, set: {
                        handle(RGLocalGiftsStore.shared.setEnabled(account: model.account, enabled: $0))
                    })).rgSettingsLink("enabled")
                }
                if model.state.enabled {
                    RGSettingsSection(header: Text("LocalGifts.Balance".i18n(lang)), footer: Text("LocalGifts.BalanceHint".i18n(lang)).foregroundColor(secondary)) {
                        HStack {
                            Text("★").foregroundColor(.orange)
                            TextField("LocalGifts.Balance".i18n(lang), text: $model.balanceText).keyboardType(.numberPad)
                                .accessibilityLabel("LocalGifts.Balance".i18n(lang))
                        }.rgSettingsLink("balance")
                        Button("LocalGifts.SaveBalance".i18n(lang)) {
                            guard let amount = Int64(model.balanceText), (0...RGLocalGiftsStore.maximumBalance).contains(amount) else {
                                showMessage("LocalGifts.InvalidAmount".i18n(lang)); return
                            }
                            handle(RGLocalGiftsStore.shared.setBalance(account: model.account, balance: amount))
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        HStack { Text("LocalGifts.CurrentBalance".i18n(lang)); Spacer(); Text("★ \(model.state.balance)").foregroundColor(secondary) }
                    }
                    RGSettingsSection(header: Text("LocalGifts.Catalog".i18n(lang)), footer: Text("LocalGifts.CatalogHint".i18n(lang)).foregroundColor(secondary)) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(model.catalog, id: \.id) { gift in
                                LocalGiftPreview(accountContext: model.context, gift: gift,
                                    presentation: model.context.sharedContext.currentPresentationData.with { $0 }, action: { buy(gift) })
                                    .frame(height: 154)
                                    .accessibilityLabel(rgLocalGiftTitle(gift, language: lang) + ", ★ \(gift.price)")
                                    .accessibilityAddTraits(.isButton)
                            }
                        }.padding(.vertical, 4).rgSettingsLink("catalog")
                    }
                }
            }
            if model.state.enabled {
                RGSettingsSection(header: Text("LocalGifts.Owned".i18n(lang)), footer: Text("LocalGifts.OwnedHint".i18n(lang)).foregroundColor(secondary)) {
                    if model.state.purchases.isEmpty { Text("LocalGifts.Empty".i18n(lang)).foregroundColor(secondary) }
                    ForEach(model.state.purchases.filter { selectedPurchase == nil || $0.id == selectedPurchase }, id: \.id) { purchase in
                        HStack {
                            if let gift = rgLocalGift(context: model.context, purchase: purchase) {
                                LocalGiftPreview(accountContext: model.context, gift: gift,
                                    presentation: model.context.sharedContext.currentPresentationData.with { $0 }, profile: true, action: {})
                                    .frame(width: 92, height: 120).allowsHitTesting(false)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(purchase.title)
                                Text("★ \(purchase.price)").foregroundColor(secondary)
                                Text(Date(timeIntervalSince1970: TimeInterval(purchase.date)), style: .date).font(.footnote).foregroundColor(secondary)
                                Button("LocalGifts.Remove".i18n(lang), role: .destructive) { remove(purchase) }
                            }
                        }
                    }
                }.rgSettingsLink("owned")
            }
        }
    }
}

public func rgLocalGiftError(_ error: RGLocalGiftsError, language: String) -> String {
    let key: String
    switch error {
    case .disabled: key = "LocalGifts.Disabled"
    case .invalidAmount: key = "LocalGifts.InvalidAmount"
    case .insufficientStars: key = "LocalGifts.Insufficient"
    case .limitReached: key = "LocalGifts.Limit"
    case .storage: key = "LocalGifts.StorageError"
    }
    return key.i18n(language)
}

/// Used before native checkout guards: completing this path never fetches a payment form.
public func rgPresentLocalGiftPurchase(context: AccountContext, gift: StarGift.Gift, controller: ViewController, completion: ((Bool) -> Void)? = nil) {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let language = data.strings.rgLanguageCode
    let result = rgBuyLocalGift(context: context, gift: gift)
    let title: String
    let text: String
    let success: Bool
    switch result {
    case .success:
        success = true
        title = "LocalGifts.Success".i18n(language)
        text = "LocalGifts.SuccessHint".i18n(language)
    case let .failure(error):
        success = false
        title = "LocalGifts.Title".i18n(language)
        text = rgLocalGiftError(error, language: language)
    }
    controller.present(textAlertController(context: context, title: title, text: text,
        actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: { completion?(success) })], dismissOnOutsideTap: false), in: .window(.root))
}

public func rgLocalGiftsController(context: AccountContext, focusSetting: String? = nil, purchaseId: UUID? = nil) -> ViewController {
    // All Telegram navigation entry points call this synchronous factory on the main queue.
    return MainActor.assumeIsolated {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
        controller.bindAppearance(context.sharedContext.presentationData)
        controller.title = "LocalGifts.Title".i18n(data.strings.rgLanguageCode)
        let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: {
            LocalGiftsView(context: context, selectedPurchase: purchaseId, showMessage: { [weak controller] text in
                guard let controller else { return }
                let data = context.sharedContext.currentPresentationData.with { $0 }
                controller.present(textAlertController(context: context, title: "LocalGifts.Title".i18n(data.strings.rgLanguageCode), text: text,
                    actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))
            }, buy: { [weak controller] gift in
                guard let controller else { return }
                let data = context.sharedContext.currentPresentationData.with { $0 }
                let language = data.strings.rgLanguageCode
                controller.present(textAlertController(context: context, title: "LocalGifts.Buy".i18n(language),
                    text: rgLocalGiftTitle(gift, language: language) + " · ★ \(gift.price)\n\n" + "LocalGifts.SuccessHint".i18n(language),
                    actions: [TextAlertAction(type: .genericAction, title: data.strings.Common_Cancel, action: {}),
                        TextAlertAction(type: .defaultAction, title: "LocalGifts.Buy".i18n(language), action: { [weak controller] in
                            Queue.mainQueue().after(0.25) {
                                guard let controller else { return }
                                rgPresentLocalGiftPurchase(context: context, gift: gift, controller: controller)
                            }
                        })]), in: .window(.root))
            }, remove: { [weak controller] purchase in
                guard let controller else { return }
                let data = context.sharedContext.currentPresentationData.with { $0 }
                let language = data.strings.rgLanguageCode
                controller.present(textAlertController(context: context, title: "LocalGifts.Remove".i18n(language), text: "LocalGifts.RemoveHint".i18n(language),
                    actions: [TextAlertAction(type: .genericAction, title: data.strings.Common_Cancel, action: {}),
                        TextAlertAction(type: .destructiveAction, title: "LocalGifts.Remove".i18n(language), action: { [weak controller] in
                            let result = RGLocalGiftsStore.shared.remove(account: rgLocalGiftsAccount(context), id: purchase.id)
                            if case .success = result, purchaseId != nil { controller?.navigationController?.popViewController(animated: true) }
                        })]), in: .window(.root))
            })
        })
        controller.bind(controller: UIHostingController(rootView: content.rgSettingsPage("localGifts", focus: focusSetting), ignoreSafeArea: true))
        return controller
    }
}
