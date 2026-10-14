import Foundation

@main enum GroupRemarksTests {
    static func main() {
        let suite = CommandLine.arguments[1]
        let mode = CommandLine.arguments[2]
        let defaults = UserDefaults(suiteName: suite)!
        let store = RGGroupRemarks(defaults: defaults, notifications: NotificationCenter())
        if mode == "restore" {
            defer { defaults.removePersistentDomain(forName: suite) }
            precondition(store.name(accountId: 1, peerId: 101) == "Project Café")
            precondition(store.name(accountId: 2, peerId: 101) == "Second account")
            precondition(store.name(accountId: 1, peerId: 102) == nil)
            precondition(store.name(accountId: 1, peerId: 103)?.count == RGGroupRemarks.maximumLength)
            print("Group remarks survived a separate process and retained account isolation.")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        precondition(store.name(accountId: 1, peerId: 101) == nil)
        store.setName("  Project Café \n", accountId: 1, peerId: 101)
        store.setName("Second account", accountId: 2, peerId: 101)
        store.setName("Temporary", accountId: 1, peerId: 102)
        precondition(store.name(accountId: 1, peerId: 101) == "Project Café")
        precondition(store.matchingPeerIds(accountId: 1, query: "CAFE project") == [101])
        precondition(store.matchingPeerIds(accountId: 2, query: "project").isEmpty)
        precondition(store.matchingPeerIds(accountId: 1, query: " \n").isEmpty)
        precondition(RGGroupRemarks.normalized("line\none\ttwo") == "line one two")
        store.setName(" \t\n ", accountId: 1, peerId: 102)
        precondition(store.name(accountId: 1, peerId: 102) == nil)
        let emoji = "👨‍👩‍👧‍👦"
        store.setName(String(repeating: emoji, count: 200), accountId: 1, peerId: 103)
        precondition(store.name(accountId: 1, peerId: 103) == String(repeating: emoji, count: RGGroupRemarks.maximumLength))
        let notifications = NotificationCenter()
        let observedStore = RGGroupRemarks(defaults: defaults, notifications: notifications)
        let changes = NSMutableArray()
        let observer = notifications.addObserver(forName: RGGroupRemarks.didChange, object: nil, queue: .main) { notification in
            guard let change = notification.object as? RGGroupRemarkChange else { preconditionFailure("Missing account and peer") }
            precondition(change.accountId == 3 && change.peerId == 104)
            precondition(Thread.isMainThread)
            changes.add(change.peerId)
        }
        observedStore.setName("Name", accountId: 3, peerId: 104)
        observedStore.setName(" Name ", accountId: 3, peerId: 104)
        observedStore.setName("", accountId: 3, peerId: 104)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        notifications.removeObserver(observer)
        precondition(changes.count == 2, "An unchanged name must not trigger another redraw")
        defaults.synchronize()
        print("Group remarks checks passed: isolated accounts, edits, clearing, normalized search, emoji bounds and main-thread change notifications.")
    }
}
