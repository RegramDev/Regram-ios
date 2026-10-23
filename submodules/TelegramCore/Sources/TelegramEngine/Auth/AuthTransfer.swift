import Foundation
import Postbox
internal import TelegramApi
import SwiftSignalKit

public struct AuthTransferExportedToken {
    public let value: Data
    public let validUntil: Int32
}

public enum ExportAuthTransferTokenError {
    case generic
    case limitExceeded
    // MARK: Regram — distinguish connection timeouts from a rejected token request.
    case timedOut
    case rpc(String)

    static func requestError(_ description: String) -> ExportAuthTransferTokenError {
        if description.hasPrefix("FLOOD_WAIT") { return .limitExceeded }
        // Only expose a bounded RPC name, never payloads, credentials or login tokens.
        if !description.isEmpty, description.count <= 96, description.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) || $0 == 95 }) {
            return .rpc(description)
        }
        return .generic
    }
}

public enum ExportAuthTransferTokenResult {
    case displayToken(AuthTransferExportedToken)
    case changeAccountAndRetry(UnauthorizedAccount)
    case loggedIn
    case passwordRequested(UnauthorizedAccount)
}

// MARK: Regram — a second account must not bootstrap exclusively from the
// bundled DC2 addresses. Reuse the connected account's current routing and DC,
// while keeping the pending account's own keychain and authorization.
func _internal_prepareAuthTransferAccount(accountManager: AccountManager<TelegramAccountManagerTypes>, account: UnauthorizedAccount, routingAccount: Account) -> Signal<UnauthorizedAccount, NoError> {
    guard account.testingEnvironment == routingAccount.testingEnvironment else { return .single(account) }
    return account.postbox.transaction { transaction -> Bool in
        guard let state = transaction.getState() as? UnauthorizedAccountState else { return false }
        switch state.contents {
        case .empty, .phoneEntry: return true
        default: return false
        }
    }
    |> mapToSignal { allowed in
        guard allowed else { return .single(account) }
        return account.changedMasterDatacenterId(accountManager: accountManager, masterDatacenterId: Int32(routingAccount.network.datacenterId), forceRestart: true, routingSource: routingAccount.network)
    }
}

// MARK: Regram — reset only an unfinished, pre-token login. Signed-in accounts
// use separate records, and password/code entry must keep its existing session.
func _internal_restartAuthTransferAccount(accountManager: AccountManager<TelegramAccountManagerTypes>, account: UnauthorizedAccount) -> Signal<UnauthorizedAccount, NoError> {
    return account.postbox.transaction { transaction -> Bool in
        guard let state = transaction.getState() as? UnauthorizedAccountState else { return false }
        switch state.contents {
        case .empty, .phoneEntry:
            guard let emptyAuthInfo = try? NSKeyedArchiver.archivedData(withRootObject: NSDictionary(), requiringSecureCoding: false) else { return false }
            transaction.setKeychainEntry(emptyAuthInfo, forKey: "persistent:datacenterAuthInfoById")
            return true
        default:
            return false
        }
    }
    |> mapToSignal { reset in
        guard reset else { return .single(account) }
        return account.changedMasterDatacenterId(accountManager: accountManager, masterDatacenterId: account.masterDatacenterId, forceRestart: true)
    }
}

