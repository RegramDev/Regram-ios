import RGSwiftUI
// MARK: Regram — hosted SwiftUI settings use the same dismissible alert window as native settings.
import AccountContext
import Display
import PresentationDataUtils
import RGStrings

public func rgPresentSettingsMessage(context: AccountContext, controller: ViewController, titleKey: String, text: String) {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    controller.view.endEditing(true)
    controller.present(textAlertController(context: context, title: titleKey.i18n(data.strings.rgLanguageCode), text: text, actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))
}
