// MARK: Regram — DC testing has its own page and runs only after the user starts it.
import Foundation
import Combine
import SwiftUI
import UIKit
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import AccountContext
import Display

private struct RGDatacenterDiagnosticsView: View {
    @Environment(\.lang) private var lang
    @StateObject var network: RGDatacenterDiagnostics
    private func milliseconds(_ value: Double?) -> String { value.map { String(format: "%.0f ms", $0) } ?? "—" }
    var body: some View {
        List {
            Section(header: Text("Diagnostics.Connection.Title".i18n(lang))) {
                Text(network.routeKey.i18n(lang))
                HStack { Text("Diagnostics.Connection.CurrentDC".i18n(lang)); Spacer(); Text(RGDatacenterLocation.title(network.currentDatacenter)) }
                Text(network.connectionKey.i18n(lang)).foregroundColor(.secondary)
            }
            Section(footer: Text("Diagnostics.DC.Notice".i18n(lang))) {
                Button((network.running ? "Diagnostics.DC.Cancel" : "Diagnostics.DC.Start").i18n(lang)) {
                    if network.running { network.cancel() } else { network.start() }
                }.rgSettingsLink("start")
            }
            ForEach(1...5, id: \.self) { dc in
                if let value = network.results[dc] {
                    Section(header: Text(RGDatacenterLocation.title(dc))) {
                        HStack {
                            Text("Diagnostics.DC.Average".i18n(lang)); Spacer()
                            if network.running && !value.completed { ProgressView() }
                            Text(milliseconds(value.average)).monospacedDigit()
                        }
                        HStack { Text("Diagnostics.DC.Minimum".i18n(lang)); Spacer(); Text(milliseconds(value.minimum)).monospacedDigit() }
                        HStack { Text("Diagnostics.DC.Variation".i18n(lang)); Spacer(); Text(milliseconds(value.variation)).monospacedDigit() }
                        HStack { Text("Diagnostics.DC.Connection".i18n(lang)); Spacer(); Text(value.connectionFailed ? (value.connectionTimedOut ? "Diagnostics.DC.Timeout" : "Diagnostics.DC.Failed").i18n(lang) : milliseconds(value.connectionMilliseconds)) }
                        HStack { Text("Diagnostics.DC.Samples".i18n(lang)); Spacer(); Text("\(value.samples.count)/3") }
                        HStack { Text("Diagnostics.DC.Failures".i18n(lang)); Spacer(); Text("\(value.failures)/3") }
                        HStack { Text("Diagnostics.DC.Timeouts".i18n(lang)); Spacer(); Text("\(value.timeouts)") }
                    }
                }
            }
            Section {
                if network.cancelled { Text("Diagnostics.DC.Cancelled".i18n(lang)).foregroundColor(.secondary) }
                Button("Diagnostics.CopyAverages".i18n(lang)) { UIPasteboard.general.string = network.report() }.rgSettingsLink("copy")
            }
        }.transaction { $0.animation = nil }
        .onDisappear { network.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in network.cancel() }
    }
}

func rgDatacenterDiagnosticsController(context: AccountContext, focusSetting: String? = nil) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "Diagnostics.DC.Title".i18n(data.strings.rgLanguageCode)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: { RGDatacenterDiagnosticsView(network: RGDatacenterDiagnostics(context: context)) })
    controller.bind(controller: UIHostingController(rootView: content.rgSettingsPage("datacenters", focus: focusSetting), ignoreSafeArea: true))
    return controller
}
