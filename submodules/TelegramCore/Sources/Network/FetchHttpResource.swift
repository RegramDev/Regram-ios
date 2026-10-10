import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit
import RGSimpleSettings // MARK: Regram — count HTTP media only when fetched as a media resource.

public func fetchHttpResource(url: String, preserveExactUrl: Bool = false, trackMediaTransfer: Bool = false) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError> {
    var urlString: String? = url
    if !preserveExactUrl {
        urlString = url.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)
    }
    if let urlString, let url = URL(string: urlString) {
        let signal = MTHttpRequestOperation.data(forHttpUrl: url)!
        return Signal { subscriber in
            subscriber.putNext(.reset)
            let disposable = signal.start(next: { next in
                if let response = next as? MTHttpResponse {
                    // MARK: Regram — generic engine HTTP requests are excluded by default.
                    if trackMediaTransfer { RGTransferStatistics.shared.recordReceived(byteCount: response.data.count) }
                    let fetchResult: MediaResourceDataFetchResult = .dataPart(resourceOffset: 0, data: response.data, range: 0 ..< Int64(response.data.count), complete: true)
                    subscriber.putNext(fetchResult)
                    subscriber.putCompletion()
                } else {
                    subscriber.putError(.generic)
                }
            }, error: { _ in
                subscriber.putError(.generic)
            }, completed: {
            })
            
            return ActionDisposable {
                disposable?.dispose()
            }
        }
    } else {
        return .never()
    }
}
