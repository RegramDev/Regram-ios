import Foundation
import UIKit
import SwiftUI
import AccountContext
import TelegramCore
import Postbox
import Display
import SwiftSignalKit
import TelegramPresentationData
import RGKeychainBackupManager
import RGSwiftUI
import RGStrings

private struct SessionBackup: Codable {
    var name: String? = nil
    var date = Date()
    let accountRecord: AccountRecord<TelegramAccountManagerTypes.Attribute>
    var peerIdInternal: Int64 { Self.peerId(self.accountRecord) }
    var userId: Int64 { PeerId(self.peerIdInternal).id._internalGetInt64Value() }
    static func peerId(_ record: AccountRecord<TelegramAccountManagerTypes.Attribute>) -> Int64 {
        for case let .backupData(backup) in record.attributes { if let id = backup.data?.peerId { return id } }
        return 0
    }
    static func isLoggedOut(_ record: AccountRecord<TelegramAccountManagerTypes.Attribute>) -> Bool {
        return record.attributes.contains { if case .loggedOut = $0 { return true }; return false }
    }
}

@available(iOS 13.0, *)
private final class SessionBackupModel: ObservableObject {
    @Published var sessions: [SessionBackup] = []
    @Published var loggedIn = Set<Int64>()
    @Published var busy = false
    @Published var notice: String?
    @Published var readFailed = false
    private let context: AccountContext
    private let lang: String
    private let queue = Queue(name: "regram.session-backup", qos: .utility)
    private let operation = MetaDisposable()
    private let accounts = MetaDisposable()
    private var token = UUID()
    private var cancellation = Atomic(value: false)

    init(context: AccountContext, lang: String) {
        self.context = context
        self.lang = lang
        self.accounts.set((context.sharedContext.accountManager.accountRecords() |> deliverOnMainQueue).start(next: { [weak self] view in
            self?.loggedIn = Set(view.records.filter { !SessionBackup.isLoggedOut($0) }.map(SessionBackup.peerId))
        }))
    }
    deinit { let _ = self.cancellation.swap(true); self.operation.dispose(); self.accounts.dispose() }

