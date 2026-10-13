import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import RGQrLoginSupport
import RGStrings

// MARK: Regram — Log in by QR code.
//
// TelegramCore already implements the whole token exchange
// (`exportAuthTransferToken`: export → import on the token's DC → 2FA), but
// upstream only drew it behind a disabled debug tap on the phone entry screen.
// This screen keeps a valid token on screen, re-exports it when it expires or
// when `updateLoginToken` reports that another device accepted it, and follows
// a DC migration by handing the migrated account back to the sequence.
//
// The sequence presents this screen modally, so its state-driven stack updates
// cannot remove an in-flight QR request. It owns the subsequent 2FA/login flow.

private final class RGQrLoginControllerNode: ASDisplayNode {
    enum ContentState {
        case loading(caption: String?)
        case code(UIImage)
        case accepted
        case failed(caption: String)
    }

    private let presentationData: PresentationData
    private let language: String

    private let titleNode: ImmediateTextNode
    private let textNode: ImmediateTextNode
    private let qrBackgroundNode: ASDisplayNode
    private let qrImageNode: ASImageNode
    private let activityIndicator: UIActivityIndicatorView
    private let retryButton = UIButton(type: .system)
    var retry: (() -> Void)?

    private var state: ContentState = .loading(caption: nil)
    private var validLayout: (ContainerViewLayout, CGFloat)?

