import Foundation
import SwiftSignalKit

import RGConfig
import RGLogging
import RGSimpleSettings
import RGWebAppExtensions
import RGWebSettingsScheme
import RGRequests
import RGRegDateScheme

private let API_VERSION: String = "0"

private func buildApiUrl(_ endpoint: String) -> String {
    return "\(RG_CONFIG.apiUrl)/v\(API_VERSION)/\(endpoint)"
}

public let RG_API_AUTHORIZATION_HEADER = "Authorization"
public let RG_API_DEVICE_TOKEN_HEADER = "Device-Token"

private enum HTTPRequestError {
    case network
}

public enum RGAPIError {
    case generic(String? = nil)
}

public func getRGSettings(token: String) -> Signal<RGWebSettings, RGAPIError> {
    return Signal { subscriber in

        let url = URL(string: buildApiUrl("settings"))!
        let headers = [RG_API_AUTHORIZATION_HEADER: "Token \(token)"]
        let completed = Atomic<Bool>(value: false)
        
        var request = URLRequest(url: url)
        headers.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        let downloadSignal = requestsCustom(request: request).start(next: { data, urlResponse in
            let _ = completed.swap(true)
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let settings = try decoder.decode(RGWebSettings.self, from: data)
                subscriber.putNext(settings)
                subscriber.putCompletion()
            } catch {
                subscriber.putError(.generic("Can't parse user settings: \(error). Response: \(String(data: data, encoding: .utf8) ?? "")"))
            }
        }, error: { error in
            subscriber.putError(.generic("Error requesting user settings: \(String(describing: error))"))
        })
        
        return ActionDisposable {
            if !completed.with({ $0 }) {
                downloadSignal.dispose()
            }
        }
    }
}



public func postRGSettings(token: String, data: [String:Any]) -> Signal<Void, RGAPIError> {
    return Signal { subscriber in

        let url = URL(string: buildApiUrl("settings"))!
        let headers = [RG_API_AUTHORIZATION_HEADER: "Token \(token)"]
        let completed = Atomic<Bool>(value: false)
        
        var request = URLRequest(url: url)
        headers.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }
        request.httpMethod = "POST"
        
        let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let dataSignal = requestsCustom(request: request).start(next: { data, urlResponse in
            let _ = completed.swap(true)
            
            if let httpResponse = urlResponse as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    subscriber.putCompletion()
                default:
                    subscriber.putError(.generic("Can't update settings: \(httpResponse.statusCode). Response: \(String(data: data, encoding: .utf8) ?? "")"))
                }
            } else {
                subscriber.putError(.generic("Not an HTTP response: \(String(describing: urlResponse))"))
            }
        }, error: { error in
            subscriber.putError(.generic("Error updating settings: \(String(describing: error))"))
        })
        
        return ActionDisposable {
            if !completed.with({ $0 }) {
                dataSignal.dispose()
            }
        }
    }
}

public func getRGAPIRegDate(token: String, deviceToken: String, userId: Int64) -> Signal<RegDate, RGAPIError> {
    return Signal { subscriber in

        let url = URL(string: buildApiUrl("regdate/\(userId)"))!
        let headers = [
            RG_API_AUTHORIZATION_HEADER: "Token \(token)",
            RG_API_DEVICE_TOKEN_HEADER: deviceToken
        ]
        let completed = Atomic<Bool>(value: false)
        
        var request = URLRequest(url: url)
        headers.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }
        request.timeoutInterval = 10
        
        let downloadSignal = requestsCustom(request: request).start(next: { data, urlResponse in
            let _ = completed.swap(true)
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let settings = try decoder.decode(RegDate.self, from: data)
                subscriber.putNext(settings)
                subscriber.putCompletion()
            } catch {
                subscriber.putError(.generic("Can't parse regDate: \(error). Response: \(String(data: data, encoding: .utf8) ?? "")"))
            }
        }, error: { error in
            subscriber.putError(.generic("Error requesting regDate: \(String(describing: error))"))
        })
        
        return ActionDisposable {
            if !completed.with({ $0 }) {
                downloadSignal.dispose()
            }
        }
    }
}


public func postRGReceipt(token: String, deviceToken: String, encodedReceiptData: Data) -> Signal<Void, RGAPIError> {
    return Signal { subscriber in

        let url = URL(string: buildApiUrl("validate"))!
        let headers = [
            RG_API_AUTHORIZATION_HEADER: "Token \(token)",
            RG_API_DEVICE_TOKEN_HEADER: deviceToken
        ]
        let completed = Atomic<Bool>(value: false)
        
        var request = URLRequest(url: url)
        headers.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }
        request.httpMethod = "POST"
        request.httpBody = encodedReceiptData
        
        let dataSignal = requestsCustom(request: request).start(next: { data, urlResponse in
            let _ = completed.swap(true)
            
            if let httpResponse = urlResponse as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    subscriber.putCompletion()
                default:
                    subscriber.putError(.generic("Error posting Receipt: \(httpResponse.statusCode). Response: \(String(data: data, encoding: .utf8) ?? "")"))
                }
            } else {
                subscriber.putError(.generic("Not an HTTP response: \(String(describing: urlResponse))"))
            }
        }, error: { error in
            subscriber.putError(.generic("Error posting Receipt: \(String(describing: error))"))
        })
        
        return ActionDisposable {
            if !completed.with({ $0 }) {
                dataSignal.dispose()
            }
        }
    }
}