    private func begin() -> (UUID, Atomic<Bool>)? {
        guard !self.busy else { return nil }
        self.busy = true
        self.token = UUID()
        self.cancellation = Atomic(value: false)
        return (self.token, self.cancellation)
    }
    func cancel() {
        let _ = self.cancellation.swap(true)
        self.operation.set(nil)
        self.token = UUID()
        self.busy = false
        self.notice = "SessionBackup.Cancelled".i18n(self.lang)
        self.refresh()
    }
    func stop() {
        let _ = self.cancellation.swap(true)
        self.operation.set(nil)
        self.token = UUID()
        self.busy = false
    }
    private func finish(_ token: UUID, text: String?, reload: Bool = true) {
        guard self.token == token else { return }
        self.busy = false
        self.operation.set(nil)
        if let text { self.notice = text }
        if reload { self.refresh() }
    }
    private static func read() throws -> (sessions: [SessionBackup], invalid: Int) {
        let items = try KeychainBackupManager.shared.getAllSessons()
        var invalid = 0
        var result: [SessionBackup] = []
        for item in items {
            if let backup = try? JSONDecoder().decode(SessionBackup.self, from: item), backup.peerIdInternal != 0 { result.append(backup) }
            else { invalid += 1 }
        }
        return (result.sorted { $0.date > $1.date }, invalid)
    }
    func refresh() {
        guard let (token, cancelled) = self.begin() else { return }
        self.queue.async { [weak self] in
            guard !cancelled.with({ $0 }) else { return }
            let result = Result { try Self.read() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.token == token else { return }
                switch result {
                case let .success(value):
                    self.sessions = value.sessions
                    self.readFailed = false
                    if value.invalid > 0 { self.notice = "SessionBackup.InvalidEntries".i18n(self.lang, args: "\(value.invalid)") }
                case .failure:
                    self.readFailed = true
                    self.notice = "SessionBackup.Failed".i18n(self.lang)
                }
                self.finish(token, text: nil, reload: false)
            }
        }
    }
    func backup() {
        guard let (token, cancelled) = self.begin() else { return }
        self.operation.set((combineLatest(self.context.sharedContext.accountManager.accountRecords(), self.context.sharedContext.activeAccountsWithInfo)
        |> take(1) |> deliverOn(self.queue)).start(next: { [weak self] records, accounts in
            guard let self else { return }
            var success = 0
            var failed = 0
            for record in records.records where !SessionBackup.isLoggedOut(record) {
                if cancelled.with({ $0 }) { break }
                let id = SessionBackup.peerId(record)
                guard id != 0 else { continue }
                let name = accounts.1.first(where: { $0.peer.id == PeerId(id) })?.peer.debugDisplayTitle
                do {
                    let data = try JSONEncoder().encode(SessionBackup(name: name, accountRecord: record))
                    try KeychainBackupManager.shared.saveSession(id: "\(id)", data)
                    success += 1
                } catch { failed += 1 }
            }
            let text = "SessionBackup.Result".i18n(self.lang, args: "\(success)", "\(failed)")
            DispatchQueue.main.async { [weak self] in self?.finish(token, text: text) }
        }))
    }
    func restore() {
        guard let (token, cancelled) = self.begin() else { return }
        self.queue.async { [weak self] in
            guard let self, !cancelled.with({ $0 }) else { return }
            do {
                let backup = try Self.read()
                self.restoreNext(backup.sessions, index: 0, restored: 0, invalid: backup.invalid, token: token, cancelled: cancelled)
            } catch {
                DispatchQueue.main.async { [weak self] in self?.finish(token, text: "SessionBackup.Failed".i18n(self?.lang ?? "en"), reload: false) }
            }
        }
    }
    private func restoreNext(_ sessions: [SessionBackup], index: Int, restored: Int, invalid: Int, token: UUID, cancelled: Atomic<Bool>) {
        guard !cancelled.with({ $0 }) else { return }
        guard index < sessions.count else {
            let text = "SessionBackup.Result".i18n(self.lang, args: "\(restored)", "\(invalid)")
            DispatchQueue.main.async { [weak self] in self?.finish(token, text: text) }
            return
        }
        let session = sessions[index]
        self.operation.set((self.context.sharedContext.accountManager.transaction { transaction -> Bool in
            guard !cancelled.with({ $0 }) else { return false }
            let records = transaction.getRecords()
            guard !records.contains(where: { SessionBackup.peerId($0) == session.peerIdInternal && !SessionBackup.isLoggedOut($0) }) else { return false }
            var attributes = session.accountRecord.attributes.filter { attribute in
                if case .sortOrder = attribute { return false }
                if case .loggedOut = attribute { return false }
                return true
            }
            let next = records.flatMap { $0.attributes }.compactMap { attribute -> Int32? in if case let .sortOrder(value) = attribute { return value.order }; return nil }.max() ?? 0
            attributes.append(.sortOrder(AccountSortOrderAttribute(order: next + 1)))
            let _ = transaction.createRecord(attributes)
            return true
        } |> deliverOn(self.queue)).start(next: { [weak self] added in
            self?.restoreNext(sessions, index: index + 1, restored: restored + (added ? 1 : 0), invalid: invalid, token: token, cancelled: cancelled)
        }))
    }
    func delete(_ session: SessionBackup?) {
        guard let (token, cancelled) = self.begin() else { return }
        self.queue.async { [weak self] in
            guard !cancelled.with({ $0 }) else { return }
            let result = Result { if let session { try KeychainBackupManager.shared.deleteSession(for: "\(session.peerIdInternal)") } else { try KeychainBackupManager.shared.deleteAllSessions() } }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let text: String?
                switch result { case .success: text = nil; case .failure: text = "SessionBackup.Failed".i18n(self.lang) }
                self.finish(token, text: text)
            }
        }
    }
    func removeFromApp(_ session: SessionBackup) {
        guard let (token, cancelled) = self.begin() else { return }
        self.operation.set((self.context.sharedContext.accountManager.transaction { transaction -> Void in
            guard !cancelled.with({ $0 }) else { return }
            if let record = transaction.getRecords().first(where: { SessionBackup.peerId($0) == session.peerIdInternal }) { transaction.updateRecord(record.id, { _ in nil }) }
        } |> deliverOnMainQueue).start(next: { [weak self] in self?.finish(token, text: nil) }))
    }
}

