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
    @State private var generation = UUID()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        List {
            Section(header: Text("Diagnostics.Download".i18n(lang)), footer: Text("Diagnostics.Download.Notice".i18n(lang))) {
                HStack { Text("Diagnostics.Speed".i18n(lang)); Spacer(); Text(ByteCountFormatter.string(fromByteCount: Int64(snapshot.bytesPerSecond), countStyle: .file) + "/s").monospacedDigit() }
                HStack { Text("Diagnostics.Received".i18n(lang)); Spacer(); Text(ByteCountFormatter.string(fromByteCount: snapshot.receivedBytes, countStyle: .file)).monospacedDigit() }
                Text((RGSimpleSettings.shared.downloadSpeedBoost == "medium" ? "Diagnostics.Boost.On" : "Diagnostics.Boost.Off").i18n(lang))
            }
            Section(header: Text("Diagnostics.Filter".i18n(lang)), footer: Text("Diagnostics.Filter.Notice".i18n(lang))) {
                Button("Diagnostics.Filter.Run".i18n(lang)) {
                    let rules = RGSimpleSettings.shared.messageFilterRules.map { rule -> RGMessageFilterRule in var rule = rule; rule.peerIds = []; return rule }
                    let token = UUID(); generation = token; testing = true
                    DispatchQueue.global(qos: .userInitiated).async {
                        let text = String(repeating: "这是一段性能测试消息 Hello Regram 😀 1234567。", count: 15)
                        let started = ProcessInfo.processInfo.systemUptime
                        for _ in 0..<10 { _ = RGMessageFilter.shouldHide(text: text, peerId: nil, rules: rules) }
                        let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 100
                        DispatchQueue.main.async { if generation == token { timing = milliseconds; testing = false } }
                    }
                }.disabled(testing)
                if testing { ProgressView() }
                if let timing { Text(String(format: "%.2f ms", timing)).monospacedDigit() }
                Text("\(RGSimpleSettings.shared.messageFilterRules.count) " + "Diagnostics.Rules".i18n(lang))
            }
            Section(footer: Text("Diagnostics.Media.Notice".i18n(lang))) {
                Text((RGSimpleSettings.shared.mediaLoadingExperiment ? "Diagnostics.Media.On" : "Diagnostics.Media.Off").i18n(lang))
            }
        }
        .onReceive(timer) { _ in snapshot = RGTransferStatistics.shared.snapshot() }
        .onDisappear { generation = UUID(); testing = false }
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