func _internal_exportAuthTransferToken(accountManager: AccountManager<TelegramAccountManagerTypes>, account: UnauthorizedAccount, otherAccountUserIds: [PeerId.Id], syncContacts: Bool) -> Signal<ExportAuthTransferTokenResult, ExportAuthTransferTokenError> {
    // MARK: Regram — let the QR screen display flood-wait/retry state instead of waiting silently.
    return account.network.request(Api.functions.auth.exportLoginToken(apiId: account.networkArguments.apiId, apiHash: account.networkArguments.apiHash, exceptIds: otherAccountUserIds.map({ $0._internalGetInt64Value() })), automaticFloodWait: false)
    |> map(Optional.init)
    |> `catch` { error -> Signal<Api.auth.LoginToken?, ExportAuthTransferTokenError> in
        if error.errorDescription == "SESSION_PASSWORD_NEEDED" {
            return account.network.request(Api.functions.account.getPassword(), automaticFloodWait: false)
            |> mapError { error -> ExportAuthTransferTokenError in
                return .requestError(error.errorDescription)
            }
            |> mapToSignal { result -> Signal<Api.auth.LoginToken?, ExportAuthTransferTokenError> in
                switch result {
                case let .password(passwordData):
                    let hint = passwordData.hint
                    return account.postbox.transaction { transaction -> Api.auth.LoginToken? in
                        transaction.setState(UnauthorizedAccountState(isTestingEnvironment: account.testingEnvironment, masterDatacenterId: account.masterDatacenterId, contents: .passwordEntry(hint: hint ?? "", number: nil, code: nil, suggestReset: false, syncContacts: syncContacts)))
                        return nil
                    }
                    |> castError(ExportAuthTransferTokenError.self)
                }
            }
        } else if error.errorDescription.hasPrefix("FLOOD_WAIT") {
            return .fail(.limitExceeded)
        } else {
            return .fail(.requestError(error.errorDescription))
        }
    }
    |> mapToSignal { result -> Signal<ExportAuthTransferTokenResult, ExportAuthTransferTokenError> in
        guard let result = result else {
            return .single(.passwordRequested(account))
        }
        switch result {
        case let .loginToken(loginTokenData):
            let (expires, token) = (loginTokenData.expires, loginTokenData.token)
            return .single(.displayToken(AuthTransferExportedToken(value: token.makeData(), validUntil: expires)))
        case let .loginTokenMigrateTo(loginTokenMigrateToData):
            let (dcId, token) = (loginTokenMigrateToData.dcId, loginTokenMigrateToData.token)
            let updatedAccount = account.changedMasterDatacenterId(accountManager: accountManager, masterDatacenterId: dcId)
            return updatedAccount
            |> castError(ExportAuthTransferTokenError.self)
            |> mapToSignal { updatedAccount -> Signal<ExportAuthTransferTokenResult, ExportAuthTransferTokenError> in
                return updatedAccount.network.request(Api.functions.auth.importLoginToken(token: token), automaticFloodWait: false)
                |> map(Optional.init)
                |> `catch` { error -> Signal<Api.auth.LoginToken?, ExportAuthTransferTokenError> in
                    if error.errorDescription == "SESSION_PASSWORD_NEEDED" {
                        return updatedAccount.network.request(Api.functions.account.getPassword(), automaticFloodWait: false)
                        |> mapError { error -> ExportAuthTransferTokenError in
                            return .requestError(error.errorDescription)
                        }
                        |> mapToSignal { result -> Signal<Api.auth.LoginToken?, ExportAuthTransferTokenError> in
                            switch result {
                            case let .password(passwordData):
                                let hint = passwordData.hint
                                return updatedAccount.postbox.transaction { transaction -> Api.auth.LoginToken? in
                                    transaction.setState(UnauthorizedAccountState(isTestingEnvironment: updatedAccount.testingEnvironment, masterDatacenterId: updatedAccount.masterDatacenterId, contents: .passwordEntry(hint: hint ?? "", number: nil, code: nil, suggestReset: false, syncContacts: syncContacts)))
                                    return nil
                                }
                                |> castError(ExportAuthTransferTokenError.self)
                            }
                        }
                    } else {
                        return .fail(.requestError(error.errorDescription))
                    }
                }
                |> mapToSignal { result -> Signal<ExportAuthTransferTokenResult, ExportAuthTransferTokenError> in
                    guard let result = result else {
                        return .single(.passwordRequested(updatedAccount))
                    }
                    switch result {
                    case let .loginTokenSuccess(loginTokenSuccessData):
                        let authorization = loginTokenSuccessData.authorization
                        switch authorization {
                        case let .authorization(authorizationData):
                            let (futureAuthToken, apiUser) = (authorizationData.futureAuthToken, authorizationData.user)
                            if let futureAuthToken = futureAuthToken {
                                storeFutureLoginToken(accountManager: accountManager, token: futureAuthToken.makeData())
                            }

                            return updatedAccount.postbox.transaction { transaction -> Signal<ExportAuthTransferTokenResult, ExportAuthTransferTokenError> in
                                let user = TelegramUser(user: apiUser)
                                let state = AuthorizedAccountState(isTestingEnvironment: updatedAccount.testingEnvironment, masterDatacenterId: updatedAccount.masterDatacenterId, peerId: user.id, state: nil, invalidatedChannels: [])
                                initializedAppSettingsAfterLogin(transaction: transaction, appVersion: updatedAccount.networkArguments.appVersion, syncContacts: syncContacts)
                                transaction.setState(state)
                                return accountManager.transaction { transaction -> ExportAuthTransferTokenResult in
                                    switchToAuthorizedAccount(transaction: transaction, account: updatedAccount, isSupportUser: false)
                                    return .loggedIn
                                }
                                |> castError(ExportAuthTransferTokenError.self)
                            }
                            |> castError(ExportAuthTransferTokenError.self)
                            |> switchToLatest
                        default:
                            return .fail(.generic)
                        }
                    default:
                        return .single(.changeAccountAndRetry(updatedAccount))
                    }
                }
            }
        case let .loginTokenSuccess(loginTokenSuccessData):
            let authorization = loginTokenSuccessData.authorization
            switch authorization {
            case let .authorization(authorizationData):
                let (futureAuthToken, apiUser) = (authorizationData.futureAuthToken, authorizationData.user)
                if let futureAuthToken = futureAuthToken {
                    storeFutureLoginToken(accountManager: accountManager, token: futureAuthToken.makeData())
                }

                return account.postbox.transaction { transaction -> Signal<ExportAuthTransferTokenResult, ExportAuthTransferTokenError> in
                    let user = TelegramUser(user: apiUser)
                    let state = AuthorizedAccountState(isTestingEnvironment: account.testingEnvironment, masterDatacenterId: account.masterDatacenterId, peerId: user.id, state: nil, invalidatedChannels: [])
                    initializedAppSettingsAfterLogin(transaction: transaction, appVersion: account.networkArguments.appVersion, syncContacts: syncContacts)
                    transaction.setState(state)
                    return accountManager.transaction { transaction -> ExportAuthTransferTokenResult in
                        switchToAuthorizedAccount(transaction: transaction, account: account, isSupportUser: false)
                        return .loggedIn
                    }
                    |> castError(ExportAuthTransferTokenError.self)
                }
                |> castError(ExportAuthTransferTokenError.self)
                |> switchToLatest
            case .authorizationSignUpRequired:
                return .fail(.generic)
            }
        }
    }
}

public enum ApproveAuthTransferTokenError {
    case generic
    case invalid
    case expired
    case alreadyAccepted
}

public func approveAuthTransferToken(account: Account, token: Data, activeSessionsContext: ActiveSessionsContext) -> Signal<RecentAccountSession, ApproveAuthTransferTokenError> {
    return account.network.request(Api.functions.auth.acceptLoginToken(token: Buffer(data: token)))
    |> mapError { error -> ApproveAuthTransferTokenError in
        switch error.errorDescription {
        case "AUTH_TOKEN_INVALID":
            return .invalid
        case "AUTH_TOKEN_EXPIRED":
            return .expired
        case "AUTH_TOKEN_ALREADY_ACCEPTED":
            return .alreadyAccepted
        default:
            return .generic
        }
    }
    |> mapToSignal { authorization -> Signal<RecentAccountSession, ApproveAuthTransferTokenError> in
        let session = RecentAccountSession(apiAuthorization: authorization)
        activeSessionsContext.addSession(session)
        return .single(session)
    }
}
