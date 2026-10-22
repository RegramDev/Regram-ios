#!/usr/bin/env python3
"""Exercise production search row transitions, edit ordering and the native catalog adapter."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
pro = (root / 'Regram/RGProUI/Sources/RGProUI.swift').read_text()
native = (root / 'submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift').read_text()
search_ui = (root / 'submodules/SettingsUI/Sources/Search/SettingsSearchItem.swift').read_text()


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


factory = block(pro, 'private func RGProControllerEntries')
edits = pro[pro.index('    }, searchInput: { value in') + len('    }, searchInput: { value in'):pro.index('    }, settingsPage: "pro."')]
adapter = (root / 'Regram/RGSettingsSearch/Sources/RGSettingsSearch.swift').read_text().replace('import AccountContext\n', '').replace('import RGStrings\n', '')
reducer = block(search_ui, '.start(next: { [weak self] queryAndFoundItems, presentationData in')
reducer = reducer[reducer.index(' in\n') + 4:-1]
fixture = r'''
import Foundation
protocol RGItemListSection { var rawValue: Int32 { get } }
PAGES
SECTIONS
LINKS
final class Strings {
    let rgLanguageCode: String
    let Common_Search = "Search", Notifications_Title = "Notifications", Appearance_AppIcon = "App Icon"
    init(rgLanguageCode: String) { self.rgLanguageCode = rgLanguageCode }
}
struct PresentationData { let strings: Strings; let theme = NSObject() }
final class RGItemListCounter { var value = -1; var count: Int { value += 1; return value } }
private enum RGProControllerEntry: Comparable, Identifiable {
    case header(id: Int, section: RGProControllerSection, text: String, badge: String?)
    case toggle(id: Int, section: RGProControllerSection, settingName: RGProToggles, value: Bool, text: String, enabled: Bool)
    case oneFromManySelector(id: Int, section: RGProControllerSection, settingName: RGProOneFromManySetting, text: String, value: String, enabled: Bool)
    case action(id: Int, section: RGProControllerSection, actionType: RGProAction, text: String, kind: ItemListActionKind)
    case searchInput(id: Int, section: RGProControllerSection, title: NSAttributedString, text: String, placeholder: String)
    case disclosure(id: Int, section: RGProControllerSection, link: RGProDisclosureLink, text: String)
    case notice(id: Int, section: RGProControllerSection, text: String)
    case settingsResult(id: Int, section: RGProControllerSection, entry: RGSettingsCatalogEntry)
    var stableId: Int {
        switch self {
        case let .searchInput(id, _, _, _, _), let .disclosure(id, _, _, _), let .notice(id, _, _), let .settingsResult(id, _, _), let .header(id, _, _, _), let .toggle(id, _, _, _, _, _), let .oneFromManySelector(id, _, _, _, _, _), let .action(id, _, _, _, _): return id
        }
    }
    var section: Int32 {
        switch self {
        case let .searchInput(_, section, _, _, _), let .disclosure(_, section, _, _), let .notice(_, section, _), let .settingsResult(_, section, _), let .header(_, section, _, _), let .toggle(_, section, _, _, _, _), let .oneFromManySelector(_, section, _, _, _, _), let .action(_, section, _, _, _): return section.rawValue
        }
    }
    var kind: Int {
        switch self { case .searchInput: return 0; case .disclosure: return 1; case .notice: return 2; case .settingsResult: return 3; case .header: return 4; case .toggle: return 5; case .oneFromManySelector: return 6; case .action: return 7 }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }
}
TOGGLES
SELECTORS
ACTIONS
SETTINGS_PAGES
enum ItemListActionKind { case destructive }
final class RGSimpleSettings {
    static let shared = RGSimpleSettings()
    let inputToolbar = false, mentionAsUserIdLink = false, localPremium = false, disableLinkPreview = false
    let filterNotifications = false, canSharePreferencesWithExtensions = true
    let enablePanguOnReceiving = false, enablePanguOnSending = false, enablePanguOnEditing = false
    enum Format: String { case plain }
    let defaultOutgoingFormat = Format.plain
    let pinnedMessageNotifications = "all", mentionsAndRepliesNotifications = "all"
}
FACTORY
public class ViewController {}
public class NavigationController {}
struct Held<T> { let value: T; func with<R>(_ f: (T) -> R) -> R { f(value) } }
final class Shared {
    let currentPresentationData: Held<PresentationData>
    var opened: [RGSettingsDestination] = []
    init(_ language: String) { currentPresentationData = Held(value: PresentationData(strings: Strings(rgLanguageCode: language))) }
    func makeRGProController(context: AccountContext) -> ViewController { ViewController() }
    func makeRGSettingsController(context: AccountContext, page: String, item: String?) -> ViewController? {
        guard let value = RGSettingsDestination(page: page, item: item) else { return nil }
        opened.append(value); return ViewController()
    }
}
public final class AccountContext { let sharedContext: Shared; init(_ language: String) { sharedContext = Shared(language) } }
ICONS
PRESENTATION
ITEM
ADAPTER
func stringTokens(_ text: String) -> [String] { text.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init) }
func matchStringTokens(_ tokens: [String], with other: [String]) -> Bool { !other.isEmpty && other.allSatisfy { query in tokens.contains { $0.hasPrefix(query) } } }
NATIVE_SEARCH
final class UIImage {}
extension SettingsSearchableItemIcon { func image() -> UIImage? { UIImage() } }
enum SettingsSearchEntry { case result(index: Int, item: SettingsSearchableItem, icon: UIImage?) }
struct SearchTransition { let entries: [SettingsSearchEntry]; let isSearching: Bool }
func preparedSettingsSearchContainerTransition(theme: NSObject, strings: Strings, from: [SettingsSearchEntry], to: [SettingsSearchEntry], interaction: Int, isSearching: Bool, forceUpdate: Bool) -> SearchTransition {
    SearchTransition(entries: to, isSearching: isSearching)
}
final class Atomic<T> {
    var value: T
    init(value: T) { self.value = value }
    func swap(_ next: T) -> T { let previous = value; value = next; return previous }
}
final class ReducerHost {
    let previousEntriesHolder = Atomic<([SettingsSearchEntry], NSObject, Strings)?>(value: nil)
    var transitions: [SearchTransition] = []
    func enqueueTransition(_ value: SearchTransition) { transitions.append(value) }
    func receive(_ value: (String, [SettingsSearchableItem])?, data: PresentationData) {
        let previousEntriesHolder = self.previousEntriesHolder
        let interaction = 0
        let callback: ((String, [SettingsSearchableItem])?, PresentationData) -> Void = { [weak self] queryAndFoundItems, presentationData in
            REDUCER_BODY
        }
        callback(value, data)
    }
}
enum TestLocalizations {
    static var cache: [String: [String: String]] = [:]
    static func values(_ language: String) -> [String: String] {
        if let values = cache[language] { return values }
        let file = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(language + ".lproj/RGLocalizable.strings")
        let values = NSDictionary(contentsOf: file) as? [String: String] ?? [:]
        cache[language] = values
        return values
    }
}
extension String {
    func i18n(_ language: String) -> String { TestLocalizations.values(language)[self] ?? self }
}
final class Queue {
    static let main = Queue()
    static func mainQueue() -> Queue { main }
    var pending: [() -> Void] = []
    func async(_ action: @escaping () -> Void) { pending.append(action) }
    func drain() { while !pending.isEmpty { pending.removeFirst()() } }
}
final class Promise { var values: [String] = []; func set(_ value: String) { values.append(value) } }
@main enum Checks {
    static func main() {
        var transitionCount = 0, routeCount = 0
        for language in ["en", "zh-hans", "zh-hant"] {
            let data = PresentationData(strings: Strings(rgLanguageCode: language))
            for page in [RGProSettingsPage.messages, .input, .privacy, .translation, .media, .appearance, .notifications, .network, .tools] {
                let rows = RGProControllerEntries(presentationData: data, page: page, searchQuery: "")
                precondition(Set(rows.map(\.stableId)).count == rows.count, "Category header identities must not collide with controls: \(page)")
            }
            let queries = ["", "no such setting zzz", "", "font", "unknown zzz", "DNS", "   \n", "字体", "模型", "OpenAI model", "Ｒｅｇｒａｍ 字体", "不存在的设置xyz", ""]
            let states = queries.map { RGProControllerEntries(presentationData: data, page: .home, searchQuery: $0) }
            for from in states { for to in states {
                precondition(Set(to.map(\.stableId)).count == to.count)
                precondition(zip(to, to.dropFirst()).allSatisfy { $0.stableId < $1.stableId })
                let (_, _, updates) = mergeListsStableWithUpdates(leftList: from, rightList: to)
                for (_, entry, previousIndex) in updates {
                    precondition(from[previousIndex].kind == entry.kind, "List updates must never reuse a text node as a disclosure/result node")
                }
                transitionCount += 1
            } }
            for index in [0, 2, 6, 12] {
                precondition(states[index].filter { $0.kind == 1 }.count == 9, "Clearing and whitespace restore all nine categories")
            }
            let context = AccountContext(language)
            let items = rgSettingsSearchableItems(context: context)
            precondition(Set(items.map(\.id)).count == items.count)
            for query in queries + ["DoH", "summary temperature", "盘古", "ReGrAm", "REGRAM PRO", "TTF", "clear", "底栏 搜索"] {
                let expected = Set(RGSettingsCatalog.results(query: query, language: language).map { "regram/" + $0.id })
                let found = Set(searchSettingsItems(items: items, query: query).map(\.id).compactMap { $0.base as? String }.filter { $0.hasPrefix("regram/") })
                precondition(found == expected, "Native and Pro searches must agree on every catalog destination")
            }
            precondition(RGSettingsCatalog.results(query: "Ｒｅｇｒａｍ 字体", language: language).contains { $0.destination.page == "fonts" || $0.destination.item == "fonts" })
            for item in items.dropFirst() {
                item.present(context, nil, { kind, controller in precondition(controller != nil) })
                routeCount += 1
            }
            precondition(context.sharedContext.opened == RGSettingsCatalog.entries.map(\.destination), "Native rows must open the exact canonical destination, not another search page")
            for item in items.dropFirst() {
                precondition(item.withUpdatedTitle("Updated").matchesQuery?("Regram") == true, "Title replacement must retain the catalog matcher")
            }
            let node = ReducerHost()
            node.receive(("font", [items[1]]), data: data)
            node.receive(("no result", []), data: data)
            node.receive(nil, data: data)
            precondition(node.transitions.count == 3 && node.transitions[1].entries.isEmpty && node.transitions[1].isSearching && !node.transitions[2].isSearching, "Native empty search removes old results, then clearing restores idle state")
        }
        let searchPromise = Promise()
        var searchGeneration = 0
        var cancelled = 0
        let cancelSearchSelection: (() -> Void)? = { cancelled += 1 }
        func changed(_ value: String) { EDITS }
        changed("font"); changed("not found"); changed("")
        Queue.main.drain()
        precondition(searchPromise.values == [""] && cancelled == 3, "Only the latest deferred text edit may replace rows")
        changed("DNS"); Queue.main.drain(); changed("DoH"); changed("   "); Queue.main.drain()
        precondition(searchPromise.values == ["", "DNS", "   "], "New edits and clearing remain usable after a previous update")
        print("Settings search passed: \(transitionCount) native list diffs, \(routeCount) canonical result openings, Unicode/catalog parity, idle restoration and latest-edit ordering.")
    }
}
'''
replacements = {
    'PAGES': block(pro, 'public enum RGProSettingsPage:'),
    'SECTIONS': block(pro, 'private enum RGProControllerSection:'),
    'LINKS': block(pro, 'private enum RGProDisclosureLink:'),
    'TOGGLES': block(pro, 'private enum RGProToggles:'),
    'SELECTORS': block(pro, 'private enum RGProOneFromManySetting:'),
    'ACTIONS': block(pro, 'private enum RGProAction:'),
    'SETTINGS_PAGES': block((root / 'Regram/RGSettingsUI/Sources/RGSettingsController.swift').read_text(), 'public enum RGSettingsPage:'),
    'FACTORY': factory,
    'ICONS': block(native, 'enum SettingsSearchableItemIcon'),
    'PRESENTATION': block(native, 'public enum SettingsSearchableItemPresentation'),
    'ITEM': block(native, 'public struct SettingsSearchableItem'),
    'ADAPTER': adapter,
    'NATIVE_SEARCH': block(native, 'func searchSettingsItems('),
    'EDITS': edits,
    'REDUCER_BODY': reducer,
}
for key, value in replacements.items():
    fixture = re.sub(r'\b' + re.escape(key) + r'\b', lambda _: value, fixture)
with tempfile.TemporaryDirectory(prefix='regram-settings-search-') as directory:
    work = Path(directory)
    (work / 'Checks.swift').write_text(fixture)
    sources = ['Regram/RGStrings/Sources/' + name + '.swift' for name in ['RGSettingsLink', 'RGSettingsCatalog', 'RGProSearchIndex']]
    sources += ['submodules/MergeLists/Sources/Identifiable.swift', 'submodules/MergeLists/Sources/MergeLists.swift']
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors'] + sources + [str(work / 'Checks.swift'), '-o', str(work / 'checks')], cwd=root, check=True)
    subprocess.run([str(work / 'checks'), str(root / 'Regram/RGStrings/Strings')], check=True)
