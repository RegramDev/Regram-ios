import Foundation
import UIKit
import SwiftUI
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import AccountContext
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UniformTypeIdentifiers

@available(iOS 13.0, *)
private final class MessageFilterModel: NSObject, ObservableObject {
    @Published var rules = RGSimpleSettings.shared.messageFilterRules
    @Published var isEditing = false { didSet { self.updateEditButton() } }
    @Published var busy = false
    @Published var notice: String?
    private weak var host: UIViewController?
    private let strings: PresentationStrings
    private var observer: NSObjectProtocol?
    private let queue = DispatchQueue(label: "regram.filter-files", qos: .userInitiated)
    private var operation: UUID?
    private var cancelled = Atomic(value: false)

    init(strings: PresentationStrings) {
        self.strings = strings
        super.init()
        self.observer = NotificationCenter.default.addObserver(forName: RGSimpleSettings.contentFiltersDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rules = RGSimpleSettings.shared.messageFilterRules
        }
    }
    deinit { let _ = self.cancelled.swap(true); if let observer = self.observer { NotificationCenter.default.removeObserver(observer) } }
    func bind(_ host: UIViewController) { self.host = host; self.updateEditButton() }
    private func updateEditButton() {
        let item = UIBarButtonItem(image: UIImage(systemName: self.isEditing ? "checkmark" : "pencil"), style: .plain, target: self, action: #selector(self.toggleEditing))
        item.accessibilityLabel = self.isEditing ? self.strings.Common_Done : self.strings.Common_Edit
        self.host?.navigationItem.rightBarButtonItem = item
    }
    @objc private func toggleEditing() { self.isEditing.toggle() }
    private func edit(_ action: @escaping () throws -> Void, completion: @escaping (Bool) -> Void = { _ in }) {
        guard !self.busy else { return }
        self.busy = true
        self.cancelled = Atomic(value: false)
        let cancelled = self.cancelled
        let token = UUID()
        self.operation = token
        self.queue.async { [weak self] in
            guard !cancelled.with({ $0 }) else { return }
            let result = Result { try action() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.operation == token else { return }
                self.busy = false
                self.operation = nil
                self.rules = RGSimpleSettings.shared.messageFilterRules
                switch result {
                case .success: completion(true)
                case .failure: self.notice = "MessageFilter.SaveFailed".i18n(self.strings.baseLanguageCode); completion(false)
                }
            }
        }
    }
    func remove(_ ids: Set<String>) {
        self.edit { RGSimpleSettings.shared.updateMessageFilterRules { $0.filter { !ids.contains($0.id) } }; return }
    }
    func save(_ rule: RGMessageFilterRule, completion: @escaping (Bool) -> Void) {
        self.edit({
            guard rule.isValid else { throw RGMessageFilter.ImportError.invalidRules }
            try RGSimpleSettings.shared.updateMessageFilterRules { current in
                guard !current.contains(where: { $0.id != rule.id && RGMessageFilter.equivalent($0, rule) }), let index = current.firstIndex(where: { $0.id == rule.id }) else { throw RGMessageFilter.ImportError.invalidRules }
                var result = current
                result[index] = rule
                return result
            }
        }, completion: completion)
    }
    func add(_ rule: RGMessageFilterRule, completion: @escaping (Bool) -> Void) {
        self.edit({
            guard rule.isValid, RGSimpleSettings.shared.addMessageFilterRule(rule) else { throw RGMessageFilter.ImportError.invalidRules }
        }, completion: completion)
    }

    func validate(_ rule: RGMessageFilterRule, completion: @escaping (Bool) -> Void) {
        self.queue.async {
            let valid = rule.isValid
            DispatchQueue.main.async { completion(valid) }
        }
    }
    func cancel() { let _ = self.cancelled.swap(true); self.operation = nil; self.busy = false }
    func importFile(_ url: URL) {
        guard !self.busy else { return }
        let token = UUID()
        self.operation = token
        self.busy = true
        self.cancelled = Atomic(value: false)
        let cancelled = self.cancelled
        let lang = self.strings.baseLanguageCode
        self.queue.async { [weak self] in
            let result = Result { try RGMessageFilter.readImport(at: url) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.operation == token else { return }
                switch result {
                case let .success(imported):
                    self.queue.async { [weak self] in
                        let merged = Result { try RGSimpleSettings.shared.importMessageFilterRules(imported, isCancelled: { cancelled.with { $0 } }) }
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.operation == token else { return }
                            self.busy = false
                            self.operation = nil
                            switch merged {
                            case let .success(count): self.notice = "MessageFilter.Imported".i18n(lang, args: "\(count)")
                            case .failure: self.notice = "MessageFilter.ImportFailed".i18n(lang)
                            }
                        }
                    }
                case .failure:
                    self.busy = false
                    self.operation = nil
                    self.notice = "MessageFilter.ImportFailed".i18n(lang)
                }
            }
        }
    }
    func exportFile(completion: @escaping (URL) -> Void) {
        guard !self.busy else { return }
        self.busy = true
        let token = UUID()
        self.operation = token
        let rules = self.rules
        self.queue.async { [weak self] in
            let result = Result { () -> URL in
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(RGMessageFilter.exportFileName)
                try Data(RGMessageFilter.encode(rules).utf8).write(to: url, options: .atomic)
                return url
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.operation == token else {
                    if case let .success(url) = result { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                    return
                }
                self.busy = false
                self.operation = nil
                switch result {
                case let .success(url): completion(url)
                case .failure: self.notice = "MessageFilter.ImportFailed".i18n(self.strings.baseLanguageCode)
                }
            }
        }
    }
}

@available(iOS 13.0, *)
private struct FilterDocumentPicker: UIViewControllerRepresentable {
    let picked: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(picked: self.picked) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .plainText], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.json", "public.text"], in: .import)
        }
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let picked: (URL) -> Void
        init(picked: @escaping (URL) -> Void) { self.picked = picked }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { self.picked(url) }
        }
    }
}

