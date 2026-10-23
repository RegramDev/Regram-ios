import Foundation

@main enum LocalGiftsTests {
    static func main() throws {
        let suite = "Regram.LocalGifts.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RGLocalGiftsStore(defaults: defaults, notifications: NotificationCenter())
        let account = "live:123"
        let payload = Data("fixture".utf8)
        func failure(_ result: Result<RGLocalGiftsState, RGLocalGiftsError>, _ expected: RGLocalGiftsError) {
            guard case let .failure(actual) = result else { fatalError("Expected failure") }
            assert(String(describing: actual) == String(describing: expected))
        }
        failure(store.purchase(account: account, title: "gift", price: 100, gift: payload), .disabled)
        _ = try store.setEnabled(account: account, enabled: true).get()
        _ = try store.setBalance(account: account, balance: 250).get()
        let purchased = try store.purchase(account: account, title: "gift", price: 100, gift: payload).get()
        assert(purchased.balance == 150 && purchased.purchases.count == 1)
        assert(purchased.purchases[0].gift == payload && purchased.purchases[0].price == 100)
        failure(store.purchase(account: account, title: "gift", price: 151, gift: payload), .insufficientStars)
        failure(store.purchase(account: account, title: "gift", price: -1, gift: payload), .invalidAmount)
        failure(store.purchase(account: account, title: "gift", price: 0, gift: payload), .invalidAmount)
        failure(store.purchase(account: account, title: "gift", price: 1, gift: Data()), .invalidAmount)
        failure(store.setBalance(account: account, balance: -1), .invalidAmount)
        failure(store.setBalance(account: account, balance: .max), .invalidAmount)
        assert(store.state(account: account) == purchased)
        assert(!store.state(account: "live:456").enabled && store.state(account: "live:456").purchases.isEmpty)
        assert(store.state(account: "test:123").purchases.isEmpty)
        let reopened = RGLocalGiftsStore(defaults: defaults)
        assert(reopened.state(account: account) == purchased)
        _ = try reopened.setEnabled(account: account, enabled: false).get()
        assert(reopened.state(account: account).purchases.count == 1)
        assert(!store.state(account: account).enabled, "Cached snapshots must notice another store writing")
        failure(reopened.purchase(account: account, title: "gift", price: 100, gift: payload), .disabled)
        _ = try reopened.setEnabled(account: account, enabled: true).get()
        _ = try reopened.remove(account: account, id: purchased.purchases[0].id).get()
        assert(reopened.state(account: account).purchases.isEmpty && reopened.state(account: account).balance == 150)
        // Racing purchases cannot overdraw the ledger or lose records.
        _ = try store.setBalance(account: account, balance: 25).get()
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = store.purchase(account: account, title: "concurrent", price: 1, gift: payload)
        }
        let raced = store.state(account: account)
        assert(raced.balance == 0 && raced.purchases.count == 25 && Set(raced.purchases.map(\.id)).count == 25)
        _ = try store.setBalance(account: account, balance: RGLocalGiftsStore.maximumBalance).get()
        let large = try store.purchase(account: account, title: "large", price: RGLocalGiftsStore.maximumBalance, gift: payload).get()
        assert(large.balance == 0)
        let capacity = "capacity"
        _ = try store.setEnabled(account: capacity, enabled: true).get()
        for _ in 0..<RGLocalGiftsStore.maximumGifts { _ = try store.purchase(account: capacity, title: "gift", price: 1, gift: payload).get() }
        let full = store.state(account: capacity)
        failure(store.purchase(account: capacity, title: "gift", price: 1, gift: payload), .limitReached)
        assert(store.state(account: capacity) == full)
        failure(store.purchase(account: account, title: "oversized", price: 1, gift: Data(repeating: 1, count: 1024 * 1024 + 1)), .invalidAmount)
        let corrupt = Data("broken ledger".utf8)
        defaults.set(corrupt, forKey: "regram.localGifts.v1.corrupt")
        failure(store.setEnabled(account: "corrupt", enabled: true), .storage)
        assert(defaults.data(forKey: "regram.localGifts.v1.corrupt") == corrupt)
        assert(!store.state(account: "corrupt").enabled)
        print("Local gift ledger: purchase, insufficient balance, validation, persistence, account isolation, disable/restore, removal, concurrent charging and corruption checks passed")
    }
}
