import RGConfig
import RGLogging
import CryptoKit
import Foundation
import MtProtoKit
import Postbox
import Security
import SwiftSignalKit
import TelegramApi


public struct RGIQTPResponse {
    public let status: Int
    public let value: String
}


private let rgIqtpTokenPrefix = "sgsig.v1."
private let rgIqtpTokenMinimumParts = 4
private let rgIqtpTokenSeparator: Character = "."
private let rgIqtpTokenMaxPastSkew: Int64 = 30
private let rgIqtpTokenMaxFutureSkew: Int64 = 10 * 60
private let rgIqtpApiVersion = 1

private func rgBase64UrlEncode(_ data: Data) -> String {
    let rgBase64 = data.base64EncodedString()
    return rgBase64
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

public func makeIqtpQuery(_ method: String, _ args: [String] = []) -> String {
    let buildNumber = Bundle.main.infoDictionary?[kCFBundleVersionKey as String] ?? ""
    let nonceLength = 16
    var bytes = [UInt8](repeating: 0, count: nonceLength)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    if status != errSecSuccess {
        for index in 0..<bytes.count {
            bytes[index] = UInt8.random(in: 0...UInt8.max)
        }
    }
    let nonce = rgBase64UrlEncode(Data(bytes)).replacingOccurrences(of: ":", with: "_")
    let queryArgs = [nonce] + args
    let baseQuery = "tp:\(rgIqtpApiVersion):\(buildNumber):\(method)"
    if queryArgs.isEmpty {
        return baseQuery
    }
    return baseQuery + ":" + queryArgs.joined(separator: ":")
}

public func rgIqtpQuery(engine: TelegramEngine, query: String, incompleteResults: Bool = false, staleCachedResults: Bool = false) -> Signal<RGIQTPResponse?, NoError> {
    let queryId = arc4random()
    func rgVerifySignedAnswer(query: String, answer: String, peerId: PeerId) -> String? {
        func rgBase64UrlDecode(_ value: String) -> Data? {
            var rgBase64 = value
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let rgRemainder = rgBase64.count % 4
            if rgRemainder > 0 {
                rgBase64 += String(repeating: "=", count: 4 - rgRemainder)
            }
            return Data(base64Encoded: rgBase64)
        }

        func rgDecodePublicKey(_ value: String) -> Data? {
            if let rgData = Data(base64Encoded: value) {
                return rgData
            }
            return rgBase64UrlDecode(value)
        }

        func rgExtractSignedToken(from text: String) -> (payload: String, signature: String)? {
            guard let rgRange = text.range(of: rgIqtpTokenPrefix) else {
                return nil
            }
            let rgTokenStart = text[rgRange.lowerBound...]
            guard let rgTokenPart = rgTokenStart.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first else {
                return nil
            }
            let rgParts = rgTokenPart.split(separator: rgIqtpTokenSeparator, omittingEmptySubsequences: false)
            guard rgParts.count >= rgIqtpTokenMinimumParts else {
                return nil
            }
            guard rgParts[0] == "sgsig", rgParts[1] == "v1" else {
                return nil
            }
            return (payload: String(rgParts[2]), signature: String(rgParts[3]))
        }

        let rgQueryParts = query.split(separator: ":", omittingEmptySubsequences: false)
        guard rgQueryParts.count >= 4, rgQueryParts[0] == "tp" else {
            RGLogger.shared.log("SGIQTP", "Missing IQTP query info")
            return nil
        }
        guard let rgQueryVersion = Int(rgQueryParts[1]), rgQueryVersion == 1 else {
            RGLogger.shared.log("SGIQTP", "Unsupported IQTP version")
            return nil
        }
        let rgQueryBuild = String(rgQueryParts[2])
        let rgQueryMethod = String(rgQueryParts[3])
        let rgQueryArgs = rgQueryParts.count > 4 ? rgQueryParts[4...].map { String($0) } : []
        guard let rgNonce = rgQueryArgs.first, !rgNonce.isEmpty else {
            RGLogger.shared.log("SGIQTP", "Missing IQTP nonce")
            return nil
        }

        guard let rgPublicKey = RG_CONFIG.publicKey, !rgPublicKey.isEmpty else {
            RGLogger.shared.log("SGIQTP", "Missing public key")
            return nil
        }
        guard let rgToken = rgExtractSignedToken(from: answer) else {
            RGLogger.shared.log("SGIQTP", "Missing signed IQTP token")
            return nil
        }
        guard let rgAnswerData = rgBase64UrlDecode(rgToken.payload) else {
            RGLogger.shared.log("SGIQTP", "Invalid IQTP answer encoding")
            return nil
        }
        guard let rgSignatureData = rgBase64UrlDecode(rgToken.signature) else {
            RGLogger.shared.log("SGIQTP", "Invalid IQTP signature encoding")
            return nil
        }
        guard let rgPublicKeyData = rgDecodePublicKey(rgPublicKey) else {
            RGLogger.shared.log("SGIQTP", "Invalid public key")
            return nil
        }
        guard let rgSigningKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rgPublicKeyData) else {
            RGLogger.shared.log("SGIQTP", "Invalid public key bytes")
            return nil
        }
        guard rgSigningKey.isValidSignature(rgSignatureData, for: rgAnswerData) else {
            RGLogger.shared.log("SGIQTP", "Invalid IQTP signature")
            return nil
        }
        guard let rgAnswerString = String(data: rgAnswerData, encoding: .utf8) else {
            RGLogger.shared.log("SGIQTP", "Invalid IQTP answer string")
            return nil
        }
        let rgAnswerParts = rgAnswerString.split(separator: ":", omittingEmptySubsequences: false)
        guard rgAnswerParts.count == 8 else {
            RGLogger.shared.log("SGIQTP", "Invalid IQTP answer parts count")
            return nil
        }
        guard let rgAnswerVersion = Int(rgAnswerParts[0]), rgAnswerVersion == 1 else {
            RGLogger.shared.log("SGIQTP", "Invalid IQTP answer version")
            return nil
        }
        let rgAnswerMethod = String(rgAnswerParts[1])
        guard rgAnswerMethod == rgQueryMethod else {
            RGLogger.shared.log("SGIQTP", "Invalid IQTP answer method")
            return nil
        }
        guard let rgAnswerPeerId = Int64(rgAnswerParts[2]) else {
            RGLogger.shared.log("SGIQTP", "Invalid IQTP answer peer id")
            return nil
        }
        let rgAnswerNonce = String(rgAnswerParts[3])
        guard rgAnswerNonce == rgNonce else {
            RGLogger.shared.log("SGIQTP", "Invalid IQTP answer nonce")
            return nil
        }
        guard let rgIat = Int64(rgAnswerParts[4]), let rgExp = Int64(rgAnswerParts[5]) else {
            RGLogger.shared.log("SGIQTP", "Invalid IQTP answer timing")
            return nil
        }
        let rgValue = String(rgAnswerParts[6])
        let rgAnswerBuild = String(rgAnswerParts[7])
        guard rgAnswerBuild == rgQueryBuild else {
            RGLogger.shared.log("SGIQTP", "Invalid IQTP answer build number")
            return nil
        }
        let rgNow = Int64(Date().timeIntervalSince1970)
        guard rgExp >= rgNow - rgIqtpTokenMaxPastSkew else {
            RGLogger.shared.log("SGIQTP", "Expired IQTP answer")
            return nil
        }
        guard rgExp <= rgNow + rgIqtpTokenMaxFutureSkew else {
            RGLogger.shared.log("SGIQTP", "IQTP answer exp too far in future")
            return nil
        }
        guard rgIat <= rgExp else {
            RGLogger.shared.log("SGIQTP", "Invalid IQTP answer timing order")
            return nil
        }
        let rgCurrentPeerId = peerId.id._internalGetInt64Value()
        guard rgAnswerPeerId == rgCurrentPeerId else {
            RGLogger.shared.log("SGIQTP", "IQTP answer peer id mismatch")
            return nil
        }
        return rgValue
    }
    #if DEBUG
    RGLogger.shared.log("SGIQTP", "[\(queryId)] Query: \(query)")
    #else
    RGLogger.shared.log("SGIQTP", "[\(queryId)] Query")
    #endif
    return engine.peers.resolvePeerByName(name: RG_CONFIG.botUsername, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            guard case let .result(result) = result else {
                RGLogger.shared.log("SGIQTP", "[\(queryId)] Failed to resolve peer \(RG_CONFIG.botUsername)")
                return .complete()
            }
            return .single(result)
        }
        |> mapToSignal { peer -> Signal<ChatContextResultCollection?, NoError> in
            guard let peer = peer else {
                RGLogger.shared.log("SGIQTP", "[\(queryId)] Empty peer")
                return .single(nil)
            }
            return engine.messages.requestChatContextResults(IQTP: true, botId: peer.id, peerId: engine.account.peerId, query: query, offset: "", incompleteResults: incompleteResults, staleCachedResults: staleCachedResults)
            |> map { results -> ChatContextResultCollection? in
                return results?.results
            }
            |> `catch` { error -> Signal<ChatContextResultCollection?, NoError> in
                RGLogger.shared.log("SGIQTP", "[\(queryId)] Failed to request inline results")
                return .single(nil)
            }
        }
        |> map { contextResult -> RGIQTPResponse? in
            guard let contextResult, let firstResult = contextResult.results.first else {
                RGLogger.shared.log("SGIQTP", "[\(queryId)] Empty inline result")
                return nil
            }
            
            var t: String?
            if case let .text(text, _, _, _, _, _) = firstResult.message {
                t = text
            }

            guard let t else {
                RGLogger.shared.log("SGIQTP", "[\(queryId)] Missing signed IQTP answer")
                return nil
            }
            let rgValue: String
            if let rgVerifiedValue = rgVerifySignedAnswer(query: query, answer: t, peerId: engine.account.peerId) {
                rgValue = rgVerifiedValue
            } else {
                RGLogger.shared.log("SGIQTP", "[\(queryId)] Invalid signed IQTP token")
                return nil
            }

            var status = 400
            if let title = firstResult.title {
                status = Int(title) ?? 400
            }
            let response = RGIQTPResponse(status: status, value: rgValue)
            RGLogger.shared.log("SGIQTP", "[\(queryId)] Response status: \(status)")
            return response
        }
}
