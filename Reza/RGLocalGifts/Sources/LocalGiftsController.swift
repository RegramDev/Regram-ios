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
    @Published var phoneCodeText: String
    @Published var phoneNumberText: String
    @Published var ratingText: String
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
        let phone = rgLocalPhoneParts(context: context, number: state.phoneNumber)
        self.phoneCodeText = phone.code
        self.phoneNumberText = phone.number
        self.ratingText = String(state.ratingLevel)
        self.localPremium = RGSimpleSettings.shared.localPremium
        self.tonBalanceText = RGLocalGiftCurrency.ton.text(for: state.tonBalance)
        self.stateDisposable = rgLocalGiftsState(context: context).start(next: { [weak self] state in
            guard let self else { return }
            if self.state.balance != state.balance { self.balanceText = String(state.balance) }
            if self.state.tonBalance != state.tonBalance { self.tonBalanceText = RGLocalGiftCurrency.ton.text(for: state.tonBalance) }
            if self.state.phoneNumber != state.phoneNumber {
                let phone = rgLocalPhoneParts(context: context, number: state.phoneNumber)
                self.phoneCodeText = phone.code
                self.phoneNumberText = phone.number
            }
            if self.state.ratingLevel != state.ratingLevel { self.ratingText = String(state.ratingLevel) }
            self.state = state
        })
    }

    deinit { stateDisposable?.dispose() }

    var phoneText: String? {
        RGLocalGiftsStore.normalizedPhone(countryCode: phoneCodeText, number: phoneNumberText)
    }
}

@MainActor private struct LocalGiftsView: View {
    private enum InputField: Hashable { case phoneCode, phone, rating, stars, ton }
    @StateObject private var model: LocalGiftsModel
    @FocusState private var focusedField: InputField?
    @SwiftUI.Environment(\.lang) private var lang
    @SwiftUI.Environment(\.rgPresentationTheme) private var theme
    @SwiftUI.Environment(\.containerViewLayout) private var containerLayout
    let showMessage: (String) -> Void
    private var secondary: Color { Color(uiColor: theme?.list.itemSecondaryTextColor ?? .secondaryLabel) }
    private var keyboardInset: CGFloat { max(0.0, (containerLayout?.inputHeight ?? 0.0) - (containerLayout?.safeInsets.bottom ?? 0.0)) }

