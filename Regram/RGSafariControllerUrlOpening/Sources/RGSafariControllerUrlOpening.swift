import RGLogging
import RGAPIWebSettings
import RGConfig
import RGSettingsUI
import SFSafariViewControllerPlus
//
import AccountContext
import Display
import Foundation
import TelegramPresentationData

func rgOpenUrlWithSafariController(
    parsedUrl: URL,
    originalUrl: String,
    context: AccountContext,
    presentationData: PresentationData,
    navigationController: NavigationController?
) {
    // Present from whatever UIKit controller is on top: asking a controller that is already
    // presenting something (a share sheet, a picker, another Safari view) only logs a warning, and the
    // tapped link then silently does nothing.
    var presenter = navigationController?.view.window?.rootViewController
    while let presented = presenter?.presentedViewController, !presented.isBeingDismissed {
        presenter = presented
    }
    if let presenter {
        let controller = SFSafariViewControllerPlusDidFinish(url: parsedUrl)
        controller.preferredBarTintColor = presentationData.theme.rootController.navigationBar.opaqueBackgroundColor
        controller.preferredControlTintColor = presentationData.theme.rootController.navigationBar.accentTextColor
        if parsedUrl.host?.lowercased() == RG_API_WEBAPP_URL_PARSED.host?.lowercased() {
            controller.onDidFinish = {
                RGLogger.shared.log("SafariController", "Closed webapp")
                updateRGWebSettingsInteractivelly(context: context)
            }
        }
        presenter.present(controller, animated: true)
    } else {
        context.sharedContext.applicationBindings.openUrl(originalUrl)
    }
}
