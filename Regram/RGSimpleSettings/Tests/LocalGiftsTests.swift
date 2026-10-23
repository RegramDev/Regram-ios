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
        for key in ["tonBalance", "appearance", "profileGiftId", "nameGiftId", "phoneEnabled", "phoneNumber", "ratingEnabled", "ratingLevel", "walletCardEnabled"] { old.removeValue(forKey: key) }
        var oldPurchases = old["purchases"] as! [[String: Any]]
        oldPurchases[0].removeValue(forKey: "currency"); oldPurchases[0].removeValue(forKey: "savedToProfile")
        oldPurchases[0].removeValue(forKey: "pinnedToTop")
        old["purchases"] = oldPurchases
        defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: "regram.localGifts.v1.legacy")
        let legacy = store.state(account: "legacy")
        assert(legacy.balance == 150 && legacy.tonBalance == 1_000_000_000_000)
        assert(legacy.purchases[0].currency == .stars && legacy.purchases[0].savedToProfile)
        assert(!legacy.phoneEnabled && legacy.appearance == nil)
        assert(!legacy.ratingEnabled && legacy.ratingLevel == 0 && !legacy.walletCardEnabled && !legacy.purchases[0].pinnedToTop)
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
        for (code, number, expected) in [("888", "1234 5678", "88812345678"), ("+1", "(234) 567-8900", "12345678900"), ("86", "13812345678", "8613812345678")] {
            assert(RGLocalGiftsStore.normalizedPhone(countryCode: code, number: number) == expected)
        }
        for (code, number) in [("", "12345678"), ("0", "12345678"), ("8888", "12345678"), ("888", ""), ("888", "+12345678"), ("a", "12345678")] {
            assert(RGLocalGiftsStore.normalizedPhone(countryCode: code, number: number) == nil)
        }
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
        // Pins persist, make hidden gifts visible, respect real+local capacity, and survive disabling.
        let first = raced.purchases[0].id, second = raced.purchases[1].id
        _ = try store.setVisibility(account: account, id: first, saved: false).get()
        let pinned = try store.setPinned(account: account, id: first, pinned: true, maximumCount: 1).get()
        assert(pinned.purchases[0].pinnedToTop && pinned.purchases[0].savedToProfile)
        assert(RGLocalGiftsStore(defaults: defaults).state(account: account) == pinned)
        _ = try store.setPinned(account: account, id: first, pinned: true, maximumCount: 0).get()
        failure(store.setPinned(account: account, id: second, pinned: true, maximumCount: 1), .pinnedLimitReached)
        assert(store.state(account: account) == pinned)
        _ = try store.setEnabled(account: account, enabled: false).get()
        failure(store.setPinned(account: account, id: first, pinned: false), .disabled)
        assert(store.state(account: account).purchases[0].pinnedToTop)
        _ = try store.setEnabled(account: account, enabled: true).get()
        let unpinned = try store.setVisibility(account: account, id: first, saved: false).get()
        assert(!unpinned.purchases[0].pinnedToTop)
        for purchase in raced.purchases.prefix(RGLocalGiftsStore.maximumPinnedGifts) {
            _ = try store.setPinned(account: account, id: purchase.id, pinned: true, maximumCount: 100).get()
        }
        failure(store.setPinned(account: account, id: raced.purchases[12].id, pinned: true, maximumCount: 100), .pinnedLimitReached)
        failure(store.setPinned(account: "live:456", id: first, pinned: true), .disabled)
        let removedPin = try store.remove(account: account, id: first).get()
        assert(!removedPin.purchases.contains { $0.id == first })
        // Rating is independent of gift mode, signed, account-scoped and reversible.
        _ = try store.setEnabled(account: account, enabled: false).get()
        for level: Int32 in [-999, -1, 0, 88, 999] {
            let rating = try store.setRating(account: account, enabled: true, level: level).get()
            assert(rating.ratingEnabled && rating.ratingLevel == level && !rating.enabled)
            assert(RGLocalGiftsStore(defaults: defaults).state(account: account) == rating)
        }
        let beforeInvalidRating = store.state(account: account)
        for level: Int32 in [-1000, 1000, .min, .max] { failure(store.setRating(account: account, enabled: true, level: level), .invalidAmount) }
        assert(store.state(account: account) == beforeInvalidRating)
        let ratingOff = try store.setRating(account: account, enabled: false, level: -1).get()
        assert(!ratingOff.ratingEnabled && ratingOff.ratingLevel == -1)
        let wallet = try store.setWalletCardEnabled(account: account, enabled: true).get()
        assert(wallet.walletCardEnabled && !wallet.enabled && !wallet.ratingEnabled)
        assert(RGLocalGiftsStore(defaults: defaults).state(account: account).walletCardEnabled)
        assert(!store.state(account: "live:456").walletCardEnabled && !store.state(account: "test:123").ratingEnabled)
        _ = try store.setEnabled(account: account, enabled: true).get()
        assert(store.state(account: account).walletCardEnabled)
        _ = try store.setWalletCardEnabled(account: account, enabled: false).get()
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
        let appearanceAccount = "appearance"
        _ = try store.setEnabled(account: appearanceAccount, enabled: true).get()
        for _ in 0..<3 { _ = try store.purchase(account: appearanceAccount, title: "gift", price: 1, gift: payload).get() }
        let ids = store.state(account: appearanceAccount).purchases.map(\.id)
        let appearance = try JSONSerialization.data(withJSONObject: ["nameCollectible": ["id": -1], "emojiStatus": ["id": -2], "profileColor": 7, "replyFileId": 99, "backgroundFileId": 100])
        _ = try store.setAppearance(account: appearanceAccount, profileGiftId: ids[0], nameGiftId: ids[1], appearance: appearance).get()
        let afterNameRemoval = try store.remove(account: appearanceAccount, id: ids[1]).get()
        let fields = try JSONSerialization.jsonObject(with: afterNameRemoval.appearance!) as! [String: Any]
        assert(afterNameRemoval.profileGiftId == ids[0] && afterNameRemoval.nameGiftId == nil)
        assert(fields["nameCollectible"] == nil && fields["emojiStatus"] != nil && fields["profileColor"] as? Int == 7 && fields["replyFileId"] as? Int == 99)
        _ = try store.setAppearance(account: appearanceAccount, profileGiftId: ids[0], nameGiftId: ids[2], appearance: appearance).get()
        let afterProfileRemoval = try store.remove(account: appearanceAccount, id: ids[0], mediaIds: [100]).get()
        let remaining = try JSONSerialization.jsonObject(with: afterProfileRemoval.appearance!) as! [String: Any]
        assert(afterProfileRemoval.profileGiftId == nil && afterProfileRemoval.nameGiftId == ids[2])
        assert(remaining["emojiStatus"] == nil && remaining["nameCollectible"] != nil && remaining["backgroundFileId"] == nil && remaining["profileColor"] as? Int == 7 && remaining["replyFileId"] as? Int == 99)
        assert(RGLocalGiftsStore(defaults: defaults).state(account: appearanceAccount) == afterProfileRemoval)
        print("Local currency, phone, appearance migration/lifecycle and gift ledger: purchase, insufficient balance, validation, persistence, account isolation, disable/restore, removal, concurrent charging and corruption checks passed")
    }
}
