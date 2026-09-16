import Foundation

import RGAPIToken
import RGAPI
import RGLogging

import AccountContext

import RGSimpleSettings
import TelegramCore

public func updateRGWebSettingsInteractivelly(context: AccountContext) {
    let _ = getRGApiToken(context: context).startStandalone(next: { token in
        let _ = getRGSettings(token: token).startStandalone(next: { webSettings in
            RGLogger.shared.log("SGAPI", "New SGWebSettings for id \(context.account.peerId.id._internalGetInt64Value()): \(webSettings) ")
            RGSimpleSettings.shared.canUseStealthMode = webSettings.global.storiesAvailable
            RGSimpleSettings.shared.duckyAppIconAvailable = webSettings.global.duckyAppIconAvailable
            RGSimpleSettings.shared.canUseNY = webSettings.global.nyAvailable
            let _ = (context.account.postbox.transaction { transaction in
                updateAppConfiguration(transaction: transaction, { configuration -> AppConfiguration in
                    var configuration = configuration
                    configuration.rgWebSettings = webSettings
                    return configuration
                })
            }).startStandalone()
        }, error: { e in
            if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
                RGLogger.shared.log("SGAPI", errorMessage)
            }
        })
    }, error: { e in
        if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
            RGLogger.shared.log("SGAPI", errorMessage)
        }
    })
}


public func postRGWebSettingsInteractivelly(context: AccountContext, data: [String: Any]) {
    let _ = getRGApiToken(context: context).startStandalone(next: { token in
        let _ = postRGSettings(token: token, data: data).startStandalone(error: { e in
            if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
                RGLogger.shared.log("SGAPI", errorMessage)
            }
        })
    }, error: { e in
        if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
            RGLogger.shared.log("SGAPI", errorMessage)
        }
    })
}
