import Foundation
import SwiftUI
import Combine
import UIKit
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import AccountContext
import Display

private struct RGDiagnosticsView: View {
    @Environment(\.lang) private var lang
    @StateObject var network: RGDatacenterDiagnostics
    @State private var snapshot = RGTransferStatistics.shared.snapshot()
    @State private var testing = false
    @State private var timing: Double?
    @State private var benchmark = RGFilterBenchmarkSession()
    @State private var benchmarkQueue = DispatchQueue(label: "Regram.filter-benchmark", qos: .userInitiated)
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private func milliseconds(_ value: Double?) -> String { value.map { String(format: "%.0f ms", $0) } ?? "—" }
    var body: some View {
        List {
            Section(header: Text("Diagnostics.Connection.Title".i18n(lang))) {
                Text(network.routeKey.i18n(lang))
                HStack { Text("Diagnostics.Connection.CurrentDC".i18n(lang)); Spacer(); Text(RGDatacenterLocation.title(network.currentDatacenter)) }
                Text(network.connectionKey.i18n(lang)).foregroundColor(.secondary)
            }
            Section(header: Text("Diagnostics.DC.Title".i18n(lang)), footer: Text("Diagnostics.DC.Notice".i18n(lang))) {
                Button((network.running ? "Diagnostics.DC.Cancel" : "Diagnostics.DC.Start").i18n(lang)) { if network.running { network.cancel() } else { network.start() } }.rgSettingsLink("datacenters")
                ForEach(1...5, id: \.self) { dc in
                    let value = network.results[dc]!
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(RGDatacenterLocation.title(dc)).font(.headline); Spacer(); if network.running && !value.completed { ProgressView() } }
                        Text("Diagnostics.DC.Connection".i18n(lang) + ": " + (value.connectionFailed ? (value.connectionTimedOut ? "Diagnostics.DC.Timeout" : "Diagnostics.DC.Failed").i18n(lang) : milliseconds(value.connectionMilliseconds))).font(.footnote).foregroundColor(.secondary)
                        HStack { Text("Diagnostics.DC.Average".i18n(lang) + ": " + milliseconds(value.average)); Spacer(); Text("Diagnostics.DC.Minimum".i18n(lang) + ": " + milliseconds(value.minimum)) }.font(.footnote)
                        Text("Diagnostics.DC.Samples".i18n(lang) + ": \(value.samples.count)/3").font(.footnote).foregroundColor(.secondary)
                        Text("Diagnostics.DC.Variation".i18n(lang) + ": " + milliseconds(value.variation)).font(.footnote)
                        Text("Diagnostics.DC.Failures".i18n(lang) + ": \(value.failures)/3 · " + "Diagnostics.DC.Timeouts".i18n(lang) + ": \(value.timeouts)").font(.footnote).foregroundColor(.secondary)
                    }.padding(.vertical, 4)
                }
                if network.cancelled { Text("Diagnostics.DC.Cancelled".i18n(lang)).foregroundColor(.secondary) }
                Button("Diagnostics.CopyReport".i18n(lang)) { UIPasteboard.general.string = network.report(language: lang, filterMilliseconds: timing) }
            }

            Section(header: Text("Diagnostics.Download".i18n(lang)), footer: Text("Diagnostics.Download.Notice".i18n(lang))) {
                HStack { Text("Diagnostics.Speed".i18n(lang)); Spacer(); Text(ByteCountFormatter.string(fromByteCount: snapshot.roundedBytesPerSecond, countStyle: .file) + "/s").monospacedDigit() }
                HStack { Text("Diagnostics.Received".i18n(lang)); Spacer(); Text(ByteCountFormatter.string(fromByteCount: snapshot.receivedBytes, countStyle: .file)).monospacedDigit() }
                Text((RGSimpleSettings.DownloadSpeedBoostValues(rawValue: RGSimpleSettings.shared.downloadSpeedBoost) == .enabled ? "Diagnostics.Boost.On" : "Diagnostics.Boost.Off").i18n(lang))
            }.rgSettingsLink("transfer")
            Section(header: Text("Diagnostics.Filter".i18n(lang)), footer: Text("Diagnostics.Filter.Notice".i18n(lang))) {
                HStack {
                    Button("Diagnostics.Filter.Run".i18n(lang)) {
                        let token = benchmark.begin()
                        let rules = RGSimpleSettings.shared.messageFilterRules
                        let session = benchmark
                        testing = true
                        benchmarkQueue.async {
                            let result = RGFilterBenchmark.measure(rules: rules, shouldContinue: { session.isActive(token) })
                            DispatchQueue.main.async {
                                guard session.finish(token) else { return }
                                timing = result?.averageMilliseconds; testing = false
                            }
                        }
                    }
                    Spacer()
                    ProgressView().opacity(testing ? 1 : 0).accessibilityHidden(!testing)
                }
                HStack {
                    Text("Diagnostics.Filter.Average".i18n(lang))
                    Spacer()
                    Text(timing.map { String(format: "%.2f ms", $0) } ?? "—").monospacedDigit()
                }
                Text("\(RGSimpleSettings.shared.messageFilterRules.count) " + "Diagnostics.Rules".i18n(lang))
            }.rgSettingsLink("filter")
            Section(footer: Text("Diagnostics.Media.Notice".i18n(lang))) {
                Text((RGSimpleSettings.shared.mediaLoadingExperiment ? "Diagnostics.Media.On" : "Diagnostics.Media.Off").i18n(lang))
            }
        }
        .transaction { $0.animation = nil }
        .onReceive(timer) { _ in
            let value = RGTransferStatistics.shared.snapshot()
            if value != snapshot { snapshot = value }
        }
        .onDisappear { benchmark.cancel(); network.cancel(); testing = false }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in benchmark.cancel(); network.cancel(); testing = false }
    }
}

func rgDiagnosticsController(context: AccountContext, focusSetting: String? = nil) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "Diagnostics.Title".i18n(data.strings.rgLanguageCode)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: { RGDiagnosticsView(network: RGDatacenterDiagnostics(context: context)) })
    controller.bind(controller: UIHostingController(rootView: content.rgSettingsPage("diagnostics", focus: focusSetting), ignoreSafeArea: true))
    return controller
}
