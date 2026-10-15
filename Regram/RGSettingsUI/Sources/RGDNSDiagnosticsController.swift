// MARK: Regram — on-demand A/AAAA diagnostics; requests use the production transport resolver.
import Foundation
import SwiftUI
import UIKit
import MtProtoKit
import AccountContext
import Display
import RGSwiftUI
import RGSimpleSettings
import RGStrings

private final class RGDNSDiagnostics: ObservableObject {
    struct Row { let family: Int; let address: String?; let milliseconds: Double?; var addresses: [String] = [] }
    @Published var rows: [Row] = []
    @Published var running = false
    private var requests: [MTDisposable] = []
    private var generation = UUID()
    deinit { requests.forEach { $0.dispose() } }
    func cancel() { generation = UUID(); requests.forEach { $0.dispose() }; requests = []; running = false }
    func start(host: String, policy: RGNetworkPolicy) {
        cancel(); rows = []; running = true; let token = UUID(); generation = token
        for family in [4, 6] {
            let signal = MTRGDNSDiagnostics.queryHostname(host, dohEndpoint: policy.effectiveEndpoint, family: family, useSystemDNS: policy.useSystemDNS)
            func finish(_ row: Row) { DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }; self.rows.removeAll { $0.family == family }; self.rows.append(row); self.rows.sort { $0.family < $1.family }; self.running = self.rows.count < 2
            } }
            if let request = signal.start(next: { value in
                let value = value as? [String: Any]
                finish(Row(family: family, address: value?["address"] as? String, milliseconds: (value?["milliseconds"] as? NSNumber)?.doubleValue, addresses: value?["addresses"] as? [String] ?? []))
            }, error: { _ in finish(Row(family: family, address: nil, milliseconds: nil)) }, completed: {}) { requests.append(request) }
        }
    }
}
private struct RGDNSDiagnosticsView: View {
    @Environment(\.lang) private var lang
    @StateObject private var test = RGDNSDiagnostics()
    @State var host: String
    let policy: RGNetworkPolicy
    let currentRoute: String
    var body: some View {
        List {
            Section(footer: Text("DNSDiagnostics.Notice".i18n(lang))) {
                Text(policy.dnsMode.titleKey.i18n(lang))
                if policy.dohEnabled { Text(policy.endpoint).font(.footnote).foregroundColor(.secondary) }
                Text(currentRoute)
                Text("NetworkPolicy.IP".i18n(lang) + ": " + policy.ipVersion.titleKey.i18n(lang))
                TextField("DNSDiagnostics.Host".i18n(lang), text: $host).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(test.running)
                Button((test.running ? "Common.Cancel" : "DNSDiagnostics.Start").i18n(lang)) {
                    if test.running { test.cancel() } else { test.start(host: host.trimmingCharacters(in: .whitespacesAndNewlines), policy: policy) }
                }.disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (policy.dohEnabled && !RGNetworkPolicy.validEndpoint(policy.endpoint)))
                if test.running { ProgressView() }
            }
            if !test.running && !test.rows.isEmpty {
                Section(header: Text("DNSDiagnostics.PolicyAddresses".i18n(lang))) {
                    let allowed = MTRGDNSDiagnostics.orderedAddresses(test.rows.flatMap(\.addresses), policy: policy.ipVersion.rawValue)
                    if allowed.isEmpty { Text("DNSDiagnostics.NoPolicyAddresses".i18n(lang)).foregroundColor(.secondary) }
                    ForEach(allowed, id: \.self) { address in Text(address).textSelection(.enabled) }
                }
            }
            ForEach(test.rows, id: \.family) { row in
                Section(header: Text(row.family == 4 ? "IPv4 · A" : "IPv6 · AAAA")) {
                    Text(row.address ?? "DNSDiagnostics.Failed".i18n(lang)).textSelection(.enabled)
                    if let milliseconds = row.milliseconds { Text(String(format: "%.0f ms", milliseconds)).monospacedDigit().foregroundColor(.secondary) }
                }
            }
        }.onDisappear { test.cancel() }
    }
}
public func rgDNSDiagnosticsController(context: AccountContext, policy: RGNetworkPolicy) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData); controller.title = "DNSDiagnostics.Title".i18n(data.strings.rgLanguageCode)
    let proxy = context.account.network.context.apiEnvironment.socksProxySettings
    let host = proxy?.ip ?? "telegram.org"
    let route = (proxy == nil ? "Diagnostics.Route.Direct" : proxy?.secret == nil ? "Diagnostics.Route.SOCKS5" : "Diagnostics.Route.MTProto").i18n(data.strings.rgLanguageCode)
    let view = RGSwiftUIView(legacyController: controller, manageSafeArea: true) { RGDNSDiagnosticsView(host: host, policy: policy, currentRoute: route) }
    controller.bind(controller: UIHostingController(rootView: view, ignoreSafeArea: true)); return controller
}
