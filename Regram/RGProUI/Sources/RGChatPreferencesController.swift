import Foundation
import SwiftUI
import Combine
import UIKit
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import AccountContext
import Display
import TelegramCore

func rgSelectSettingsChat(context: AccountContext, controller: ViewController, completion: @escaping (EnginePeer) -> Void) {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let selector = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [], title: "ChatPreferences.SelectChat".i18n(data.strings.baseLanguageCode)))
    selector.peerSelected = { [weak selector] peer, _ in selector?.dismiss(); completion(peer) }
    (controller.navigationController as? NavigationController)?.pushViewController(selector)
}

private struct RGChatPreferencesView: View {
    @Environment(\.lang) private var lang
    let context: AccountContext
    let selectChat: (@escaping (EnginePeer) -> Void) -> Void
    @State private var peer: EnginePeer?
    @State private var preferences = RGChatPreferences()
    @State private var revealed = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section(footer: Text("ChatPreferences.Notice".i18n(lang))) {
                Button(peer?.debugDisplayTitle ?? "ChatPreferences.SelectChat".i18n(lang)) {
                    selectChat { peer in
                        self.peer = peer
                        preferences = RGSimpleSettings.shared.chatPreferences(accountId: context.account.peerId.toInt64(), peerId: peer.id.toInt64())
                        revealed = RGSimpleSettings.shared.temporarilyVisiblePeerIds(accountId: context.account.peerId.toInt64()).contains(peer.id.toInt64())
                    }
                }
            }
            if peer != nil {
                Section {
                    Picker("OutgoingFormatting.Title".i18n(lang), selection: Binding(get: { preferences.formatting ?? "inherit" }, set: { preferences.formatting = $0 == "inherit" ? nil : $0 })) {
                        Text("ChatPreferences.Inherit".i18n(lang)).tag("inherit")
                        ForEach(RGSimpleSettings.DefaultOutgoingFormat.allCases, id: \.rawValue) { format in
                            Text("OutgoingFormatting.\(format.rawValue)".i18n(lang)).tag(format.rawValue)
                        }
                    }
                    Picker("Pangu.Title".i18n(lang), selection: Binding(get: { preferences.panguSpacing.map { $0 ? "on" : "off" } ?? "inherit" }, set: { preferences.panguSpacing = $0 == "inherit" ? nil : $0 == "on" })) {
                        Text("ChatPreferences.Inherit".i18n(lang)).tag("inherit")
                        Text("ChatPreferences.On".i18n(lang)).tag("on")
                        Text("ChatPreferences.Off".i18n(lang)).tag("off")
                    }
                    Button("ChatPreferences.Reset".i18n(lang)) { preferences = RGChatPreferences() }
                }
                Section(footer: Text("ChatPreferences.Reveal.Notice".i18n(lang))) {
                    Button((revealed ? "ChatPreferences.Reveal.End" : "ChatPreferences.Reveal").i18n(lang)) {
                        guard let peer else { return }
                        if revealed { RGSimpleSettings.shared.endTemporaryReveal(accountId: context.account.peerId.toInt64(), peerId: peer.id.toInt64()) }
                        else { RGSimpleSettings.shared.temporarilyReveal(accountId: context.account.peerId.toInt64(), peerId: peer.id.toInt64()) }
                        revealed.toggle()
                    }
                }
            }
        }.onReceive(timer) { _ in
            if let peer { revealed = RGSimpleSettings.shared.temporarilyVisiblePeerIds(accountId: context.account.peerId.toInt64()).contains(peer.id.toInt64()) }
        }.onChange(of: preferences) { value in
            guard let peer else { return }
            RGSimpleSettings.shared.setChatPreferences(value, accountId: context.account.peerId.toInt64(), peerId: peer.id.toInt64())
        }
    }
}

func rgChatPreferencesController(context: AccountContext) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "ChatPreferences.Title".i18n(data.strings.baseLanguageCode)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: {
        RGChatPreferencesView(context: context, selectChat: { [weak controller] completion in
            guard let controller else { return }
            rgSelectSettingsChat(context: context, controller: controller, completion: completion)
        })
    })
    controller.bind(controller: UIHostingController(rootView: content, ignoreSafeArea: true))
    return controller
}
