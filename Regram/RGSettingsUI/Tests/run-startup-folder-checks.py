#!/usr/bin/env python3
"""Exercise production startup selector actions and folder-removal fallback without accounts."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
selector = (root / 'Regram/RGSettingsUI/Sources/RGStartupFolderSelector.swift').read_text()
selector = '\n'.join(line for line in selector.splitlines() if not line.startswith('import '))
controller = (root / 'submodules/ChatListUI/Sources/ChatListController.swift').read_text()
a = controller.index('            var selectedEntryId = !strongSelf.initializedFilters')
b = controller.index('            let filtersLimit =', a)
fallback = controller[a:b]
fixture = r'''
import Foundation
extension String { func i18n(_ lang: String) -> String { self } }
enum RGFeatureChatListStartupFolderMode: String { case telegramDefault = "telegram", last, specific }
final class RGSimpleSettings {
    static let shared = RGSimpleSettings()
    static let chatListAllChatsFolderId: Int32 = -1
    var chatListStartupFolderMode = "telegram"
    var chatListStartupFolderModeValue: RGFeatureChatListStartupFolderMode { RGFeatureChatListStartupFolderMode(rawValue: chatListStartupFolderMode)! }
    var ids: [Int64: Int32] = [:]
    func chatListStartupSpecificFolderId(accountPeerId: Int64) -> Int32? { ids[accountPeerId] }
    func setChatListStartupSpecificFolderId(_ id: Int32, accountPeerId: Int64) { ids[accountPeerId] = id }
}
struct ChatFolderTitle { let text: String }
enum ChatListFilter { case allChats, filter(Int32, ChatFolderTitle, String?, Int) }
struct Strings { let rgLanguageCode = "en", ChatList_Tabs_AllChats = "All Chats" }
struct PresentationData { let strings = Strings() }
class ActionSheetItem {}
final class ActionSheetButtonItem: ActionSheetItem {
    enum Color { case accent }
    let title: String; let action: () -> Void
    init(title: String, color: Color, action: @escaping () -> Void) { self.title = title; self.action = action }
}
enum EntryId: Equatable { case all, filter(Int32) }
struct Entry { let id: EntryId }
final class Container { var currentItemFilter: EntryId = .all }
final class DisplayNode { let mainContainerNode = Container() }
final class Controller {
    var initializedFilters = true
    let chatListDisplayNode = DisplayNode()
    var tabContainerData: ([Entry], Bool, Int32?)?
}
SELECTOR
func fallback(current: EntryId, previous: [EntryId], available: [EntryId]) -> EntryId {
    let strongSelf = Controller()
    strongSelf.chatListDisplayNode.mainContainerNode.currentItemFilter = current
    strongSelf.tabContainerData = (previous.map { Entry(id: $0) }, false, nil)
    let firstItemEntryId = current
    let resolvedItems = available.map { Entry(id: $0) }
    FALLBACK
    _ = resetCurrentEntry
    return selectedEntryId
}
@main enum Checks {
    static func main() {
        let settings = RGSimpleSettings.shared, data = PresentationData()
        let filters: [ChatListFilter] = [.allChats, .filter(27, ChatFolderTitle(text: "Work"), nil, 0), .filter(35, ChatFolderTitle(text: "Home"), nil, 0)]
        var dismissed = 0, updated = 0
        let items = rgStartupFolderActionItems(filters: filters, accountId: 111, presentationData: data, dismiss: { dismissed += 1 }, updated: { updated += 1 }).map { $0 as! ActionSheetButtonItem }
        precondition(items.map(\.title) == ["features.ChatListStartupFolder.telegram", "features.ChatListStartupFolder.last", "All Chats", "Work", "Home"])
        precondition(settings.ids.isEmpty && dismissed == 0 && updated == 0, "Opening or cancelling the sheet must not write settings")
        items[3].action()
        precondition(settings.chatListStartupFolderMode == "specific" && settings.ids[111] == 27 && settings.ids[222] == nil)
        precondition(rgStartupFolderTitle(filters: filters, accountId: 111, presentationData: data) == "Work")
        precondition(rgStartupFolderTitle(filters: [], accountId: 111, presentationData: data) == "features.ChatListStartupFolder.Unavailable")
        precondition(rgStartupFolderTitle(filters: filters, accountId: 222, presentationData: data) == "features.ChatListStartupFolder.notSet")
        items[2].action()
        precondition(settings.ids[111] == -1 && rgStartupFolderTitle(filters: [], accountId: 111, presentationData: data) == "All Chats")
        items[1].action(); precondition(settings.chatListStartupFolderMode == "last")
        items[0].action(); precondition(settings.chatListStartupFolderMode == "telegram")
        precondition(dismissed == 4 && updated == 4)
        precondition(rgStartupFolderActionItems(filters: [], accountId: 111, presentationData: data, dismiss: {}, updated: {}).count == 3)
        precondition(fallback(current: .filter(27), previous: [.filter(27), .all], available: [.all]) == .all, "Removing index-zero folder must not form a negative range")
        precondition(fallback(current: .filter(35), previous: [.all, .filter(27), .filter(35)], available: [.all, .filter(27)]) == .filter(27), "Prefer the immediate surviving predecessor")
        precondition(fallback(current: .filter(27), previous: [.all, .filter(27)], available: [.all, .filter(27)]) == .filter(27))
        precondition(fallback(current: .filter(35), previous: [], available: [.all]) == .all)
        print("Startup folder checks passed: direct selection, cancellation, titles, missing folders, account mapping, All Chats and safe removal fallback.")
    }
}
'''.replace('SELECTOR', selector).replace('FALLBACK', fallback)
with tempfile.TemporaryDirectory(prefix='regram-startup-folder-') as directory:
    work = Path(directory)
    source = work / 'Checks.swift'
    source.write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors', str(source), '-o', str(work / 'checks')], check=True)
    subprocess.run([str(work / 'checks')], check=True)