    init(presentationData: PresentationData) {
        self.presentationData = presentationData
        self.language = presentationData.strings.baseLanguageCode

        self.titleNode = ImmediateTextNode()
        self.titleNode.maximumNumberOfLines = 2
        self.titleNode.textAlignment = .center
        self.titleNode.displaysAsynchronously = false

        self.textNode = ImmediateTextNode()
        self.textNode.maximumNumberOfLines = 0
        self.textNode.textAlignment = .center
        self.textNode.lineSpacing = 0.2
        self.textNode.displaysAsynchronously = false

        // The generated code is dark on light, so it needs a light plate to stay
        // scannable in a dark theme.
        self.qrBackgroundNode = ASDisplayNode()
        self.qrBackgroundNode.backgroundColor = .white
        self.qrBackgroundNode.cornerRadius = 16.0
        self.qrBackgroundNode.borderWidth = UIScreenPixel
        self.qrBackgroundNode.borderColor = presentationData.theme.list.itemPlainSeparatorColor.cgColor

        self.qrImageNode = ASImageNode()
        self.qrImageNode.contentMode = .scaleAspectFit
        self.qrImageNode.displaysAsynchronously = false

        self.activityIndicator = UIActivityIndicatorView(style: .medium)
        self.activityIndicator.color = presentationData.theme.list.itemAccentColor
        self.activityIndicator.hidesWhenStopped = true

        super.init()

        self.backgroundColor = presentationData.theme.list.plainBackgroundColor

        self.addSubnode(self.titleNode)
        self.addSubnode(self.qrBackgroundNode)
        self.addSubnode(self.qrImageNode)
        self.addSubnode(self.textNode)

        self.retryButton.setTitle("QrLogin.RetryButton".i18n(self.language), for: .normal)
        self.retryButton.titleLabel?.font = Font.semibold(17.0)
        self.retryButton.tintColor = presentationData.theme.list.itemAccentColor
        self.retryButton.addTarget(self, action: #selector(self.retryPressed), for: .touchUpInside)
        self.applyState()
    }

    @objc private func retryPressed() { self.retry?() }

    override func didLoad() {
        super.didLoad()

        self.view.addSubview(self.activityIndicator)
        self.view.addSubview(self.retryButton)
        self.qrImageNode.view.layer.minificationFilter = .nearest
        self.qrImageNode.view.layer.magnificationFilter = .nearest
        self.applyState()
    }

    func update(state: ContentState) {
        self.state = state
        self.applyState()
        if let (layout, navigationBarHeight) = self.validLayout {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
        }
    }

    private func applyState() {
        let title: String
        let text: String
        var showsPlate = true
        var isBusy = true
        var showsRetry = false
        var image: UIImage?
        switch self.state {
        case let .loading(caption):
            title = "QrLogin.Title".i18n(self.language)
            text = caption ?? "QrLogin.Text".i18n(self.language)
        case let .code(codeImage):
            title = "QrLogin.Title".i18n(self.language)
            text = "QrLogin.Text".i18n(self.language)
            image = codeImage
            isBusy = false
        case .accepted:
            title = "QrLogin.Accepted.Title".i18n(self.language)
            text = "QrLogin.Accepted.Text".i18n(self.language)
            showsPlate = false
        case let .failed(caption):
            title = "QrLogin.Title".i18n(self.language)
            text = caption
            showsPlate = false
            isBusy = false
            showsRetry = true
        }

        self.titleNode.attributedText = NSAttributedString(string: title, font: Font.semibold(24.0), textColor: self.presentationData.theme.list.itemPrimaryTextColor)
        self.textNode.attributedText = NSAttributedString(string: text, font: Font.regular(15.0), textColor: self.presentationData.theme.list.itemSecondaryTextColor)

        self.qrBackgroundNode.isHidden = !showsPlate
        self.qrImageNode.image = image
        self.qrImageNode.isHidden = image == nil

        // Spinning until the first code arrives (fetching a token needs a round
        // trip, and an empty white square reads as broken) and while the
        // accepted login completes.
        self.retryButton.isHidden = !showsRetry
        if isBusy {
            self.activityIndicator.startAnimating()
        } else {
            self.activityIndicator.stopAnimating()
        }
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = (layout, navigationBarHeight)

        let sideInset: CGFloat = 24.0 + max(layout.safeInsets.left, layout.safeInsets.right)
        let availableWidth = max(1.0, min(430.0, layout.size.width - sideInset * 2.0))

        let titleSize = self.titleNode.updateLayout(CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
        let textSize = self.textNode.updateLayout(CGSize(width: availableWidth, height: .greatestFiniteMagnitude))

        let titleSpacing: CGFloat = 28.0
        let textSpacing: CGFloat = 28.0
        let qrSide = min(260.0, availableWidth)
        let showsRetry: Bool
        if case .failed = self.state { showsRetry = true } else { showsRetry = false }
        let qrHeight: CGFloat = showsRetry ? 0.0 : qrSide
        let contentHeight = titleSize.height + titleSpacing + qrHeight + textSpacing + textSize.height + (showsRetry ? 56.0 : 0.0)

        let bottomInset = max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom)
        let availableHeight = layout.size.height - navigationBarHeight - bottomInset
        var originY = navigationBarHeight + max(16.0, floor((availableHeight - contentHeight) / 2.0) - 20.0)

        transition.updateFrame(node: self.titleNode, frame: CGRect(origin: CGPoint(x: floor((layout.size.width - titleSize.width) / 2.0), y: originY), size: titleSize))
        originY += titleSize.height + titleSpacing

        let qrFrame = CGRect(origin: CGPoint(x: floor((layout.size.width - qrSide) / 2.0), y: originY), size: CGSize(width: qrSide, height: qrSide))
        transition.updateFrame(node: self.qrBackgroundNode, frame: qrFrame)
        transition.updateFrame(node: self.qrImageNode, frame: qrFrame.insetBy(dx: 12.0, dy: 12.0))

        let indicatorSize = self.activityIndicator.intrinsicContentSize
        self.activityIndicator.frame = CGRect(origin: CGPoint(x: floor(qrFrame.midX - indicatorSize.width / 2.0), y: floor(qrFrame.midY - indicatorSize.height / 2.0)), size: indicatorSize)
        originY += qrHeight + textSpacing

        transition.updateFrame(node: self.textNode, frame: CGRect(origin: CGPoint(x: floor((layout.size.width - textSize.width) / 2.0), y: originY), size: textSize))
        self.retryButton.frame = CGRect(x: sideInset, y: originY + textSize.height + 12.0, width: availableWidth, height: 44.0)
    }
}

final class RGQrLoginController: ViewController {
    private var controllerNode: RGQrLoginControllerNode {
        return self.displayNode as! RGQrLoginControllerNode
    }

    private let sharedContext: SharedAccountContext
    private var account: UnauthorizedAccount
    private let presentationData: PresentationData
    private let syncContacts: Bool
    private let accountUpdated: (UnauthorizedAccount) -> Void

    private let tokenDisposable = MetaDisposable()
    private let refreshDisposable = MetaDisposable()
    private var requestVersion = 0
    private let tokenEventsDisposable = MetaDisposable()
    private let qrImageDisposable = MetaDisposable()
    private let connectionStatusDisposable = MetaDisposable()
    private var connectionStatus: ConnectionStatus = .waitingForNetwork
    private var hasDisplayedToken = false
    private var hasRestartedInitialSession = false

