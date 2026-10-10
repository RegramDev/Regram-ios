import Foundation
import SwiftUI
import UIKit
import RGSwiftUI
import RGStrings
import AccountContext
import Display
import TelegramCore
import Postbox
import SwiftSignalKit

private struct RGRevokedPage {
    let messages: [Message]
    let cursors: [Int32: MessageIndex]
    let ended: Set<Int32>
    let scanned: Int
}

private final class RGRevokedHistory: ObservableObject {
    @Published var peer: EnginePeer?
    @Published var messages: [Message] = []
    @Published var loading = false
    @Published var hasMore = false
    @Published var scanned = 0
    private let context: AccountContext
    private let disposable = MetaDisposable()
    private var cursors: [Int32: MessageIndex] = [:]
    private var ended: Set<Int32> = []
    private var generation = UUID()
    init(context: AccountContext) { self.context = context }
    deinit { self.disposable.dispose() }

    func select(_ peer: EnginePeer) {
        self.disposable.set(nil); self.generation = UUID()
        self.peer = peer; self.messages = []; self.cursors = [:]; self.ended = []; self.scanned = 0; self.loading = false; self.hasMore = true
        self.load()
    }
    func load() {
        guard !self.loading, self.hasMore, let peer = self.peer else { return }
        self.loading = true
        let generation = self.generation, cursors = self.cursors, ended = self.ended
        self.disposable.set((self.context.account.postbox.transaction { transaction -> RGRevokedPage in
            var next = cursors, completed = ended, retained: [Message] = [], scanned = 0
            // Read bounded local pages; no server request or whole-database scan is needed.
            for namespace in [Namespaces.Message.Cloud, Namespaces.Message.Local, Namespaces.Message.SecretIncoming] where !completed.contains(namespace) {
                let from = next[namespace] ?? MessageIndex.upperBound(peerId: peer.id, namespace: namespace)
                let page = transaction.getMessages(peerId: peer.id, namespace: namespace, from: from, includeFrom: false, to: MessageIndex.lowerBound(peerId: peer.id, namespace: namespace), limit: 150)
                scanned += page.count
                retained.append(contentsOf: page.filter { $0.attributes.contains(where: { $0 is RGRevokedMessageAttribute }) })
                if let last = page.last { next[namespace] = last.index }
                if page.count < 150 { completed.insert(namespace) }
            }
            return RGRevokedPage(messages: retained, cursors: next, ended: completed, scanned: scanned)
        } |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self, self.generation == generation else { return }
            let existing = Set(self.messages.map(\.id))
            self.messages.append(contentsOf: page.messages.filter { !existing.contains($0.id) })
            self.messages.sort { $0.index > $1.index }
            self.cursors = page.cursors; self.ended = page.ended; self.scanned += page.scanned
            self.hasMore = page.ended.count < 3; self.loading = false
        }))
    }
    func clearLoaded() {
        guard !self.loading else { return }
        self.loading = true
        let generation = self.generation
        let ids = self.messages.map(\.id)
        self.disposable.set((self.context.account.postbox.transaction { transaction in
            let retainedIds = ids.filter { transaction.getMessage($0)?.attributes.contains(where: { $0 is RGRevokedMessageAttribute }) == true }
            // Explicit local cleanup only. Already revoked records are not deleted for other users.
            self.context.engine.messages.deleteMessages(transaction: transaction, ids: retainedIds)
        } |> deliverOnMainQueue).start(next: { [weak self] _ in
            guard let self, self.generation == generation else { return }
            self.messages.removeAll(); self.loading = false
        }))
    }
}

private struct RGRevokedMessagesView: View {
    @Environment(\.lang) private var lang
    @ObservedObject var history: RGRevokedHistory
    let select: (@escaping (EnginePeer) -> Void) -> Void
    let open: (Message) -> Void
    let clear: (@escaping () -> Void) -> Void
    @State private var query = ""
    private var visible: [Message] { history.messages.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        List {
            Section(footer: Text("Revoked.Notice".i18n(lang))) {
                Button(history.peer?.debugDisplayTitle ?? "ChatPreferences.SelectChat".i18n(lang)) { select { history.select($0) } }
                TextField("Revoked.Search".i18n(lang), text: $query)
            }
            ForEach(visible, id: \.id) { message in
                Button { open(message) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.text.isEmpty ? "Revoked.Media".i18n(lang) : message.text).lineLimit(4).foregroundColor(.primary)
                        Text(Date(timeIntervalSince1970: Double(message.timestamp)), style: .date).font(.caption).foregroundColor(.secondary)
                    }.padding(.vertical, 5)
                }
            }
            if history.peer != nil {
                Section(footer: Text("\(history.scanned) " + "Revoked.Scanned".i18n(lang))) {
                    if history.loading { ProgressView() }
                    else if history.hasMore { Button("Revoked.LoadMore".i18n(lang)) { history.load() } }
                    else if visible.isEmpty { Text("Revoked.Empty".i18n(lang)).foregroundColor(.secondary) }
                    if !history.messages.isEmpty { Button("Revoked.ClearLoaded".i18n(lang), role: .destructive) { clear { history.clearLoaded() } }.disabled(history.loading) }
                }
            }
        }
    }
}

func rgRevokedMessagesController(context: AccountContext) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "Revoked.Title".i18n(data.strings.baseLanguageCode)
    let history = RGRevokedHistory(context: context)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: {
        RGRevokedMessagesView(history: history, select: { [weak controller] completion in
            guard let controller else { return }; rgSelectSettingsChat(context: context, controller: controller, completion: completion)
        }, open: { [weak controller] message in
            guard let navigation = controller?.navigationController as? NavigationController, let peer = history.peer, peer.id == message.id.peerId else { return }
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigation, context: context, chatLocation: .peer(peer), subject: .message(id: .id(message.id), highlight: nil, timecode: nil, setupReply: false)))
        }, clear: { [weak controller] apply in
            let current = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: current)
            sheet.setItemGroups([ActionSheetItemGroup(items: [ActionSheetTextItem(title: "Revoked.Clear.Notice".i18n(current.strings.baseLanguageCode)), ActionSheetButtonItem(title: current.strings.Common_Delete, color: .destructive, action: { [weak sheet] in sheet?.dismissAnimated(); apply() })]), ActionSheetItemGroup(items: [ActionSheetButtonItem(title: current.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])])
            controller?.present(sheet, in: .window(.root))
        })
    })
    controller.bind(controller: UIHostingController(rootView: content, ignoreSafeArea: true))
    return controller
}
