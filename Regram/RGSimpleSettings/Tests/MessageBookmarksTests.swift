import Foundation

@main enum MessageBookmarksTests {
    static func main() {
        let suite = CommandLine.arguments[1], mode = CommandLine.arguments[2]
        let defaults = UserDefaults(suiteName: suite)!
        let store = RGMessageBookmarks(defaults: defaults, notifications: NotificationCenter())
        let a = RGBookmarkMessageId(peerId: 100, namespace: 0, id: 7)
        let b = RGBookmarkMessageId(peerId: 200, namespace: 0, id: 7)
        if mode == "restore" {
            defer { defaults.removePersistentDomain(forName: suite) }
            let saved = store.bookmark(accountId: 1, messageId: a)!
            precondition(saved.threadId == 50 && saved.addedAt == 10 && saved.tags == ["Changed"])
            precondition(store.bookmark(accountId: 2, messageId: a)?.tags == ["Account Two"])
            precondition(store.bookmark(accountId: 1, messageId: b) == nil)
            print("Bookmark references and labels survived a separate process with account isolation.")
            return
        }
        store.save(accountId: 1, messageId: a, threadId: 50, tags: [" Work ", "work", "项目", ""], now: 10)
        store.save(accountId: 1, messageId: b, threadId: nil, tags: [], now: 20)
        store.save(accountId: 2, messageId: a, threadId: nil, tags: ["Account Two"], now: 30)
        precondition(store.bookmarks(accountId: 1).map(\.id) == [b, a])
        precondition(store.bookmark(accountId: 1, messageId: a)?.tags == ["Work", "项目"])
        store.save(accountId: 1, messageId: a, threadId: nil, tags: ["Changed"], now: 999)
        precondition(store.bookmarks(accountId: 1).count == 2)
        precondition(store.bookmark(accountId: 1, messageId: a)?.addedAt == 10)
        precondition(store.bookmark(accountId: 1, messageId: a)?.threadId == 50)
        store.remove(accountId: 1, messageId: b)
        precondition(store.bookmarks(accountId: 1).count == 1 && store.bookmarks(accountId: 2).count == 1)
        let emoji = "👨‍👩‍👧‍👦"
        precondition(RGMessageBookmarks.normalizedTags([String(repeating: emoji, count: 40)])[0].count == 32)
        precondition(RGMessageBookmarks.normalizedTags((0..<20).map(String.init)).count == 10)
        precondition(RGMessageBookmarks.normalizedTags(["one\ntwo", "\t\0", "Ａ", "a"]) == ["one two", "Ａ"])
        let bytes = try! JSONEncoder().encode(store.bookmarks(accountId: 1))
        let object = try! JSONSerialization.jsonObject(with: bytes) as! [[String: Any]]
        precondition(Set(object[0].keys) == ["messageId", "threadId", "addedAt", "tags"], "Message bodies must not enter bookmark storage")
        defaults.synchronize()
        print("Bookmark checks passed: distinct peers, accounts, duplicate edits, thread preservation, tag limits and reference-only persistence.")
    }
}