@available(iOS 13.0, *)
private struct FilterShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

@available(iOS 13.0, *)
private struct FilterPatternInput: UIViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(text: self.$text) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) { if view.text != self.text { view.text = self.text } }
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textViewDidChange(_ textView: UITextView) { self.text.wrappedValue = textView.text }
    }
}

@available(iOS 13.0, *)
private struct FilterRuleEditor: View {
    @Environment(\.presentationMode) private var presentation
    @ObservedObject var model: MessageFilterModel
    @State var rule: RGMessageFilterRule
    let context: AccountContext
    let strings: PresentationStrings
    init(model: MessageFilterModel, rule: RGMessageFilterRule, context: AccountContext, strings: PresentationStrings) {
        self.model = model; self._rule = State(initialValue: rule); self.context = context; self.strings = strings
    }
    var body: some View {
        NavigationView {
            Form {
                Section(footer: Text("MessageFilter.Regex.Notice".i18n(self.strings.baseLanguageCode))) {
                    FilterPatternInput(text: self.$rule.pattern).frame(minHeight: 150)
                    Toggle("MessageFilter.ContentMatching".i18n(self.strings.baseLanguageCode), isOn: Binding(get: { !self.rule.isRegex }, set: { self.rule.isRegex = !$0 }))
                }
                NavigationLink(destination: FilterScopePicker(context: self.context, selected: self.$rule.peerIds, strings: self.strings)) {
                    Text("MessageFilter.Rule.LimitToChats".i18n(self.strings.baseLanguageCode))
                }
            }
            .navigationBarTitle(Text("MessageFilter.Rule.EditTitle".i18n(self.strings.baseLanguageCode)), displayMode: .inline)
            .navigationBarItems(leading: Button(action: { self.presentation.wrappedValue.dismiss() }) {
                Image(systemName: "xmark").accessibility(label: Text(self.strings.Common_Cancel))
            }, trailing: Button(action: { self.model.save(self.rule) { saved in if saved { self.presentation.wrappedValue.dismiss() } } }) {
                Image(systemName: "checkmark").accessibility(label: Text(self.strings.Common_Done))
            }.disabled(self.rule.pattern.isEmpty || self.model.busy))
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

@available(iOS 13.0, *)
private final class FilterScopeModel: ObservableObject {
    @Published var peers: [EnginePeer] = []
    @Published var hasMore = false
    private let disposable = MetaDisposable()
    private var count = 100
    func load(context: AccountContext, more: Bool = false) {
        if more { self.count += 100 }
        self.disposable.set((combineLatest(context.engine.messages.chatList(group: .root, count: self.count), context.engine.messages.chatList(group: .archive, count: self.count)) |> deliverOnMainQueue).start(next: { [weak self] root, archive in
            var seen = Set<EnginePeer.Id>()
            self?.peers = (root.items + archive.items).compactMap { item in
                guard let peer = item.renderedPeer.peer, seen.insert(peer.id).inserted else { return nil }
                return peer
            }
            self?.hasMore = root.hasEarlier || archive.hasEarlier
        }))
    }
    deinit { self.disposable.dispose() }
}

@available(iOS 13.0, *)
private struct FilterScopePicker: View {
    let context: AccountContext
    @Binding var selected: [Int64]
    let strings: PresentationStrings
    @ObservedObject private var model = FilterScopeModel()
    @State private var query = ""
    init(context: AccountContext, selected: Binding<[Int64]>, strings: PresentationStrings) {
        self.context = context; self._selected = selected; self.strings = strings
    }
    var body: some View {
        List {
            TextField(self.strings.Common_Search, text: self.$query)
            Button("MessageFilter.Rule.AllChats".i18n(self.strings.baseLanguageCode)) { self.selected = [] }
            ForEach(self.model.peers.filter { self.query.isEmpty || $0.debugDisplayTitle.localizedCaseInsensitiveContains(self.query) }, id: \.id) { peer in
                Button(action: {
                    let id = peer.id.toInt64()
                    if self.selected.contains(id) { self.selected.removeAll { $0 == id } } else { self.selected.append(id) }
                }) {
                    HStack { Text(peer.debugDisplayTitle); Spacer(); if self.selected.contains(peer.id.toInt64()) { Image(systemName: "checkmark") } }
                }
            }
            if self.model.hasMore { Button("MessageFilter.LoadMore".i18n(self.strings.baseLanguageCode)) { self.model.load(context: self.context, more: true) } }
        }
        .navigationBarTitle(Text("MessageFilter.SelectChats.Title".i18n(self.strings.baseLanguageCode)), displayMode: .inline)
        .onAppear { self.model.load(context: self.context) }
    }
}

@available(iOS 13.0, *)
private struct MessageFilterView: View {
    private enum Sheet: Identifiable {
        case importFile, share(URL), edit(RGMessageFilterRule)
        var id: String { switch self { case .importFile: return "import"; case .share: return "share"; case let .edit(rule): return rule.id } }
    }
    @ObservedObject var model: MessageFilterModel
    let context: AccountContext
    let strings: PresentationStrings
    @State var pattern: String
    @State var contentMatching: Bool
    @State private var sheet: Sheet?
    @State private var exportedURL: URL?
    private var lang: String { self.strings.baseLanguageCode }
    init(model: MessageFilterModel, context: AccountContext, strings: PresentationStrings, pattern: String, contentMatching: Bool) {
        self.model = model; self.context = context; self.strings = strings
        self._pattern = State(initialValue: pattern); self._contentMatching = State(initialValue: contentMatching)
    }
    var body: some View {
        List {
            Section(footer: Text("MessageFilter.Regex.Notice".i18n(self.lang))) {
                TextField(self.contentMatching ? "MessageFilter.InputPlaceholder".i18n(self.lang) : "MessageFilter.InputPlaceholderRegex".i18n(self.lang), text: self.$pattern).autocapitalization(.none).disableAutocorrection(true)
                Toggle("MessageFilter.ContentMatching".i18n(self.lang), isOn: self.$contentMatching)
                Button("MessageFilter.Add".i18n(self.lang)) {
                    let submitted = self.pattern
                    self.model.add(RGMessageFilterRule(pattern: submitted.trimmingCharacters(in: .whitespacesAndNewlines), isRegex: !self.contentMatching)) { saved in
                        if saved && self.pattern == submitted { self.pattern = "" }
                    }
                }.disabled(self.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || self.model.busy)
            }
            Section {
                Button("MessageFilter.Import".i18n(self.lang)) { self.sheet = .importFile }.disabled(self.model.busy)
                Button("MessageFilter.Export".i18n(self.lang)) { self.model.exportFile { self.exportedURL = $0; self.sheet = .share($0) } }.disabled(self.model.busy || self.model.rules.isEmpty)
                if self.model.busy { Text("MessageFilter.Working".i18n(self.lang)); Button(self.strings.Common_Cancel) { self.model.cancel() } }
            }
            Section(header: Text("MessageFilter.Keywords.Title".i18n(self.lang))) {
                ForEach(self.model.rules.reversed(), id: \.id) { rule in
                    Button(action: { self.sheet = .edit(rule) }) {
                        VStack(alignment: .leading) {
                            Text(rule.pattern).lineLimit(2)
                            Text((rule.isRegex ? "MessageFilter.Rule.Regex" : "MessageFilter.ContentMatching").i18n(self.lang)).font(.caption).foregroundColor(.secondary)
                            if rule.isRegex && RGMessageFilter.isPaused(rule.pattern) { Text("MessageFilter.Rule.Paused".i18n(self.lang)).font(.caption).foregroundColor(.secondary) }
                        }
                    }
                }.onDelete { offsets in
                    let rows = Array(self.model.rules.reversed())
                    self.model.remove(Set(offsets.compactMap { $0 < rows.count ? rows[$0].id : nil }))
                }
            }
        }
        .listStyle(GroupedListStyle())
        .environment(\.editMode, Binding(get: { self.model.isEditing ? .active : .inactive }, set: { self.model.isEditing = $0.isEditing }))
        .sheet(item: self.$sheet, onDismiss: {
            if let url = self.exportedURL { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            self.exportedURL = nil
        }) { sheet in
            Group {
                switch sheet {
                case .importFile: FilterDocumentPicker { url in self.sheet = nil; self.model.importFile(url) }
                case let .share(url): FilterShareSheet(url: url)
                case let .edit(rule): FilterRuleEditor(model: self.model, rule: rule, context: self.context, strings: self.strings)
                }
            }
        }
        .alert(isPresented: Binding(get: { self.model.notice != nil }, set: { if !$0 { self.model.notice = nil } })) {
            Alert(title: Text("MessageFilter.Title".i18n(self.lang)), message: Text(self.model.notice ?? ""), dismissButton: .default(Text(self.strings.Common_OK)))
        }
    }
}

@available(iOS 13.0, *)
public func rgMessageFilterController(context: AccountContext, presentationData: PresentationData? = nil, initialKeyword: String = "") -> ViewController {
    let data = presentationData ?? context.sharedContext.currentPresentationData.with { $0 }
    let wrapper = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    let model = MessageFilterModel(strings: data.strings)
    let host = UIHostingController(rootView: MessageFilterView(model: model, context: context, strings: data.strings, pattern: initialKeyword, contentMatching: !initialKeyword.isEmpty))
    model.bind(host)
    wrapper.bindNativeNavigation(controller: host, title: "MessageFilter.Title".i18n(data.strings.baseLanguageCode), backLabel: data.strings.Common_Back)
    return wrapper
}
