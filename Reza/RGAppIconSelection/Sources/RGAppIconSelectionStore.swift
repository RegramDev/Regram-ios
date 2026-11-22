// MARK: Regram — persist acknowledged icons without confusing primary with an absent preference.
import Foundation
import RGSimpleSettings

final class RGAppIconSelectionStore {
    static let key = "Regram.AppIconSelection.v1"
    private struct Selection {
        let name: String?
        let pending: Bool
    }
    private struct Request {
        let id: UUID
        let name: String?
        let previousSystemName: String?
        let deadline: TimeInterval
    }
    private let defaults: UserDefaults
    private let clock: () -> TimeInterval
    private var saved: Selection?
    private var restoring = false
    private var active: Request?
    private var latest: Request?

    init(defaults: UserDefaults, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults
        self.clock = clock
        if let value = defaults.dictionary(forKey: Self.key), value["version"] as? Int == 1,
           let primary = value["primary"] as? Bool, let name = value["name"] as? String,
           let pending = value["pending"] as? Bool,
           name.utf8.count <= 128, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
           primary ? name.isEmpty : !name.isEmpty {
            self.saved = Selection(name: primary ? nil : RGAppIconNames.canonicalName(name), pending: pending)
            self.restoring = true
        }
    }

    private static func matches(_ actual: String?, _ requested: String?) -> Bool {
        actual == requested
    }

    /// A stale retired getter must never override an acknowledged new icon or an active request.
    func needsRetiredIconReset(systemName: String?) -> Bool {
        RGAppIconNames.isRetiredSystemName(systemName) && self.active == nil && self.saved?.name == nil
    }

    private func save(_ name: String?, pending: Bool) {
        let name = RGAppIconNames.canonicalName(name)
        if let saved = self.saved, saved.name == name && saved.pending == pending { return }
        self.saved = Selection(name: name, pending: pending)
        self.defaults.set(["version": 1, "primary": name == nil, "name": name ?? "", "pending": pending], forKey: Self.key)
        self.defaults.synchronize()
    }

    func beginRequest(_ name: String?, systemName: String?) -> UUID {
        let request = Request(id: UUID(), name: name, previousSystemName: systemName, deadline: self.clock() + 15)
        self.active = request
        self.latest = request
        return request.id
    }

    func finishRequest(_ id: UUID, succeeded: Bool) {
        // A late completion must not overwrite a newer request or an already observed transition.
        guard self.latest?.id == id, let request = self.active, request.id == id else { return }
        self.active = nil
        if succeeded { self.save(request.name, pending: true) }
    }

    func resolvedName(systemName: String?) -> String? {
        // While applying, expose real UIKit transitions to the coordinator's watchdog.
        if let request = self.active {
            if systemName != request.previousSystemName, Self.matches(systemName, request.name) {
                self.active = nil
                self.restoring = false
                self.save(request.name, pending: false)
                return request.name
            }
            if self.clock() < request.deadline { return systemName }
            self.active = nil
        }
        // A missing/late callback can still converge from an observed system transition.
        if let request = self.latest, systemName != request.previousSystemName, Self.matches(systemName, request.name) {
            self.restoring = false
            self.save(request.name, pending: false)
            return request.name
        }
        guard let saved = self.saved else {
            if systemName != nil { self.save(systemName, pending: false) }
            return systemName
        }
        if Self.matches(systemName, saved.name) {
            self.restoring = false
            if saved.pending { self.save(saved.name, pending: false) }
            return systemName
        }
        // A cold nil getter is not evidence that the acknowledged alternate was reset.
        if self.restoring || saved.pending || (systemName == nil && saved.name != nil) { return saved.name }
        self.save(systemName, pending: false)
        return systemName
    }
}
