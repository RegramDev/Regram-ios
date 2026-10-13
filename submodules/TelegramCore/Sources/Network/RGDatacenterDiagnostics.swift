// MARK: Regram — bounded diagnostic requests over the account's existing network/proxy engine.
import Foundation
import SwiftSignalKit
import TelegramApi
import MtProtoKit

public struct RGDatacenterProbeSample {
    public let datacenterId: Int
    public let index: Int
    public let milliseconds: Double?
    public let timedOut: Bool
}

public extension Network {
    func rgTestDatacenter(_ datacenterId: Int) -> Signal<RGDatacenterProbeSample, NoError> {
        guard (1...5).contains(datacenterId) else { return .complete() }
        return self.download(datacenterId: datacenterId, isMedia: false, tag: nil)
        |> map { Optional($0) }
        |> timeout(8, queue: .mainQueue(), alternate: .single(nil))
        |> take(1)
        |> deliverOnMainQueue
        |> mapToSignal { worker -> Signal<RGDatacenterProbeSample, NoError> in
            guard let worker else { return .single(RGDatacenterProbeSample(datacenterId: datacenterId, index: 0, milliseconds: nil, timedOut: true)) }
            return Signal { subscriber in
                let request = MetaDisposable()
                let cancelled = Atomic(value: false)
                var index = 0
                func next() {
                    guard !cancelled.with({ $0 }) else { return }
                    let started = ProcessInfo.processInfo.systemUptime
                    let currentIndex = index
                    let holder = MetaDisposable()
                    request.set(holder)
                    let signal = worker.request(Api.functions.help.getNearestDc(), automaticFloodWait: false)
                    |> timeout(8, queue: .mainQueue(), alternate: .fail(MTRpcError(errorCode: 408, errorDescription: "REGRAM_PROBE_TIMEOUT")))
                    |> deliverOnMainQueue
                    holder.set(signal.start(next: { value in
                        guard !cancelled.with({ $0 }) else { return }
                        let matches: Bool
                        switch value { case let .nearestDc(details): matches = details.thisDc == Int32(datacenterId) }
                        subscriber.putNext(RGDatacenterProbeSample(datacenterId: datacenterId, index: currentIndex, milliseconds: matches ? (ProcessInfo.processInfo.systemUptime - started) * 1000 : nil, timedOut: false))
                        advance()
                    }, error: { error in
                        guard !cancelled.with({ $0 }) else { return }
                        subscriber.putNext(RGDatacenterProbeSample(datacenterId: datacenterId, index: currentIndex, milliseconds: nil, timedOut: error.errorCode == 408))
                        advance()
                    }))
                }
                func advance() {
                    index += 1
                    if index == 4 { subscriber.putCompletion() }
                    else { Queue.mainQueue().after(0.15) { next() } }
                }
                next()
                return ActionDisposable { _ = cancelled.swap(true); request.dispose() }
            }
        }
    }
}
