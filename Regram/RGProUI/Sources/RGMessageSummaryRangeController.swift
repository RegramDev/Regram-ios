// MARK: Regram — time-bounded, cancellable paging in the current chat or topic, before any API upload.
import Foundation
import SwiftUI
import UIKit
import Display
import AccountContext
import TelegramCore
import Postbox
import SwiftSignalKit
import RGSwiftUI
import RGSimpleSettings
import RGStrings

private final class RGSummaryRangeLoader: ObservableObject {
    @Published var loading = false
    @Published var messages: [Message] = []
    @Published var errorKey: String?
    private let context: AccountContext
    private let peerId: PeerId
    private let threadId: Int64?
    private let request = MetaDisposable()
    private var generation = UUID()
    init(context: AccountContext, peerId: PeerId, threadId: Int64?) { self.context = context; self.peerId = peerId; self.threadId = threadId }
    deinit { request.dispose() }
    func cancel() { generation = UUID(); request.set(nil); loading = false }
    func load(from: Date, to: Date) {
        cancel(); messages = []; errorKey = nil
        guard RGSimpleSettings.shared.messageSummaryEnabled, from < to, to.timeIntervalSince1970 <= Double(Int32.max), from.timeIntervalSince1970 > 0 else { errorKey = "Summary.RangeInvalid"; return }
        let token = UUID(); generation = token; loading = true
        let lower = Int32(from.timeIntervalSince1970), upper = Int32(to.timeIntervalSince1970)
        let location = SearchMessagesLocation.peer(peerId: peerId, fromId: nil, tags: nil, reactions: nil, threadId: threadId, minDate: lower, maxDate: upper)
        var seen = Set<MessageId>(), accumulated: [Message] = [], bytes = 0, pages = 0
        func page(_ state: SearchMessagesState?) {
            guard self.generation == token else { return }
            self.request.set((self.context.engine.messages.searchMessages(location: location, query: "", state: state, limit: 100) |> take(1)
                |> map(Optional.init) |> timeout(25, queue: .mainQueue(), alternate: .single(nil)) |> deliverOnMainQueue).start(next: { [weak self] result in
                guard let self, self.generation == token else { return }
                guard let (result, next) = result else { self.loading = false; self.errorKey = "Summary.RangeFailed"; return }
                pages += 1
                for message in result.messages where message.timestamp >= lower && message.timestamp <= upper && seen.insert(message.id).inserted {
                    guard !message.text.isEmpty, !message.containsSecretMedia, !message.isCopyProtected() else { continue }
                    bytes += message.text.utf8.count + 10
                    accumulated.append(message)
                }
                guard bytes <= 64000, accumulated.count <= 5000, pages <= 100 else { self.loading = false; self.errorKey = "Summary.RangeTooLarge"; return }
                if result.completed {
                    self.messages = accumulated.sorted { $0.index < $1.index }; self.loading = false
                    if self.messages.isEmpty { self.errorKey = "Summary.RangeEmpty" }
                } else if state == next { self.loading = false; self.errorKey = "Summary.RangeFailed" }
                else { DispatchQueue.main.async { page(next) } }
            }))
        }
        page(nil)
    }
}
private struct RGSummaryRangeView: View {
    @Environment(\.lang) private var lang
    @Environment(\.rgSettingsColors) private var colors
    @ObservedObject var loader: RGSummaryRangeLoader
    let selectedMessages: [Message]
    let open: ([Message]) -> Void
    @State private var preset = "hour"
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var end = Date()
    var body: some View {
        RGSettingsList {
            RGSettingsSection(footer: Text("Summary.RangeNotice".i18n(lang))) {
                Picker("Summary.Range".i18n(lang), selection: $preset) {
                    Text("Summary.LastHour".i18n(lang)).tag("hour")
                    Text("Summary.Today".i18n(lang)).tag("today")
                    Text("Summary.LastDay".i18n(lang)).tag("day")
                    Text("Summary.CustomRange".i18n(lang)).tag("custom")
                }.pickerStyle(.menu).disabled(loader.loading)
                if preset == "custom" {
                    DatePicker("Summary.From".i18n(lang), selection: $start, in: ...Date()).disabled(loader.loading)
                    DatePicker("Summary.To".i18n(lang), selection: $end, in: ...Date()).disabled(loader.loading)
                }
                Button((loader.loading ? "Common.Cancel" : "Summary.LoadRange").i18n(lang)) {
                    if loader.loading { loader.cancel(); return }
                    let now = Date()
                    let from = preset == "today" ? Calendar.current.startOfDay(for: now) : preset == "day" ? now.addingTimeInterval(-86400) : preset == "custom" ? start : now.addingTimeInterval(-3600)
                    loader.load(from: from, to: preset == "custom" ? end : now)
                }
                if loader.loading { ProgressView("Summary.LoadingRange".i18n(lang)) }
                if let key = loader.errorKey { Text(key.i18n(lang)).foregroundColor(colors.secondary) }
            }
            if !loader.messages.isEmpty {
                RGSettingsSection {
                    Text("Summary.Selected".i18n(lang) + " \(loader.messages.count)")
                    Button("Summary.ReviewRange".i18n(lang)) { open(loader.messages) }
                }
            }
            if !selectedMessages.isEmpty { RGSettingsSection { Button("Summary.OnlySelected".i18n(lang)) { open(selectedMessages) } } }
        }.environment(\.locale, Locale(identifier: lang)).onDisappear { loader.cancel() }
    }
}
public func rgMessageSummaryRangeController(context: AccountContext, peerId: PeerId, threadId: Int64?, selectedMessages: [Message] = []) -> ViewController? {
    guard RGSimpleSettings.shared.messageSummaryEnabled, peerId.namespace != Namespaces.Peer.SecretChat else { return nil }
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData); controller.title = "Summary.RangeAction".i18n(data.strings.rgLanguageCode)
    let loader = RGSummaryRangeLoader(context: context, peerId: peerId, threadId: threadId)
    let view = RGSwiftUIView(legacyController: controller, manageSafeArea: true) { RGSummaryRangeView(loader: loader, selectedMessages: selectedMessages, open: { [weak controller] messages in
        guard let result = rgMessageSummaryController(context: context, messages: messages, permitsTimeRange: true) else { return }
        (controller?.navigationController as? NavigationController)?.pushViewController(result)
    }) }
    controller.bind(controller: UIHostingController(rootView: view, ignoreSafeArea: true)); return controller
}