    private func revealInput(in proxy: ScrollViewProxy) {
        guard let focusedField else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(focusedField == .phoneCode ? InputField.phone : focusedField, anchor: .center) }
        }
    }

    init(context: AccountContext, showMessage: @escaping (String) -> Void) {
        _model = StateObject(wrappedValue: LocalGiftsModel(context: context))
        self.showMessage = showMessage
    }

    private func handle(_ result: Result<RGLocalGiftsState, RGLocalGiftsError>) {
        if case let .failure(error) = result { showMessage(rgLocalGiftError(error, language: lang)) }
    }

    var body: some View {
        ScrollViewReader { proxy in
        RGSettingsForm {
            RGSettingsSection(footer: Text("LocalPremium.Notice".i18n(lang) + "\n" + "Showroom.PremiumRefresh".i18n(lang)).foregroundColor(secondary)) {
                Toggle("LocalPremium.Title".i18n(lang), isOn: Binding(get: { model.localPremium }, set: {
                    model.localPremium = $0; RGSimpleSettings.shared.localPremium = $0
                })).rgSettingsLink("localPremium")
            }
            RGSettingsSection(header: Text("LocalPhone.Title".i18n(lang)), footer: Text("LocalPhone.Hint".i18n(lang)).foregroundColor(secondary)) {
                HStack(spacing: 12) {
                    HStack(spacing: 3) {
                        Text("+")
                        TextField("LocalPhone.CountryCode".i18n(lang), text: $model.phoneCodeText).keyboardType(.numberPad)
                            .focused($focusedField, equals: .phoneCode)
                            .accessibilityLabel("LocalPhone.CountryCode".i18n(lang))
                    }.frame(width: 85).id(InputField.phoneCode)
                    Divider()
                    TextField("LocalPhone.Number".i18n(lang), text: $model.phoneNumberText).keyboardType(.phonePad)
                        .focused($focusedField, equals: .phone)
                        .accessibilityLabel("LocalPhone.Number".i18n(lang))
                }.id(InputField.phone).rgSettingsLink("phone")
                Toggle("LocalPhone.Enabled".i18n(lang), isOn: Binding(get: { model.state.phoneEnabled }, set: { value in
                    if value && model.phoneText == nil {
                        showMessage("LocalPhone.Invalid".i18n(lang)); return
                    }
                    handle(RGLocalGiftsStore.shared.setPhone(account: model.account, enabled: value, number: value ? (model.phoneText ?? model.state.phoneNumber) : model.state.phoneNumber))
                }))
                Button("LocalPhone.Save".i18n(lang)) {
                    guard let number = model.phoneText else { showMessage("LocalPhone.Invalid".i18n(lang)); return }
                    handle(RGLocalGiftsStore.shared.setPhone(account: model.account, enabled: true, number: number))
                    focusedField = nil
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            RGSettingsSection(header: Text("LocalRating.Title".i18n(lang)), footer: Text("LocalRating.Hint".i18n(lang)).foregroundColor(secondary)) {
                TextField("LocalRating.Level".i18n(lang), text: $model.ratingText).keyboardType(.numbersAndPunctuation)
                    .focused($focusedField, equals: .rating).id(InputField.rating)
                    .accessibilityLabel("LocalRating.Level".i18n(lang)).rgSettingsLink("rating")
                Toggle("LocalRating.Enabled".i18n(lang), isOn: Binding(get: { model.state.ratingEnabled }, set: { value in
                    guard !value || Int32(model.ratingText.trimmingCharacters(in: .whitespacesAndNewlines)).map({ (-RGLocalGiftsStore.maximumRatingLevel...RGLocalGiftsStore.maximumRatingLevel).contains($0) }) == true else {
                        showMessage("LocalRating.Invalid".i18n(lang)); return
                    }
                    let level = value ? (Int32(model.ratingText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? model.state.ratingLevel) : model.state.ratingLevel
                    handle(RGLocalGiftsStore.shared.setRating(account: model.account, enabled: value, level: level))
                }))
                Button("LocalRating.Save".i18n(lang)) {
                    guard let level = Int32(model.ratingText.trimmingCharacters(in: .whitespacesAndNewlines)), (-RGLocalGiftsStore.maximumRatingLevel...RGLocalGiftsStore.maximumRatingLevel).contains(level) else { showMessage("LocalRating.Invalid".i18n(lang)); return }
                    handle(RGLocalGiftsStore.shared.setRating(account: model.account, enabled: true, level: level))
                    focusedField = nil
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
                                .focused($focusedField, equals: .stars)
                                .accessibilityLabel("LocalGifts.Balance".i18n(lang))
                        }.id(InputField.stars).rgSettingsLink("balance")
                        Button("LocalGifts.SaveBalance".i18n(lang)) {
                            guard let amount = Int64(model.balanceText), (0...RGLocalGiftsStore.maximumBalance).contains(amount) else {
                                showMessage("LocalGifts.InvalidAmount".i18n(lang)); return
                            }
                            handle(RGLocalGiftsStore.shared.setBalance(account: model.account, balance: amount))
                            focusedField = nil
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        HStack { Text("LocalGifts.CurrentBalance".i18n(lang)); Spacer(); starIcon; Text(String(model.state.balance)).foregroundColor(secondary) }
                    }
                }
            }
            if model.state.enabled {
                RGSettingsSection(header: Text("LocalGifts.TonBalance".i18n(lang)), footer: Text("LocalGifts.TonHint".i18n(lang) + "\n" + "LocalWallet.Hint".i18n(lang)).foregroundColor(secondary)) {
                    HStack {
                        if let image = UIImage(bundleImageName: "Ads/GramBig") { Image(uiImage: image).resizable().scaledToFit().frame(width: 18, height: 18).accessibilityHidden(true) }
                        TextField("LocalGifts.TonBalance".i18n(lang), text: $model.tonBalanceText).keyboardType(.decimalPad)
                            .focused($focusedField, equals: .ton)
                            .accessibilityLabel("LocalGifts.TonBalance".i18n(lang))
                    }.id(InputField.ton).rgSettingsLink("tonBalance")
                    Button("LocalGifts.SaveTonBalance".i18n(lang)) {
                        guard let amount = RGLocalGiftCurrency.ton.amount(from: model.tonBalanceText) else { showMessage("LocalGifts.InvalidAmount".i18n(lang)); return }
                        handle(RGLocalGiftsStore.shared.setBalance(account: model.account, balance: amount, currency: .ton))
                        focusedField = nil
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    Toggle("LocalWallet.Enabled".i18n(lang), isOn: Binding(get: { model.state.walletCardEnabled }, set: {
                        handle(RGLocalGiftsStore.shared.setWalletCardEnabled(account: model.account, enabled: $0))
                    })).rgSettingsLink("walletCard")
                }
            }
        }
        // Telegram supplies the keyboard height to this hosted system Form.
        // Reserve it inside the existing safe-area wrapper so focus and Save stay visible.
        .padding(.bottom, keyboardInset)
        .onChange(of: containerLayout?.inputHeight) { _ in revealInput(in: proxy) }
        .onChange(of: focusedField) { _ in revealInput(in: proxy) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(model.context.sharedContext.currentPresentationData.with { $0 }.strings.Common_Done) { focusedField = nil }
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
    case .pinnedLimitReached: key = "LocalGifts.PinnedLimit"
    case .storage: key = "LocalGifts.StorageError"
    }
    return key.i18n(language)
}

public func rgPresentLocalWalletNotice(context: AccountContext, controller: ViewController) {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    controller.present(textAlertController(context: context, title: "LocalWallet.Title".i18n(data.strings.rgLanguageCode), text: rgLocalWalletNotice(context: context),
        actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))
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
