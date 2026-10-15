// MARK: Regram
import Foundation
import SwiftUI
import UIKit
import AccountContext
import Display
import RGSwiftUI
import RGSimpleSettings
import RGStrings
import MtProtoKit

private struct RGNetworkPolicyView: View {
    @Environment(\.lang) private var lang
    @State private var policy = RGSimpleSettings.shared.networkPolicy
    @State private var dnsFailure: String?
    let saved: () -> Void
    let openTest: (RGNetworkPolicy) -> Void
    var body: some View {
        Form {
            Section(footer: Text("NetworkPolicy.DoHNotice".i18n(lang))) {
                Picker("NetworkPolicy.DNSMode".i18n(lang), selection: $policy.dnsMode) {
                    ForEach(RGNetworkPolicy.DNSMode.allCases, id: \.self) { mode in Text(mode.titleKey.i18n(lang)).tag(mode) }
                }.pickerStyle(.menu).rgSettingsLink("enabled")
                TextField("NetworkPolicy.Endpoint".i18n(lang), text: $policy.endpoint, prompt: Text("https://dns.google/resolve")).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().rgSettingsLink("endpoint")
                if policy.dohEnabled, let dnsFailure {
                    Text(("NetworkPolicy.DoHFailure." + dnsFailure).i18n(lang)).font(.footnote).foregroundColor(.secondary)
                }
                if policy.dohEnabled && !RGNetworkPolicy.validEndpoint(policy.endpoint) { Text("NetworkPolicy.InvalidURL".i18n(lang)).foregroundColor(.secondary) }
            }
            Section(footer: Text("NetworkPolicy.IPNotice".i18n(lang))) {
                Picker("NetworkPolicy.IP".i18n(lang), selection: $policy.ipVersion) {
                    ForEach(RGNetworkPolicy.IPVersion.allCases, id: \.self) { version in
                        Text(version.titleKey.i18n(lang)).tag(version)
                    }
                }.pickerStyle(.menu).rgSettingsLink("ipVersion")
            }
            Section(footer: Text("NetworkPolicy.BackupNotice".i18n(lang))) {
                Toggle("NetworkPolicy.DisableBackup".i18n(lang), isOn: $policy.disableBackupAddresses).rgSettingsLink("disableBackup")
            }
            Button("DNSDiagnostics.Title".i18n(lang)) { openTest(policy) }.rgSettingsLink("test")
            Button("NetworkPolicy.Apply".i18n(lang)) { RGSimpleSettings.shared.networkPolicy = policy; saved() }.disabled(policy.dohEnabled && !RGNetworkPolicy.validEndpoint(policy.endpoint)).rgSettingsLink("apply")
        }.onReceive(NotificationCenter.default.publisher(for: RGNetworkPolicy.didChange)) { _ in policy = RGSimpleSettings.shared.networkPolicy }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("Regram.DNS.FailureChanged"))) { _ in dnsFailure = MTRGDNSDiagnostics.lastFailure(endpoint: policy.endpoint) }
        .onChange(of: policy.endpoint) { value in dnsFailure = MTRGDNSDiagnostics.lastFailure(endpoint: value) }
        .onAppear { dnsFailure = MTRGDNSDiagnostics.lastFailure(endpoint: policy.endpoint) }
    }
}
public func rgNetworkPolicyController(context: AccountContext, focusSetting: String? = nil) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData); controller.title = "NetworkPolicy.Title".i18n(data.strings.rgLanguageCode)
    let view = RGSwiftUIView(legacyController: controller, manageSafeArea: true) { RGNetworkPolicyView(saved: { [weak controller] in guard let controller else { return }; rgPresentSettingsMessage(context: context, controller: controller, titleKey: "NetworkPolicy.Title", text: "NetworkPolicy.Applied".i18n(controller.lang)) }, openTest: { [weak controller] policy in
        (controller?.navigationController as? NavigationController)?.pushViewController(rgDNSDiagnosticsController(context: context, policy: policy))
    }) }
    controller.bind(controller: UIHostingController(rootView: view.rgSettingsPage("networkPolicy", focus: focusSetting), ignoreSafeArea: true)); return controller
}
