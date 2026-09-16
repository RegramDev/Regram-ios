import Foundation
import UIKit
import SwiftUI
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import AccountContext
import LegacyUI
import Display
import ItemListUI
import Postbox
import PresentationDataUtils
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

// MARK: Regram — UIDocumentPickerViewController keeps only a weak reference to its delegate, so a
// coordinator created inline would be released before the user picks anything and the callback would
// never fire. Held here for the lifetime of the picker.
private var rgMessageFilterImportDelegate: RGMessageFilterImportDelegate?

private final class RGMessageFilterImportDelegate: NSObject, UIDocumentPickerDelegate {
    private let onPick: (URL) -> Void

    init(onPick: @escaping (URL) -> Void) {
        self.onPick = onPick
        super.init()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            // `.import` hands back a copy in the app's own container, so no security scope to open.
            self.onPick(url)
        }
        rgMessageFilterImportDelegate = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        rgMessageFilterImportDelegate = nil
    }
}

@available(iOS 13.0, *)
struct MessageFilterKeywordInputFieldModifier: ViewModifier {
    @Binding var newKeyword: String
    let onAdd: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content
                .submitLabel(.return)
                .submitScope(false) // TODO(regram): Keyboard still closing
                .interactiveDismissDisabled()
                .onSubmit {
                    onAdd()
                }
        } else {
            content
        }
    }
}


@available(iOS 13.0, *)
struct MessageFilterKeywordInputView: View {
    @Environment(\.lang) var lang: String
    @Binding var newKeyword: String
    let isRegex: Bool
    let onAdd: () -> Void

    /// A regex that does not compile must not be added: it would be inert and look like the filter
    /// silently stopped working, so the add button stays disabled until the pattern parses.
    private var canAdd: Bool {
        let trimmed = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return false
        }
        if isRegex {
            return RGMessageFilter.compiledRegex(for: trimmed) != nil
        }
        return true
    }

    var body: some View {
        HStack {
            TextField(isRegex ? "MessageFilter.InputPlaceholderRegex".i18n(lang) : "MessageFilter.InputPlaceholder".i18n(lang), text: $newKeyword)
                .autocorrectionDisabled(true)
                .autocapitalization(.none)
                .keyboardType(.default)
                .modifier(MessageFilterKeywordInputFieldModifier(newKeyword: $newKeyword, onAdd: onAdd))


            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(canAdd ? .accentColor : .secondary)
                    .imageScale(.large)
            }
            .disabled(!canAdd)
            .buttonStyle(PlainButtonStyle())
        }
    }
}

@available(iOS 13.0, *)
struct MessageFilterView: View {
    weak var wrapperController: LegacyController?
    let selectChats: (Set<Int64>, @escaping (Set<Int64>) -> Void) -> Void
    // MARK: Regram — editing a pattern is a native pushed screen, not a SwiftUI sheet or alert. A
    // modal would have to be presented by the UIHostingController, which is a *child* of the
    // LegacyController here; that never reaches the surface and instead tears this screen down back
    // to Regram Pro. `selectChats` above already pushes a native controller for the same reason.
    let editPatternExternally: (RGMessageFilterRule, @escaping (String) -> Void) -> Void
    @Environment(\.lang) var lang: String

    @State private var newKeyword: String
    @State private var newIsRegex: Bool = false
    @State private var rules: [RGMessageFilterRule] {
        didSet {
            RGSimpleSettings.shared.messageFilterRules = rules
        }
    }

    init(wrapperController: LegacyController?, initialKeyword: String, selectChats: @escaping (Set<Int64>, @escaping (Set<Int64>) -> Void) -> Void, editPatternExternally: @escaping (RGMessageFilterRule, @escaping (String) -> Void) -> Void) {
        self.wrapperController = wrapperController
        self.selectChats = selectChats
        self.editPatternExternally = editPatternExternally
        _newKeyword = State(initialValue: initialKeyword)
        _rules = State(initialValue: RGSimpleSettings.shared.messageFilterRules)
    }

