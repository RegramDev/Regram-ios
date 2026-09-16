import UIKit
import TelegramUI
import BuildConfig
import ShareExtensionContext
import SwiftSignalKit
import TelegramCore
import RGAppGroupIdentifier

@objc(ShareRootController)
class ShareRootController: UIViewController {
    private var impl: ShareRootControllerImpl?
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        self.modalPresentationStyle = .fullScreen
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Regram — upstream just returns from `loadView` when it cannot reach the app's data,
    // which leaves an empty full-screen view controller that never completes or cancels the
    // extension request: the share sheet shows a blank page the user can only force-close. Say what
    // happened and dismiss instead.
    private func failWithUnavailableData() {
        self.view.backgroundColor = UIColor(white: 0.0, alpha: 0.5)

        let alert = UIAlertController(
            title: "Sharing Unavailable",
            message: "This build cannot reach the app's data from the share sheet. Open the app and send from there.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Shared data container is unavailable"
            ]))
        })
        // `loadView` runs before the view is in a window, so presenting has to wait a beat.
        Queue.mainQueue().after(0.1) { [weak self] in
            self?.present(alert, animated: true)
        }
    }

    override func loadView() {
        super.loadView()

        if self.impl == nil {
            let appBundleIdentifier = Bundle.main.bundleIdentifier!
            guard let lastDotRange = appBundleIdentifier.range(of: ".", options: [.backwards]) else {
                self.failWithUnavailableData()
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
                self.failWithUnavailableData()
                return
            }
            
            let rootPath = appGroupUrl.path + "/telegram-data"
            
            let deviceSpecificEncryptionParameters = BuildConfig.deviceSpecificEncryptionParameters(rootPath, baseAppBundleId: baseAppBundleId)
            let encryptionParameters: (Data, Data) = (deviceSpecificEncryptionParameters.key, deviceSpecificEncryptionParameters.salt)
            
            let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
            
            self.impl = ShareRootControllerImpl(initializationData: ShareRootControllerInitializationData(appBundleId: baseAppBundleId, appBuildType: buildConfig.isAppStoreBuild ? .public : .internal, appGroupPath: appGroupUrl.path, apiId: buildConfig.apiId, apiHash: buildConfig.apiHash, languagesCategory: languagesCategory, encryptionParameters: encryptionParameters, appVersion: appVersion, bundleData: buildConfig.bundleData(withAppToken: nil, tokenType: nil, tokenEnvironment: nil, signatureDict: nil), useBetaFeatures: !buildConfig.isAppStoreBuild, makeTempContext: { accountManager, appLockContext, applicationBindings, InitialPresentationDataAndSettings, networkArguments in
                return makeTempContext(
                    sharedContainerPath: appGroupUrl.path,
                    rootPath: rootPath,
                    appGroupPath: appGroupUrl.path,
                    accountManager: accountManager,
                    appLockContext: appLockContext,
                    encryptionParameters: EngineValueBoxEncryptionParameters(
                        forceEncryptionIfNoSet: false,
                        key: EngineValueBoxEncryptionParameters.Key(data: encryptionParameters.0)!,
                        salt: EngineValueBoxEncryptionParameters.Salt(data: encryptionParameters.1)!
                    ),
                    applicationBindings: applicationBindings,
                    initialPresentationDataAndSettings: InitialPresentationDataAndSettings,
                    networkArguments: networkArguments,
                    buildConfig: buildConfig
                )
            }), getExtensionContext: { [weak self] in
                return self?.extensionContext
            })
            
            self.impl?.openUrl = { [weak self] url in
                guard let self, let url = URL(string: url) else {
                    return
                }
                let _ = self.openURL(url)
            }
        }
        
        self.impl?.loadView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.impl?.viewWillAppear()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.impl?.viewWillDisappear()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.impl?.viewWillDisappear()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.impl?.viewDidLayoutSubviews(view: self.view, traitCollection: self.traitCollection)
    }
    
    @objc func openURL(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                if #available(iOS 18.0, *) {
                    application.open(url, options: [:], completionHandler: nil)
                    return true
                } else {
                    return application.perform(#selector(openURL(_:)), with: url) != nil
                }
            }
            responder = responder?.next
        }
        return false
    }
}
