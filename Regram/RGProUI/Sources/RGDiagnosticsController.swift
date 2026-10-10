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
    @State private var snapshot = RGTransferStatistics.shared.snapshot()
    @State private var testing = false
    @State private var timing: Double?
    @State private var benchmark = RGFilterBenchmarkSession()
    @State private var benchmarkQueue = DispatchQueue(label: "Regram.filter-benchmark", qos: .userInitiated)
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        List {
            Section(header: Text("Diagnostics.Download".i18n(lang)), footer: Text("Diagnostics.Download.Notice".i18n(lang))) {
                HStack { Text("Diagnostics.Speed".i18n(lang)); Spacer(); Text(ByteCountFormatter.string(fromByteCount: snapshot.roundedBytesPerSecond, countStyle: .file) + "/s").monospacedDigit() }
                HStack { Text("Diagnostics.Received".i18n(lang)); Spacer(); Text(ByteCountFormatter.string(fromByteCount: snapshot.receivedBytes, countStyle: .file)).monospacedDigit() }
                Text((RGSimpleSettings.DownloadSpeedBoostValues(rawValue: RGSimpleSettings.shared.downloadSpeedBoost) == .enabled ? "Diagnostics.Boost.On" : "Diagnostics.Boost.Off").i18n(lang))
            }
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
            }
            Section(footer: Text("Diagnostics.Media.Notice".i18n(lang))) {
                Text((RGSimpleSettings.shared.mediaLoadingExperiment ? "Diagnostics.Media.On" : "Diagnostics.Media.Off").i18n(lang))
            }
        }
        .transaction { $0.animation = nil }
        .onReceive(timer) { _ in
            let value = RGTransferStatistics.shared.snapshot()
            if value != snapshot { snapshot = value }
        }
        .onDisappear { benchmark.cancel(); testing = false }
    }
}

func rgDiagnosticsController(context: AccountContext) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "Diagnostics.Title".i18n(data.strings.baseLanguageCode)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: { RGDiagnosticsView() })
    controller.bind(controller: UIHostingController(rootView: content, ignoreSafeArea: true))
    return controller
}
