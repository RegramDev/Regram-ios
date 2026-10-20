// MARK: Regram — the account's initial folder is independent of its last visited folder.
import Foundation
import SwiftUI
import UIKit
import AccountContext
import Display
import RGSwiftUI
import RGSimpleSettings
import RGStrings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

private struct RGStartupFolderChoice: Identifiable {
    let id: Int32
    let title: String
}

private final class RGStartupFolderModel: ObservableObject {
    @Published var folders: [RGStartupFolderChoice] = []
    private var disposable: Disposable?
    init(context: AccountContext) {
        self.disposable = (context.engine.peers.updatedChatListFilters() |> deliverOnMainQueue).start(next: { [weak self] filters in
            self?.folders = filters.compactMap { filter in
                if case let .filter(id, title, _, _) = filter { return RGStartupFolderChoice(id: id, title: title.text) }
                return nil
            }
        })
    }
    deinit { self.disposable?.dispose() }
}

private struct RGStartupFolderView: View {
    @Environment(\.lang) private var lang
    @ObservedObject var model: RGStartupFolderModel
    let accountId: Int64
    let allChatsTitle: String
    @State private var mode = RGSimpleSettings.shared.chatListStartupFolderModeValue.rawValue
    @State private var folder: Int32
    init(model: RGStartupFolderModel, accountId: Int64, allChatsTitle: String) {
        self.model = model
        self.accountId = accountId
        self.allChatsTitle = allChatsTitle
        self._folder = State(initialValue: RGSimpleSettings.shared.chatListStartupSpecificFolderId(accountPeerId: accountId) ?? -1)
    }
    var body: some View {
        Form {
            Picker("features.ChatListStartupFolder".i18n(lang), selection: $mode) {
                ForEach(RGFeatureChatListStartupFolderMode.allCases, id: \.rawValue) { value in
                    Text(("features.ChatListStartupFolder." + value.rawValue).i18n(lang)).tag(value.rawValue)
                }
            }.rgSettingsLink("mode")
            if mode == "specific" {
                Picker("features.ChatListStartupFolder.specific".i18n(lang), selection: $folder) {
                    Text(allChatsTitle).tag(Int32(-1))
                    if folder != -1 && !model.folders.contains(where: { $0.id == folder }) {
                        Text("features.ChatListStartupFolder.Unavailable".i18n(lang)).tag(folder).disabled(true)
                    }

                    ForEach(model.folders) { value in Text(value.title).tag(value.id) }
                }.rgSettingsLink("specific")
            }
        }
        .onChange(of: mode) { value in
            RGSimpleSettings.shared.chatListStartupFolderMode = value
            RGSimpleSettings.shared.rememberLastFolder = value == "last"
        }
        .onChange(of: folder) { value in RGSimpleSettings.shared.setChatListStartupSpecificFolderId(value, accountPeerId: accountId) }
    }
}

public func rgStartupFolderController(context: AccountContext, focusSetting: String? = nil) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "features.ChatListStartupFolder".i18n(data.strings.rgLanguageCode)
    let model = RGStartupFolderModel(context: context)
    let view = RGSwiftUIView(legacyController: controller, manageSafeArea: true) {
        RGStartupFolderView(model: model, accountId: context.account.peerId.toInt64(), allChatsTitle: data.strings.ChatList_Tabs_AllChats)
    }
    controller.bind(controller: UIHostingController(rootView: view.rgSettingsPage("startupFolder", focus: focusSetting), ignoreSafeArea: true))
    return controller
}