    // Set once the token exchange has finished (logged in, or the account now
    // waits for its 2FA password). Nothing is re-exported after that.
    private var isCompleted = false
    private(set) var hasBeenAccepted = false

    init(sharedContext: SharedAccountContext, account: UnauthorizedAccount, presentationData: PresentationData, syncContacts: Bool, accountUpdated: @escaping (UnauthorizedAccount) -> Void) {
        self.sharedContext = sharedContext
        self.account = account
        self.presentationData = presentationData
        self.syncContacts = syncContacts
        self.accountUpdated = accountUpdated

        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: AuthorizationSequenceController.navigationBarTheme(presentationData.theme), strings: NavigationBarStrings(presentationStrings: presentationData.strings)))

        self.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)
        self.statusBar.statusBarStyle = presentationData.theme.intro.statusBarStyle.style
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: presentationData.strings.Common_Cancel, style: .plain, target: self, action: #selector(self.cancelPressed))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.tokenDisposable.dispose()
        self.refreshDisposable.dispose()
        self.tokenEventsDisposable.dispose()
        self.qrImageDisposable.dispose()
        self.connectionStatusDisposable.dispose()
    }

    @objc private func cancelPressed() {
        self.isCompleted = true
        self.tokenDisposable.set(nil)
        self.refreshDisposable.set(nil)
        self.tokenEventsDisposable.set(nil)
        self.qrImageDisposable.set(nil)
        self.connectionStatusDisposable.set(nil)
        self.dismiss()
    }

    override public func loadDisplayNode() {
        self.displayNode = RGQrLoginControllerNode(presentationData: self.presentationData)
        self.displayNodeDidLoad()

        self.controllerNode.retry = { [weak self] in self?.refreshToken() }
        self.activateAccount()
        self.prepareConnection()
    }

    private func prepareConnection() {
        let sharedContext = self.sharedContext
        let pendingAccount = self.account
        let accountUpdated = self.accountUpdated
        let foreground = sharedContext.applicationBindings.applicationInForeground
        // Keep initialization alive through dismissal: replacing an exclusive
        // keychain requires handing the resulting account back to the sequence.
        let connection = sharedContext.activeAccountContexts
        |> take(1)
        |> timeout(2.0, queue: .mainQueue(), alternate: .single((nil, [], nil)))
        |> mapToSignal { primary, accounts, _ -> Signal<UnauthorizedAccount, NoError> in
            let candidates = ([primary].compactMap { $0 } + accounts.map { $0.1 })
            guard let routingAccount = candidates.first(where: { $0.account.testingEnvironment == pendingAccount.testingEnvironment })?.account else {
                return .single(pendingAccount)
            }
            return TelegramEngineUnauthorized(account: pendingAccount).auth.prepareAuthTransferAccount(accountManager: sharedContext.accountManager, routingAccount: routingAccount)
        }
        |> deliverOnMainQueue
        let _ = connection.startStandalone(next: { [weak self] account in
            account.shouldBeServiceTaskMaster.set(foreground |> map { active -> AccountServiceTaskMasterMode in active ? .always : .never })
            if let self, !self.isCompleted {
                self.updateAccount(account)
                self.subscribeToTokenEvents()
                self.refreshToken()
            } else {
                accountUpdated(account)
            }
        })
    }

    private func activateAccount() {
        // A pending login owns a separate account/network. Keep it active while
        // the app is in the foreground, including after a same-DC restart.
        self.account.shouldBeServiceTaskMaster.set(self.sharedContext.applicationBindings.applicationInForeground |> map { active -> AccountServiceTaskMasterMode in
            return active ? .always : .never
        })
        self.connectionStatus = .waitingForNetwork
        self.connectionStatusDisposable.set((self.account.network.connectionStatus |> deliverOnMainQueue).startStrict(next: { [weak self] status in
            self?.connectionStatus = status
        }))
    }

    private var timeoutCaption: String {
        // Distinguish a connection that never opened from an unanswered token
        // request, so a device-only failure can be diagnosed without token logs.
        let key: String
        switch self.connectionStatus {
        case .waitingForNetwork: key = "QrLogin.NetworkUnavailable"
        case .connecting: key = "QrLogin.ConnectionTimedOut"
        case .updating: key = "QrLogin.InitializationTimedOut"
        case .online: key = "QrLogin.RequestTimedOut"
        }
        return key.i18n(self.presentationData.strings.baseLanguageCode)
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }

    // `updateLoginToken` arrives on the account that exported the token, so the
    // subscription follows the account across a DC migration.
    private func subscribeToTokenEvents() {
        self.tokenEventsDisposable.set((self.account.updateLoginTokenEvents
        |> deliverOnMainQueue).startStrict(next: { [weak self] _ in
            guard let self, !self.isCompleted else {
                return
            }
            // Another device accepted the code. Exporting again now returns the
            // authorization (or a migration / password request).
            // An event requests a re-export; only a confirmed authorization shows "accepted".
            self.refreshToken()
        }))
    }

    private func refreshToken() {
        guard !self.isCompleted else { return }
        if !self.hasDisplayedToken { self.controllerNode.update(state: .loading(caption: nil)) }
        self.refreshDisposable.set(nil)
        self.tokenDisposable.set(nil)
        self.requestVersion += 1
        let version = self.requestVersion
        let account = self.account
        let sharedContext = self.sharedContext
        let syncContacts = self.syncContacts

        // The first token must not depend indefinitely on initializing other accounts.
        let accountIds = sharedContext.activeAccountContexts
        |> take(1)
        |> map { _, accounts, _ in
            accounts.map { $0.1.account }.filter { $0.testingEnvironment == account.testingEnvironment }.map { $0.peerId.id }
        }
        |> timeout(2.0, queue: .mainQueue(), alternate: .single([]))
        |> castError(ExportAuthTransferTokenError.self)
        let tokenSignal = accountIds
        |> mapToSignal { ids in
            TelegramEngineUnauthorized(account: account).auth.exportAuthTransferToken(accountManager: sharedContext.accountManager, otherAccountUserIds: ids, syncContacts: syncContacts)
        }
        |> timeout(self.hasRestartedInitialSession ? 60.0 : 20.0, queue: .mainQueue(), alternate: .fail(.timedOut))
        |> deliverOnMainQueue

        self.tokenDisposable.set(tokenSignal.startStrict(next: { [weak self] result in
            guard let self, !self.isCompleted, self.requestVersion == version else { return }
            switch result {
            case let .displayToken(token):
                self.hasDisplayedToken = true
                self.displayToken(token, version: version)
                self.scheduleRefresh(after: Double(max(1, token.validUntil - Int32(Date().timeIntervalSince1970))))
            case let .changeAccountAndRetry(account):
                self.updateAccount(account)
                self.refreshToken()
            case .loggedIn:
                self.complete()
            case let .passwordRequested(account):
                self.updateAccount(account)
                self.complete()
            }
        }, error: { [weak self] error in
            guard let self, !self.isCompleted, self.requestVersion == version else { return }
            self.qrImageDisposable.set(nil)
            switch error {
            case .generic:
                self.controllerNode.update(state: .loading(caption: "QrLogin.Retrying".i18n(self.presentationData.strings.baseLanguageCode)))
                self.scheduleRefresh(after: 3.0)
            case .limitExceeded:
                self.controllerNode.update(state: .failed(caption: "QrLogin.TooManyAttempts".i18n(self.presentationData.strings.baseLanguageCode)))
                self.scheduleRefresh(after: 30.0)
            case .timedOut:
                if !self.hasDisplayedToken && !self.hasRestartedInitialSession {
                    self.restartInitialSession()
                } else {
                    self.controllerNode.update(state: .failed(caption: self.timeoutCaption))
                    self.scheduleRefresh(after: 3.0)
                }
            case let .rpc(reason):
                if let delay = RGQrLoginRetry.delay(forRPC: reason) {
                    self.controllerNode.update(state: .loading(caption: "QrLogin.Retrying".i18n(self.presentationData.strings.baseLanguageCode)))
                    self.scheduleRefresh(after: delay)
                } else {
                    self.controllerNode.update(state: .failed(caption: "QrLogin.RequestError".i18n(self.presentationData.strings.baseLanguageCode, args: reason)))
                }
            }
        }))
    }

    private func restartInitialSession() {
        self.hasRestartedInitialSession = true
        self.refreshDisposable.set(nil)
        self.tokenDisposable.set(nil)
        self.qrImageDisposable.set(nil)
        self.tokenEventsDisposable.set(nil)
        self.requestVersion += 1
        let version = self.requestVersion
        let oldAccount = self.account
        oldAccount.shouldBeServiceTaskMaster.set(.single(.never))
        self.controllerNode.update(state: .loading(caption: "QrLogin.Reconnecting".i18n(self.presentationData.strings.baseLanguageCode)))
        let restart = TelegramEngineUnauthorized(account: oldAccount).auth.restartAuthTransferAccount(accountManager: self.sharedContext.accountManager)
        |> deliverOnMainQueue
        let accountUpdated = self.accountUpdated
        let foreground = self.sharedContext.applicationBindings.applicationInForeground
        // Once keychain ownership changes, the new account must reach the sequence
        // even if the user closes the QR page during initialization.
        let _ = restart.startStandalone(next: { [weak self] account in
            account.shouldBeServiceTaskMaster.set(foreground |> map { active -> AccountServiceTaskMasterMode in active ? .always : .never })
            if let self, !self.isCompleted, self.requestVersion == version {
                self.updateAccount(account)
                self.subscribeToTokenEvents()
                self.scheduleRefresh(after: 0.1)
            } else {
                accountUpdated(account)
            }
        })
    }

    private func scheduleRefresh(after duration: Double) {
        self.refreshDisposable.set((Signal<Never, NoError>.complete()
        |> delay(duration, queue: .mainQueue())).startStrict(completed: { [weak self] in self?.refreshToken() }))
    }

    private func updateAccount(_ updatedAccount: UnauthorizedAccount) {
        if updatedAccount === self.account {
            return
        }
        self.account.shouldBeServiceTaskMaster.set(.single(.never))
        self.account = updatedAccount
        self.activateAccount()
        self.accountUpdated(updatedAccount)
        if !self.isCompleted {
            self.subscribeToTokenEvents()
        }
    }

    private func complete() {
        if self.isCompleted {
            return
        }
        self.isCompleted = true
        self.hasBeenAccepted = true
        self.refreshDisposable.set(nil)
        self.tokenDisposable.set(nil)
        self.tokenEventsDisposable.set(nil)
        self.qrImageDisposable.set(nil)
        self.connectionStatusDisposable.set(nil)
        self.controllerNode.update(state: .accepted)
        // The sequence may have processed the password state before this callback ran.
        self.dismiss()
    }

    private func displayToken(_ token: AuthTransferExportedToken, version: Int) {
        let pixelSize = min(2048, Int(260.0 * UIScreen.main.scale))
        // Theme color, kept opaque and sufficiently dark for reliable scanning on the white plate.
        var red: CGFloat = 0.0, green: CGFloat = 0.0, blue: CGFloat = 0.0, alpha: CGFloat = 1.0
        let accent = self.presentationData.theme.list.itemAccentColor
        if !accent.getRed(&red, green: &green, blue: &blue, alpha: &alpha) || max(red, green, blue) - min(red, green, blue) < 0.05 {
            red = 0.0; green = 0.55; blue = 0.32
        }
        let intensity = red * 0.2126 + green * 0.7152 + blue * 0.0722
        let factor = min(1.0, 0.45 / max(0.001, intensity))
        let color = UIColor(red: red * factor, green: green * factor, blue: blue * factor, alpha: 1.0).cgColor
        let signal = Signal<CGImage?, NoError> { subscriber in
            subscriber.putNext(RGQrLoginCode.image(token: token.value, maximumPixelSize: pixelSize, foregroundColor: color))
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(Queue.concurrentDefaultQueue())
        |> timeout(5.0, queue: .mainQueue(), alternate: .single(nil))
        |> deliverOnMainQueue
        self.qrImageDisposable.set(signal.startStrict(next: { [weak self] image in
            guard let self, !self.isCompleted, self.requestVersion == version else { return }
            if let image {
                self.controllerNode.update(state: .code(UIImage(cgImage: image, scale: UIScreen.main.scale, orientation: .up)))
            } else {
                self.controllerNode.update(state: .failed(caption: "QrLogin.RenderFailed".i18n(self.presentationData.strings.baseLanguageCode)))
                self.scheduleRefresh(after: 5.0)
            }
        }))
    }
}
