// MARK: Regram — account-scoped local simulation; never writes Telegram payment data.
import Foundation

public struct RGLocalGiftPurchase: Codable, Equatable {
    public let id: UUID
    public let date: Int32
    public let title: String
    public let price: Int64
    public let gift: Data
}

public struct RGLocalGiftsState: Codable, Equatable {
    public var enabled = false
    public var balance: Int64 = 10000
    public var purchases: [RGLocalGiftPurchase] = []
    public init() {}
}

public enum RGLocalGiftsError: Error {
    case disabled, invalidAmount, insufficientStars, limitReached, storage
}

/// One lock covers reading, charging and persisting a purchase. No optimistic server state.
public final class RGLocalGiftsStore {
    public static let shared = RGLocalGiftsStore()
    public static let didChange = Notification.Name("Regram.LocalGifts.DidChange")
    public static let maximumBalance: Int64 = 9_000_000_000_000_000
    public static let maximumGifts = 500
    private let defaults: UserDefaults
    private let notifications: NotificationCenter
    private let lock = NSLock()
    private var cached: [String: (data: Data, state: RGLocalGiftsState)] = [:]

    public init(defaults: UserDefaults = .standard, notifications: NotificationCenter = .default) {
        self.defaults = defaults
        self.notifications = notifications
    }

    private func key(_ account: String) -> String { "regram.localGifts.v1." + account }

    private func read(_ account: String) throws -> RGLocalGiftsState {
        guard let data = defaults.data(forKey: key(account)) else {
            cached.removeValue(forKey: account)
            return RGLocalGiftsState()
        }
        if let entry = cached[account], entry.data == data { return entry.state }
        guard data.count <= 16 * 1024 * 1024,
              let state = try? JSONDecoder().decode(RGLocalGiftsState.self, from: data),
              (0...Self.maximumBalance).contains(state.balance), state.purchases.count <= Self.maximumGifts,
              Set(state.purchases.map(\.id)).count == state.purchases.count,
              state.purchases.allSatisfy({ $0.price > 0 && $0.price <= Self.maximumBalance && !$0.gift.isEmpty && $0.gift.count <= 1024 * 1024 }) else {
            throw RGLocalGiftsError.storage
        }
        cached[account] = (data, state)
        return state
    }

    public func state(account: String) -> RGLocalGiftsState {
        lock.lock(); defer { lock.unlock() }
        // A malformed local ledger is hidden and never silently overwritten by a purchase.
        return (try? read(account)) ?? RGLocalGiftsState()
    }

    @discardableResult private func update(account: String, _ change: (inout RGLocalGiftsState) throws -> Void) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        lock.lock()
        let result: Result<RGLocalGiftsState, RGLocalGiftsError>
        do {
            var state = try read(account)
            try change(&state)
            let encoded = try JSONEncoder().encode(state)
            guard encoded.count <= 16 * 1024 * 1024 else { throw RGLocalGiftsError.limitReached }
            defaults.set(encoded, forKey: key(account))
            cached[account] = (encoded, state)
            result = .success(state)
        } catch let error as RGLocalGiftsError { result = .failure(error) }
        catch { result = .failure(.storage) }
        lock.unlock()
        if case .success = result {
            notifications.post(name: Self.didChange, object: account)
        }
        return result
    }

    public func setEnabled(account: String, enabled: Bool) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { $0.enabled = enabled }
    }

    public func setBalance(account: String, balance: Int64) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { state in
            guard (0...Self.maximumBalance).contains(balance) else { throw RGLocalGiftsError.invalidAmount }
            state.balance = balance
        }
    }

    public func purchase(account: String, title: String, price: Int64, gift: Data) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { state in
            guard state.enabled else { throw RGLocalGiftsError.disabled }
            guard price > 0 && price <= Self.maximumBalance && !gift.isEmpty && gift.count <= 1024 * 1024 else { throw RGLocalGiftsError.invalidAmount }
            guard state.purchases.count < Self.maximumGifts else { throw RGLocalGiftsError.limitReached }
            guard state.balance >= price else { throw RGLocalGiftsError.insufficientStars }
            let purchase = RGLocalGiftPurchase(id: UUID(), date: Int32(clamping: Int64(Date().timeIntervalSince1970)), title: String(title.prefix(256)), price: price, gift: gift)
            state.balance -= price
            state.purchases.insert(purchase, at: 0)
        }
    }

    public func remove(account: String, id: UUID) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { $0.purchases.removeAll { $0.id == id } }
    }
}