@available(iOS 13.0, *)
private struct SessionBackupManagerView: View {
    @ObservedObject var model: SessionBackupModel
    let strings: PresentationStrings
    @State private var pendingDelete: SessionBackup?
    @State private var confirmDelete = false
    @State private var pendingRemove: SessionBackup?
    @State private var confirmRemove = false
    private var lang: String { self.strings.baseLanguageCode }
    init(model: SessionBackupModel, strings: PresentationStrings) { self.model = model; self.strings = strings }
    private static let formatter: DateFormatter = {
        let value = DateFormatter(); value.dateStyle = .short; value.timeStyle = .short; return value
    }()
    var body: some View {
        List {
            Section(footer: Text("SessionBackup.Notice".i18n(self.lang))) {
                Button("SessionBackup.Actions.Backup".i18n(self.lang)) { self.model.backup() }.disabled(self.model.busy)
                Button("SessionBackup.Actions.Restore".i18n(self.lang)) { self.model.restore() }.disabled(self.model.busy || self.model.readFailed)
                Button("SessionBackup.Actions.DeleteAll".i18n(self.lang)) { self.pendingDelete = nil; self.confirmDelete = true }.foregroundColor(.red).disabled(self.model.busy)
                if self.model.busy {
                    Text("SessionBackup.Working".i18n(self.lang))
                    Button(self.strings.Common_Cancel) { self.model.cancel() }
                }
                if self.model.readFailed { Button("SessionBackup.Retry".i18n(self.lang)) { self.model.refresh() }.disabled(self.model.busy) }
            }
            Section(header: Text("SessionBackup.Sessions.Title".i18n(self.lang))) {
                ForEach(self.model.sessions, id: \.peerIdInternal) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.name ?? "\(session.userId)")
                        Text("SessionBackup.LastBackupAt".i18n(self.lang, args: Self.formatter.string(from: session.date))).font(.caption).foregroundColor(.secondary)
                        Text((self.model.loggedIn.contains(session.peerIdInternal) ? "SessionBackup.LoggedIn" : "SessionBackup.LoggedOut").i18n(self.lang)).font(.caption)
                    }.contextMenu {
                        Button("SessionBackup.Actions.DeleteOne".i18n(self.lang)) { self.pendingDelete = session; self.confirmDelete = true }.disabled(self.model.busy)
                        Button("SessionBackup.Actions.RemoveFromApp".i18n(self.lang)) { self.pendingRemove = session; self.confirmRemove = true }.disabled(self.model.busy)
                    }
                }
            }
        }
        .listStyle(GroupedListStyle())
        .onAppear { self.model.refresh() }
        .onDisappear { self.model.stop() }
        .actionSheet(isPresented: self.$confirmDelete) {
            ActionSheet(title: Text((self.pendingDelete == nil ? "SessionBackup.DeleteAll.Title" : "SessionBackup.DeleteSingle.Title").i18n(self.lang)), buttons: [.destructive(Text(self.strings.Common_Delete), action: { self.model.delete(self.pendingDelete) }), .cancel(Text(self.strings.Common_Cancel))])
        }
        .alert(isPresented: Binding(get: { self.model.notice != nil || self.confirmRemove }, set: { if !$0 { self.model.notice = nil; self.confirmRemove = false } })) {
            if self.confirmRemove, let session = self.pendingRemove {
                return Alert(title: Text("SessionBackup.RemoveFromApp.Title".i18n(self.lang)), message: Text("SessionBackup.RemoveFromApp.Text".i18n(self.lang, args: session.name ?? "\(session.userId)")), primaryButton: .destructive(Text(self.strings.Common_Delete), action: { self.model.removeFromApp(session) }), secondaryButton: .cancel(Text(self.strings.Common_Cancel)))
            }
            return Alert(title: Text("SessionBackup.Title".i18n(self.lang)), message: Text(self.model.notice ?? ""), dismissButton: .default(Text(self.strings.Common_OK)))
        }
    }
}

@available(iOS 13.0, *)
public func rgSessionBackupManagerController(context: AccountContext, presentationData: PresentationData? = nil) -> ViewController {
    let data = presentationData ?? context.sharedContext.currentPresentationData.with { $0 }
    let wrapper = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    let model = SessionBackupModel(context: context, lang: data.strings.baseLanguageCode)
    let host = UIHostingController(rootView: SessionBackupManagerView(model: model, strings: data.strings))
    wrapper.bindNativeNavigation(controller: host, title: "SessionBackup.Title".i18n(data.strings.baseLanguageCode), backLabel: data.strings.Common_Back)
    return wrapper
}
