// MARK: Regram — Telegram-themed UI over the local ledger, with no checkout service.
import Foundation
import UIKit
import SwiftUI
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
    @Published var balanceText: String
    @Published var tonBalanceText: String
    @Published var phoneText: String
    @Published var localPremium: Bool
    private var stateDisposable: Disposable?
    let context: AccountContext
    let account: String

    init(context: AccountContext) {
        self.context = context
        self.account = rgLocalGiftsAccount(context)
        let state = RGLocalGiftsStore.shared.state(account: self.account)
        self.state = state
        self.balanceText = String(state.balance)
        self.phoneText = state.phoneNumber
        self.localPremium = RGSimpleSettings.shared.localPremium
        self.tonBalanceText = RGLocalGiftCurrency.ton.text(for: state.tonBalance)
        self.stateDisposable = rgLocalGiftsState(context: context).start(next: { [weak self] state in
            guard let self else { return }
            if self.state.balance != state.balance { self.balanceText = String(state.balance) }
            if self.state.tonBalance != state.tonBalance { self.tonBalanceText = RGLocalGiftCurrency.ton.text(for: state.tonBalance) }
            if self.state.phoneNumber != state.phoneNumber { self.phoneText = state.phoneNumber }
            self.state = state
        })
    }

    deinit { stateDisposable?.dispose() }
}

@MainActor private struct LocalGiftsView: View {
    @StateObject private var model: LocalGiftsModel
    @SwiftUI.Environment(\.lang) private var lang
    @SwiftUI.Environment(\.rgPresentationTheme) private var theme
    let showMessage: (String) -> Void
    private var secondary: Color { Color(uiColor: theme?.list.itemSecondaryTextColor ?? .secondaryLabel) }

    init(context: AccountContext, showMessage: @escaping (String) -> Void) {
        _model = StateObject(wrappedValue: LocalGiftsModel(context: context))
        self.showMessage = showMessage
    }

    private func handle(_ result: Result<RGLocalGiftsState, RGLocalGiftsError>) {
        if case let .failure(error) = result { showMessage(rgLocalGiftError(error, language: lang)) }
    }