    private func subtitle(for rule: RGMessageFilterRule) -> String {
        var parts: [String] = []
        if rule.isRegex {
            parts.append("MessageFilter.Rule.Regex".i18n(lang))
        }
        if rule.appliesToAllChats {
            parts.append("MessageFilter.Rule.AllChats".i18n(lang))
        } else {
            parts.append("MessageFilter.Rule.SelectedChats".i18n(lang) + " (\(rule.peerIds.count))")
        }
        if rule.isRegex && !rule.isValid {
            parts.append("MessageFilter.Rule.InvalidRegex".i18n(lang))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Regram — export/import sits on the keyword list header rather than in the navigation
    // bar, whose two slots are already taken by the back button and Edit.
    @ViewBuilder
    private var keywordsHeader: some View {
        HStack {
            Text("MessageFilter.Keywords.Title".i18n(lang))
            Spacer()
            if #available(iOS 14.0, *) {
                Menu {
                    Button("MessageFilter.Export".i18n(lang)) { exportRules() }
                    Button("MessageFilter.Import".i18n(lang)) { importRules() }
                } label: {
                    // The header's own font is a small caps caption, which would make the control
                    // both hard to see and hard to hit.
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundColor(.accentColor)
                }
            }
        }
    }

    var bodyContent: some View {
            List {
                Section {
                    // Icon and title
                    VStack(spacing: 8) {
                        Image(systemName: "nosign.app.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)

                        Text("MessageFilter.Title".i18n(lang))
                            .font(.title)
                            .bold()

                        Text("MessageFilter.SubTitle".i18n(lang))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowInsets(EdgeInsets())

                }

                Section(footer: Text("MessageFilter.Regex.Notice".i18n(lang))) {
                    MessageFilterKeywordInputView(newKeyword: $newKeyword, isRegex: newIsRegex, onAdd: addRule)
                    Toggle("MessageFilter.Regex".i18n(lang), isOn: $newIsRegex)
                }

                Section(header: keywordsHeader, footer: Text("MessageFilter.Rules.Notice".i18n(lang))) {
                    ForEach(rules.reversed(), id: \.id) { rule in
                        // Tap edits the keyword, long press reaches everything else. The scope
                        // picker is a full-screen chat selector, which is too heavy to be what a
                        // stray tap lands on.
                        Button(action: {
                            editPattern(of: rule)
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.pattern)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                    Text(subtitle(for: rule))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .contextMenu {
                            Button(action: {
                                editScope(of: rule)
                            }) {
                                Text("MessageFilter.Rule.LimitToChats".i18n(lang))
                            }
                            Button(action: {
                                toggleRegex(of: rule)
                            }) {
                                Text(rule.isRegex ? "MessageFilter.Rule.MakePlain".i18n(lang) : "MessageFilter.Rule.MakeRegex".i18n(lang))
                            }
                            Button(action: {
                                delete(rule)
                            }) {
                                Text("MessageFilter.Rule.Delete".i18n(lang))
                            }
                        }
                    }
                    .onDelete { indexSet in
                        // The list is rendered newest-first, so offsets have to be mapped back.
                        let originalIndices = IndexSet(indexSet.map { rules.count - 1 - $0 })
                        deleteRules(at: originalIndices)
                    }
                }
        }
        .tgNavigationBackButton(wrapperController: wrapperController)
    }

    var body: some View {
        NavigationView {
            if #available(iOS 14.0, *) {
                bodyContent
                    .toolbar {
                        EditButton()
                    }
            } else {
                bodyContent
            }
        }
    }

    private func addRule() {
        let trimmedKeyword = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else { return }
        if newIsRegex, RGMessageFilter.compiledRegex(for: trimmedKeyword) == nil {
            return
        }

        let exists = rules.contains {
            $0.pattern == trimmedKeyword && $0.isRegex == newIsRegex
        }

        guard !exists else {
            return
        }

        withAnimation {
            rules.append(RGMessageFilterRule(pattern: trimmedKeyword, isRegex: newIsRegex))
        }
        newKeyword = ""
    }

    private func editPattern(of rule: RGMessageFilterRule) {
        editPatternExternally(rule) { entered in
            updatePattern(of: rule, to: entered)
        }
    }

    /// Walks to the topmost presented controller. UIKit controllers cannot go through
    /// `present(_:in:)`, and presenting on this screen's own host would put them underneath its modal.
    private func topPresenter() -> UIViewController? {
        var presenter: UIViewController? = wrapperController?.view.window?.rootViewController
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        return presenter
    }

    private func exportRules() {
        guard !rules.isEmpty, let presenter = topPresenter() else {
            return
        }
        let json = RGMessageFilter.encode(rules)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("regram-message-filter.json")
        guard let data = json.data(using: .utf8), (try? data.write(to: url, options: .atomic)) != nil else {
            return
        }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // Required on iPad, where a share sheet without an anchor is a runtime trap.
        controller.popoverPresentationController?.sourceView = presenter.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0.0, height: 0.0)
        presenter.present(controller, animated: true, completion: nil)
    }

    private func importRules() {
        guard let presenter = topPresenter() else {
            return
        }
        let picker = UIDocumentPickerViewController(documentTypes: ["public.json", "public.text"], in: .import)
        let delegate = RGMessageFilterImportDelegate { url in
            guard let data = try? Data(contentsOf: url), let json = String(data: data, encoding: .utf8) else {
                return
            }
            let imported = RGMessageFilter.decode(json)
            guard !imported.isEmpty else {
                return
            }
            // Merged, not replaced: an import should never silently wipe rules the user still wants.
            // Matching pattern + kind is treated as the same rule and skipped, and every imported rule
            // gets a fresh id so it cannot collide with an existing row.
            var merged = rules
            for rule in imported where !merged.contains(where: { $0.pattern == rule.pattern && $0.isRegex == rule.isRegex }) {
                merged.append(RGMessageFilterRule(pattern: rule.pattern, isRegex: rule.isRegex, peerIds: rule.peerIds))
            }
            rules = merged
        }
        picker.delegate = delegate
        rgMessageFilterImportDelegate = delegate
        presenter.present(picker, animated: true, completion: nil)
    }

    /// Rewrites an existing rule's keyword in place, keeping its id so the row it is rendered in
    /// stays the same one, and its scope.
    private func updatePattern(of rule: RGMessageFilterRule, to pattern: String) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        // Editing one rule into an exact duplicate of another would leave two rows that cannot be
        // told apart; drop the edit instead.
        if rules.contains(where: { $0.id != rule.id && $0.pattern == pattern && $0.isRegex == rule.isRegex }) {
            return
        }
        var updated = rules
        updated[index].pattern = pattern
        rules = updated
    }

    private func toggleRegex(of rule: RGMessageFilterRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        var updated = rules
        updated[index].isRegex.toggle()
        withAnimation {
            rules = updated
        }
    }

    private func delete(_ rule: RGMessageFilterRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        deleteRules(at: IndexSet(integer: index))
    }

    private func editScope(of rule: RGMessageFilterRule) {
        selectChats(Set(rule.peerIds)) { selected in
            guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
            var updated = rules
            updated[index].peerIds = Array(selected)
            rules = updated
        }
    }

    private func deleteRules(at offsets: IndexSet) {
        withAnimation {
            rules.remove(atOffsets: offsets)
        }
    }
}

// MARK: Regram — the keyword editor.
//
// A native ItemList screen rather than a SwiftUI sheet or a UIAlertController: the SwiftUI content
// above is hosted by a UIHostingController installed as a *child* of the LegacyController, so
// anything it tries to present modally tears the whole screen down back to Regram Pro instead. The
// chat scope picker below already works around this the same way, by pushing on the wrapper.
//
// A full screen is also what the keyword itself wants — an alert text field shows one short line,
// which is unusable for the regular expressions this list mostly holds.

private final class RGMessageFilterPatternArguments {
    let updateText: (String) -> Void

