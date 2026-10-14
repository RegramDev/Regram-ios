// MARK: Regram
import Foundation
import SwiftUI
import UIKit
import AccountContext
import Display
import RGSwiftUI
import RGSimpleSettings
import RGStrings

private struct RGNetworkPolicyView: View {
    @Environment(\.lang) private var lang
    @State private var policy = RGSimpleSettings.shared.networkPolicy
    let saved: () -> Void
    var body: some View {
        Form {
            Section(footer: Text("NetworkPolicy.DoHNotice".i18n(lang))) {
                Toggle("NetworkPolicy.DoH".i18n(lang), isOn: $policy.dohEnabled).rgSettingsLink("enabled")
                TextField("NetworkPolicy.Endpoint".i18n(lang), text: $policy.endpoint, prompt: Text("https://example.com/dns-query")).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().rgSettingsLink("endpoint")
                if policy.dohEnabled && !RGNetworkPolicy.validEndpoint(policy.endpoint) { Text("NetworkPolicy.InvalidURL".i18n(lang)).foregroundColor(.secondary) }
            }
            Section(footer: Text("NetworkPolicy.IPNotice".i18n(lang))) {
                Picker("NetworkPolicy.IP".i18n(lang), selection: $policy.ipVersion) {
                    Text("NetworkPolicy.Automatic".i18n(lang)).tag(RGNetworkPolicy.IPVersion.automatic)
                    Text("NetworkPolicy.IPv4".i18n(lang)).tag(RGNetworkPolicy.IPVersion.ipv4)
                    Text("NetworkPolicy.IPv6".i18n(lang)).tag(RGNetworkPolicy.IPVersion.ipv6)
                }.pickerStyle(.menu).rgSettingsLink("ipVersion")
            }
            Button("NetworkPolicy.Apply".i18n(lang)) { RGSimpleSettings.shared.networkPolicy = policy; saved() }.disabled(policy.dohEnabled && !RGNetworkPolicy.validEndpoint(policy.endpoint)).rgSettingsLink("apply")
        }
    }
}
public func rgNetworkPolicyController(context: AccountContext, focusSetting: String? = nil) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData); controller.title = "NetworkPolicy.Title".i18n(data.strings.rgLanguageCode)
    let view = RGSwiftUIView(legacyController: controller, manageSafeArea: true) { RGNetworkPolicyView(saved: { [weak controller] in guard let controller else { return }; rgPresentSettingsMessage(context: context, controller: controller, titleKey: "NetworkPolicy.Title", text: "NetworkPolicy.Applied".i18n(controller.lang)) }) }
    controller.bind(controller: UIHostingController(rootView: view.rgSettingsPage("networkPolicy", focus: focusSetting), ignoreSafeArea: true)); return controller
}