    var body: some View {
        RGSettingsForm {
            RGSettingsSection {
                VStack(spacing: 12) {
                    if let image = UIImage(named: "RegramLocalShowroom") {
                        Image(uiImage: image).resizable().scaledToFit().accessibilityHidden(true)
                    }
                    Text("Showroom.Title".i18n(lang)).font(.headline).multilineTextAlignment(.center)
                }.padding(.vertical, 8)
            }
            RGSettingsSection(footer: Text("LocalPremium.Notice".i18n(lang) + "\n" + "Showroom.PremiumRefresh".i18n(lang)).foregroundColor(secondary)) {
                Toggle("LocalPremium.Title".i18n(lang), isOn: Binding(get: { model.localPremium }, set: {
                    model.localPremium = $0; RGSimpleSettings.shared.localPremium = $0
                })).rgSettingsLink("localPremium")
            }
            RGSettingsSection(header: Text("LocalPhone.Title".i18n(lang)), footer: Text("LocalPhone.Hint".i18n(lang)).foregroundColor(secondary)) {
                TextField("LocalPhone.Number".i18n(lang), text: $model.phoneText).keyboardType(.phonePad)
                    .accessibilityLabel("LocalPhone.Number".i18n(lang)).rgSettingsLink("phone")
                Toggle("LocalPhone.Enabled".i18n(lang), isOn: Binding(get: { model.state.phoneEnabled }, set: { value in
                    if value && RGLocalGiftsStore.normalizedPhone(model.phoneText) == nil {
                        showMessage("LocalPhone.Invalid".i18n(lang)); return
                    }
                    handle(RGLocalGiftsStore.shared.setPhone(account: model.account, enabled: value, number: model.phoneText))
                }))
                Button("LocalPhone.Save".i18n(lang)) {
                    guard RGLocalGiftsStore.normalizedPhone(model.phoneText) != nil else { showMessage("LocalPhone.Invalid".i18n(lang)); return }
                    handle(RGLocalGiftsStore.shared.setPhone(account: model.account, enabled: true, number: model.phoneText))
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            Group {
                RGSettingsSection(footer: Text("LocalGifts.Notice".i18n(lang)).foregroundColor(secondary)) {
                    Toggle("LocalGifts.Enabled".i18n(lang), isOn: Binding(get: { model.state.enabled }, set: {
                        handle(RGLocalGiftsStore.shared.setEnabled(account: model.account, enabled: $0))
                    })).rgSettingsLink("enabled")
                }
                if model.state.enabled {
                    RGSettingsSection(header: Text("LocalGifts.Balance".i18n(lang)), footer: Text(("LocalGifts.BalanceHint".i18n(lang)) + "\n" + "LocalGifts.NativeHint".i18n(lang)).foregroundColor(secondary)) {
                        HStack {
                            starIcon
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
                        HStack { Text("LocalGifts.CurrentBalance".i18n(lang)); Spacer(); starIcon; Text(String(model.state.balance)).foregroundColor(secondary) }
                    }
                }
            }
            if model.state.enabled {
                RGSettingsSection(header: Text("LocalGifts.TonBalance".i18n(lang)), footer: Text("LocalGifts.TonHint".i18n(lang)).foregroundColor(secondary)) {
                    HStack {
                        if let image = UIImage(bundleImageName: "Ads/GramBig") { Image(uiImage: image).resizable().scaledToFit().frame(width: 18, height: 18).accessibilityHidden(true) }
                        TextField("LocalGifts.TonBalance".i18n(lang), text: $model.tonBalanceText).keyboardType(.decimalPad)
                            .accessibilityLabel("LocalGifts.TonBalance".i18n(lang))
                    }.rgSettingsLink("tonBalance")
                    Button("LocalGifts.SaveTonBalance".i18n(lang)) {
                        guard let amount = RGLocalGiftCurrency.ton.amount(from: model.tonBalanceText) else { showMessage("LocalGifts.InvalidAmount".i18n(lang)); return }
                        handle(RGLocalGiftsStore.shared.setBalance(account: model.account, balance: amount, currency: .ton))
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }

    private var starIcon: some View {
        Group {
            if let image = UIImage(bundleImageName: "Premium/Stars/StarSmall") {
                Image(uiImage: image).resizable().scaledToFit().frame(width: 18, height: 18).accessibilityHidden(true)
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
    case .insufficientTon: key = "LocalGifts.InsufficientTon"
    case .limitReached: key = "LocalGifts.Limit"
    case .storage: key = "LocalGifts.StorageError"
    }
    return key.i18n(language)
}

/// Used before native checkout guards: completing this path never fetches a payment form.
public func rgPresentLocalGiftPurchase(context: AccountContext, gift: StarGift.Gift, controller: ViewController, completion: ((Bool) -> Void)? = nil) {
    rgPresentLocalGiftPurchase(context: context, gift: .generic(gift), price: gift.price, controller: controller, completion: completion)
}

public func rgPresentLocalGiftPurchase(context: AccountContext, gift: StarGift, price: Int64, currency: CurrencyAmount.Currency = .stars, controller: ViewController, purchased: ((StarGift) -> Void)? = nil, completion: ((Bool) -> Void)? = nil) {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let language = data.strings.rgLanguageCode
    let result = rgBuyLocalGift(context: context, gift: gift, price: price, currency: currency == .ton ? .ton : .stars)
    let title: String
    let text: String
    let success: Bool
    var purchasedGift: StarGift?
    switch result {
    case let .success(state):
        purchasedGift = state.purchases.first.flatMap { rgLocalGift(context: context, purchase: $0) }
        success = true
        title = "LocalGifts.Success".i18n(language)
        text = "LocalGifts.SuccessHint".i18n(language)
    case let .failure(error):
        success = false
        title = "LocalGifts.Title".i18n(language)
        text = rgLocalGiftError(error, language: language)
    }
    controller.present(textAlertController(context: context, title: title, text: text,
        actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: { if let purchasedGift { purchased?(purchasedGift) }; completion?(success) })], dismissOnOutsideTap: false), in: .window(.root))
}

public func rgLocalGiftsController(context: AccountContext, focusSetting: String? = nil) -> ViewController {
    // All Telegram navigation entry points call this synchronous factory on the main queue.
    return MainActor.assumeIsolated {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
        controller.bindAppearance(context.sharedContext.presentationData)
        controller.title = "Showroom.Title".i18n(data.strings.rgLanguageCode)
        let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: {
            LocalGiftsView(context: context, showMessage: { [weak controller] text in
                guard let controller else { return }
                let data = context.sharedContext.currentPresentationData.with { $0 }
                controller.present(textAlertController(context: context, title: "Showroom.Title".i18n(data.strings.rgLanguageCode), text: text,
                    actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))

            })
        })
        controller.bind(controller: UIHostingController(rootView: content.rgSettingsPage("localGifts", focus: focusSetting), ignoreSafeArea: true))
        return controller
    }
}