    init(updateText: @escaping (String) -> Void) {
        self.updateText = updateText
    }
}

private enum RGMessageFilterPatternSection: Int32 {
    case pattern
}

private enum RGMessageFilterPatternEntryTag: ItemListItemTag {
    case pattern

    func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? RGMessageFilterPatternEntryTag {
            return self == other
        } else {
            return false
        }
    }
}

private enum RGMessageFilterPatternEntry: ItemListNodeEntry {
    case pattern(String, String)
    case info(String)

    var section: ItemListSectionId {
        return RGMessageFilterPatternSection.pattern.rawValue
    }

    var stableId: Int32 {
        switch self {
        case .pattern:
            return 0
        case .info:
            return 1
        }
    }

    static func ==(lhs: RGMessageFilterPatternEntry, rhs: RGMessageFilterPatternEntry) -> Bool {
        switch lhs {
        case let .pattern(lhsText, lhsPlaceholder):
            if case let .pattern(rhsText, rhsPlaceholder) = rhs, lhsText == rhsText, lhsPlaceholder == rhsPlaceholder {
                return true
            } else {
                return false
            }
        case let .info(lhsText):
            if case let .info(rhsText) = rhs, lhsText == rhsText {
                return true
            } else {
                return false
            }
        }
    }

    static func <(lhs: RGMessageFilterPatternEntry, rhs: RGMessageFilterPatternEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! RGMessageFilterPatternArguments
        switch self {
        case let .pattern(text, placeholder):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: placeholder, maxLength: nil, sectionId: self.section, style: .blocks, capitalization: false, autocorrection: false, returnKeyType: .default, minimalHeight: 120.0, textUpdated: { updatedText in
                arguments.updateText(updatedText)
            }, tag: RGMessageFilterPatternEntryTag.pattern)
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func rgMessageFilterPatternEditorController(context: AccountContext, rule: RGMessageFilterRule, apply: @escaping (String) -> Void) -> ViewController {
    let statePromise = ValuePromise(rule.pattern, ignoreRepeated: true)
    let stateValue = Atomic(value: rule.pattern)

    var dismissImpl: (() -> Void)?

    let arguments = RGMessageFilterPatternArguments(updateText: { value in
        statePromise.set(stateValue.modify { _ in value })
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, text -> (ItemListControllerState, (ItemListNodeState, RGMessageFilterPatternArguments)) in
        let lang = presentationData.strings.baseLanguageCode
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty keyword matches nothing and an uncompilable expression is inert; either would
        // look like the filter had silently broken. Removing a rule is a separate, explicit action.
        var canSave = !trimmed.isEmpty
        if canSave && rule.isRegex {
            canSave = RGMessageFilter.compiledRegex(for: trimmed) != nil
        }

        let leftNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: {
            dismissImpl?()
        })
        let rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: canSave, action: {
            apply(trimmed)
            dismissImpl?()
        })

        let entries: [RGMessageFilterPatternEntry] = [
            .pattern(text, rule.isRegex ? "MessageFilter.InputPlaceholderRegex".i18n(lang) : "MessageFilter.InputPlaceholder".i18n(lang)),
            .info(rule.isRegex ? "MessageFilter.Rule.EditMessageRegex".i18n(lang) : "MessageFilter.Rule.EditMessage".i18n(lang))
        ]

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("MessageFilter.Rule.EditTitle".i18n(lang)), leftNavigationButton: leftNavigationButton, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, focusItemTag: RGMessageFilterPatternEntryTag.pattern, animateChanges: false)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .modal
    dismissImpl = { [weak controller] in
        controller?.view.endEditing(true)
        controller?.dismiss()
    }
    return controller
}

@available(iOS 13.0, *)
public func rgMessageFilterController(context: AccountContext, presentationData: PresentationData? = nil, initialKeyword: String = "") -> ViewController {
    let theme = presentationData?.theme ?? (UITraitCollection.current.userInterfaceStyle == .dark ? defaultDarkColorPresentationTheme : defaultPresentationTheme)
    let strings = presentationData?.strings ?? defaultPresentationStrings

    let legacyController = LegacySwiftUIController(
        presentation: .navigation,
        theme: theme,
        strings: strings
    )
    // Status bar color will break if theme changed
    legacyController.statusBar.statusBarStyle = theme.rootController
        .statusBarStyle.style
    legacyController.displayNavigationBar = false

    // The chat scope picker is a native controller, so it is pushed on the wrapper rather than
    // presented from SwiftUI.
    let selectChats: (Set<Int64>, @escaping (Set<Int64>) -> Void) -> Void = { [weak legacyController] selected, completion in
        let pickerPresentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = pickerPresentationData.strings.baseLanguageCode
        let picker = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(
            context: context,
            mode: .chatSelection(ContactMultiselectionControllerMode.ChatSelection(
                title: "MessageFilter.SelectChats.Title".i18n(lang),
                searchPlaceholder: pickerPresentationData.strings.ChatListFilter_AddChatsSearchPlaceholder,
                selectedChats: Set(selected.map { PeerId($0) }),
                additionalCategories: nil,
                chatListFilters: nil
            )),
            filters: [],
            alwaysEnabled: true
        ))
        picker.navigationPresentation = .modal
        let _ = (picker.result
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { [weak picker] result in
            guard case let .result(rawPeerIds, _) = result else {
                picker?.dismiss()
                return
            }
            let peerIds = rawPeerIds.compactMap { id -> Int64? in
                switch id {
                case let .peer(peerId):
                    return peerId.toInt64()
                case .deviceContact:
                    return nil
                }
            }
            completion(Set(peerIds))
            picker?.dismiss()
        })
        legacyController?.push(picker)
    }

    let editPattern: (RGMessageFilterRule, @escaping (String) -> Void) -> Void = { [weak legacyController] rule, completion in
        legacyController?.push(rgMessageFilterPatternEditorController(context: context, rule: rule, apply: completion))
    }

    let swiftUIView = RGSwiftUIView<MessageFilterView>(
        legacyController: legacyController,
        content: {
            MessageFilterView(wrapperController: legacyController, initialKeyword: initialKeyword, selectChats: selectChats, editPatternExternally: editPattern)
        }
    )
    let controller = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: controller)

    return legacyController
}
