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
        // Existing b34631 ledgers gain independent TON, visibility, appearance and phone defaults.
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(purchased)) as! [String: Any]
        for key in ["tonBalance", "appearance", "profileGiftId", "nameGiftId", "phoneEnabled", "phoneNumber"] { old.removeValue(forKey: key) }
        var oldPurchases = old["purchases"] as! [[String: Any]]
        oldPurchases[0].removeValue(forKey: "currency"); oldPurchases[0].removeValue(forKey: "savedToProfile")
        old["purchases"] = oldPurchases
        defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: "regram.localGifts.v1.legacy")
        let legacy = store.state(account: "legacy")
        assert(legacy.balance == 150 && legacy.tonBalance == 1_000_000_000_000)
        assert(legacy.purchases[0].currency == .stars && legacy.purchases[0].savedToProfile)
        assert(!legacy.phoneEnabled && legacy.appearance == nil)
        for (text, expected) in [("0", Int64(0)), ("1.000000001", 1_000_000_001), ("0,5", 500_000_000), ("9000000", RGLocalGiftsStore.maximumBalance)] {
            assert(RGLocalGiftCurrency.ton.amount(from: text) == expected)
            assert(RGLocalGiftCurrency.ton.amount(from: RGLocalGiftCurrency.ton.text(for: expected)) == expected)
        }
        for text in ["-1", "1.0000000001", "9000000.000000001", "1e6", "1.2.3", ".2", "NaN", "١٢", "999999999999999999999999999999"] {
            assert(RGLocalGiftCurrency.ton.amount(from: text) == nil, text)
        }
        assert(RGLocalGiftCurrency.stars.amount(from: "1.5") == nil)
        _ = try store.setBalance(account: account, balance: 1_000_000_001, currency: .ton).get()
        let tonPurchase = try store.purchase(account: account, title: "TON collectible", price: 1_000_000_000, gift: payload, currency: .ton).get()
        let tonId = tonPurchase.purchases[0].id
        assert(tonPurchase.balance == 150 && tonPurchase.tonBalance == 1 && tonPurchase.purchases[0].currency == .ton)
        failure(store.purchase(account: account, title: "TON collectible", price: 2, gift: payload, currency: .ton), .insufficientTon)
        assert(store.state(account: account) == tonPurchase)
        let hidden = try store.setVisibility(account: account, id: tonId, saved: false).get()
        assert(!hidden.purchases[0].savedToProfile && hidden.tonBalance == 1)
        _ = try store.setAppearance(account: account, profileGiftId: tonId, nameGiftId: tonId, appearance: payload).get()
        assert(RGLocalGiftsStore(defaults: defaults).state(account: account).appearance == payload)
        failure(store.setAppearance(account: account, profileGiftId: UUID(), nameGiftId: nil, appearance: payload), .storage)
        let deleted = try store.remove(account: account, id: tonId).get()
        assert(deleted.appearance == nil && deleted.profileGiftId == nil && deleted.nameGiftId == nil && deleted.tonBalance == 1)
        assert(RGLocalGiftsStore.normalizedPhone(" +1 (234) 567-8900 ") == "12345678900")
        let phoneState = try store.setPhone(account: account, enabled: true, number: "+888 1234 5678").get()
        assert(phoneState.phoneNumber == "88812345678" && phoneState.phoneEnabled)
        assert(!store.state(account: "live:456").phoneEnabled)
        assert(RGLocalGiftsStore(defaults: defaults).state(account: account).phoneNumber == "88812345678")
        failure(store.setPhone(account: account, enabled: true, number: "tel:12345"), .invalidAmount)
        failure(store.setPhone(account: account, enabled: true, number: "+1234"), .invalidAmount)
        assert(store.state(account: account) == phoneState)
        _ = try store.setEnabled(account: account, enabled: false).get()
        assert(store.state(account: account).phoneEnabled, "Phone display has an independent switch")
        _ = try store.setPhone(account: account, enabled: false, number: phoneState.phoneNumber).get()
        _ = try store.setEnabled(account: account, enabled: true).get()
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
        print("Local currency, phone, appearance migration/lifecycle and gift ledger: purchase, insufficient balance, validation, persistence, account isolation, disable/restore, removal, concurrent charging and corruption checks passed")
    }
}
