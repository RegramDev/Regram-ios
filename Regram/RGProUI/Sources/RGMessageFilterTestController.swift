import Foundation
import SwiftUI
import UIKit
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import AccountContext
import Display
import TelegramPresentationData

private struct RGMessageFilterTestView: View {
    @Environment(\.lang) private var lang
    let rules: [RGMessageFilterRule]
    @State private var text = ""
    @State private var results: [RGMessageFilter.MatchResult] = []
    @State private var running = false

    private func resultKey(_ result: RGMessageFilter.MatchResult) -> String {
        switch result {
        case .matched: return "MessageFilter.Test.Matched"
        case .notMatched: return "MessageFilter.Test.NotMatched"
        case .disabled: return "MessageFilter.Rule.Disabled"
        case .invalidRegex: return "MessageFilter.Rule.InvalidRegex"
        case .timedOut: return "MessageFilter.Test.TimedOut"
        }
    }

    var body: some View {
        List {
            Section(footer: Text("MessageFilter.Test.Notice".i18n(lang))) {
                TextEditor(text: $text).frame(minHeight: 130)
                    .accessibilityIdentifier("regram.filter.test.text")
                Button("MessageFilter.Test.Run".i18n(lang)) {
                    let input = text
                    running = true
                    DispatchQueue.global(qos: .userInitiated).async {
                        let evaluated = rules.map { RGMessageFilter.matchResult(rule: $0, text: input) }
                        DispatchQueue.main.async {
                            if text == input { results = evaluated }
                            running = false
                        }
                    }
                }.disabled(running || text.isEmpty)
                if running { ProgressView() }
            }
            ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                if results.indices.contains(index) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(rule.pattern)
                        Text(resultKey(results[index]).i18n(lang))
                            .foregroundColor(results[index] == .matched ? .accentColor : .secondary)
                        Text((rule.isException ? "MessageFilter.Rule.Keep" : "MessageFilter.Rule.Hide").i18n(lang))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }.onChange(of: text) { _ in results = [] }
    }
}

func rgMessageFilterTestController(context: AccountContext, rules: [RGMessageFilterRule]) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "MessageFilter.Test.Title".i18n(data.strings.baseLanguageCode)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: { RGMessageFilterTestView(rules: rules) })
    controller.bind(controller: UIHostingController(rootView: content, ignoreSafeArea: true))
    return controller
}
