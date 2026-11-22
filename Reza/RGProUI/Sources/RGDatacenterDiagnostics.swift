// MARK: Regram — opt-in diagnostics; no account identity or proxy credentials are exported.
import AccountContext
import Combine
import Foundation
import RGSimpleSettings
import RGStrings
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import UIKit

final class RGDatacenterDiagnostics: ObservableObject {
    @Published var results = Dictionary(uniqueKeysWithValues: (1...5).map { ($0, RGDatacenterStatistics()) })
    @Published var running = false
    @Published var routeKey = "Diagnostics.Route.Direct"
    @Published var connectionKey = "Diagnostics.Connection.Waiting"
    @Published var cancelled = false
    let currentDatacenter: Int
    private let context: AccountContext
    private var tests = DisposableSet()
    private var observations = DisposableSet()
    private var generation = UUID()
    private var currentProxy: ProxySettings?

    init(context: AccountContext) {
        self.context = context
        self.currentDatacenter = context.account.network.datacenterId
        observations.add((context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.proxySettings]) |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self else { return }
            let proxy = data.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? .defaultSettings
            var key = "Diagnostics.Route.Direct"
            if proxy.enabled, let server = proxy.activeServer {
                switch server.connection {
                case .socks5: key = "Diagnostics.Route.SOCKS5"
                case .mtp: key = "Diagnostics.Route.MTProto"
                case .web: key = "Diagnostics.Route.Web"
                }
            }
            if self.currentProxy != proxy, self.running { self.cancel() }
            self.currentProxy = proxy
            self.routeKey = key
        }))
        observations.add((context.account.network.connectionStatus |> deliverOnMainQueue).start(next: { [weak self] state in
            switch state {
            case .online: self?.connectionKey = "Diagnostics.Connection.Online"
            case .connecting: self?.connectionKey = "Diagnostics.Connection.Connecting"
            case .waitingForNetwork: self?.connectionKey = "Diagnostics.Connection.Waiting"
            case .updating: self?.connectionKey = "Diagnostics.Connection.Updating"
            }
        }))
    }
    deinit { tests.dispose(); observations.dispose() }
    func start() {
        cancel()
        results = Dictionary(uniqueKeysWithValues: (1...5).map { ($0, RGDatacenterStatistics()) })
        running = true; cancelled = false
        let id = UUID(); generation = id
        for dc in 1...5 {
            tests.add(context.account.network.rgTestDatacenter(dc).start(next: { [weak self] sample in
                guard let self, self.generation == id else { return }
                var result = self.results[dc]!
                if sample.index == 0 { result.connectionMilliseconds = sample.milliseconds; result.connectionFailed = sample.milliseconds == nil; result.connectionTimedOut = sample.timedOut }
                else if let milliseconds = sample.milliseconds { result.samples.append(milliseconds) }
                else { result.failures += 1; if sample.timedOut { result.timeouts += 1 } }
                self.results[dc] = result
            }, completed: { [weak self] in
                guard let self, self.generation == id else { return }
                self.results[dc]?.completed = true
                if self.results.values.allSatisfy(\.completed) { self.running = false }
            }))
        }
    }
    func cancel() {
        generation = UUID(); tests.dispose(); tests = DisposableSet()
        if running { cancelled = true }
        running = false
    }
    func report() -> String { RGDatacenterReport.averages(results) }
}
