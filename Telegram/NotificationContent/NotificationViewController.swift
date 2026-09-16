import UIKit
import UserNotifications
import UserNotificationsUI
import TelegramUI
import BuildConfig
import RGAppGroupIdentifier

@objc(NotificationViewController)
@available(iOSApplicationExtension 10.0, iOS 10.0, *)
class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var impl: NotificationViewControllerImpl?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if self.impl == nil {
            let appBundleIdentifier = Bundle.main.bundleIdentifier!
            guard let lastDotRange = appBundleIdentifier.range(of: ".", options: [.backwards]) else {
                return
            }
            
            let baseAppBundleId = String(appBundleIdentifier[..<lastDotRange.lowerBound])
            
            let buildConfig = BuildConfig(baseAppBundleId: baseAppBundleId)
            
            let languagesCategory = "ios"
            
            // MARK: Regram — must resolve the container the same way the app does; a re-signing
            // tool never grants group.<bundle id>, so hardcoding it leaves the extension with no
            // account to read and the app with data it cannot see.
            let maybeAppGroupUrl = rgDataContainerURL()
            
            guard let appGroupUrl = maybeAppGroupUrl else {
                return
            }
            
            let rootPath = appGroupUrl.path + "/telegram-data"
            
            let deviceSpecificEncryptionParameters = BuildConfig.deviceSpecificEncryptionParameters(rootPath, baseAppBundleId: baseAppBundleId)
            let encryptionParameters: (Data, Data) = (deviceSpecificEncryptionParameters.key, deviceSpecificEncryptionParameters.salt)
            
            let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
            
            self.impl = NotificationViewControllerImpl(initializationData: NotificationViewControllerInitializationData(appBundleId: baseAppBundleId, appBuildType: buildConfig.isAppStoreBuild ? .public : .internal, appGroupPath: appGroupUrl.path, apiId: buildConfig.apiId, apiHash: buildConfig.apiHash, languagesCategory: languagesCategory, encryptionParameters: encryptionParameters, appVersion: appVersion, bundleData: buildConfig.bundleData(withAppToken: nil, tokenType: nil, tokenEnvironment: nil, signatureDict: nil), useBetaFeatures: !buildConfig.isAppStoreBuild), setPreferredContentSize: { [weak self] size in
                self?.preferredContentSize = size
            })
        }
        
        self.impl?.viewDidLoad(view: self.view)
    }
    
    func didReceive(_ notification: UNNotification) {
        self.impl?.didReceive(notification, view: self.view)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        self.impl?.viewWillTransition(to: size)
    }
}
