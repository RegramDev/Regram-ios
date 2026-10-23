import Foundation

public let FALLBACK_BASE_BUNDLE_ID: String = "com.regram.app"

public func rgBaseBundleIdentifier() -> String {
    return FALLBACK_BASE_BUNDLE_ID
}

// MARK: Regram
/// Entitlement keys this build gates a system call on.
public enum RGEntitlement {
    /// Required by every `INPreferences` / `INInteraction` entry point.
    public static let siri = "com.apple.developer.siri"
    /// Required for a notification service extension to drop a notification instead of merely
    /// rewriting it. Approval-only from Apple, so a re-signed build never has it — without it,
    /// handing the system empty content yields a blank banner rather than no banner.
    public static let userNotificationsFiltering = "com.apple.developer.usernotifications.filtering"
}

// MARK: Regram — the application and extensions always share their declared App Group.
public let rgIsSandboxOnlyBuild = false

/// What the signature this process is *actually* running under grants, as opposed to what the build
/// declared.
///
/// This distinction is load-bearing for a re-signed build: the declared entitlements are replaced
/// wholesale by whatever the signing profile carries, and a free Apple ID carries close to nothing.
/// Several system frameworks respond to a missing entitlement by calling `abort()` rather than
/// returning an error — `-[INPreferences assertThisProcessHasSiriEntitlement]` and
/// `+[CKContainer defaultContainer]` both do, and both from inside a `dispatch_once`, where the
/// exception cannot be caught by anything. So the grant has to be checked before the call, not
/// recovered from after it.
///
/// Read out of the process's **own code signature**, not out of `embedded.mobileprovision`. The
/// profile is the wrong source twice over: an App Store build carries none at all (verified against
/// a decrypted store IPA — only `_CodeSignature` is present), and a re-signing tool is free to
/// install a profile that differs from what it actually signed with. The code signature is what the
/// kernel enforces, so it is the only answer that cannot disagree with reality.
private final class RGGrantedEntitlements {
    static let shared = RGGrantedEntitlements()

    private let lock = NSLock()
    private var didLoad = false
    private var values: [String: Any] = [:]

    /// Extracts the entitlements plist from the `LC_CODE_SIGNATURE` payload of this process's own
    /// executable. Memoised: it cannot change while the process runs.
    ///
    /// Locates the blob by its magic rather than walking the Mach-O load commands and the signature
    /// SuperBlob index. The magic is a 4-byte constant at a blob header, the header carries its own
    /// length, and the payload has to parse as a plist naming an `application-identifier` — three
    /// independent checks, which is enough to reject a coincidental byte match without needing to
    /// handle thin/fat headers, slice offsets and index layouts.
    private func loadIfNeeded() {
        if self.didLoad {
            return
        }
        self.didLoad = true

        guard let url = Bundle.main.executableURL,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return
        }
        // CSMAGIC_EMBEDDED_ENTITLEMENTS, big-endian on disk.
        let magic = Data([0xfa, 0xde, 0x71, 0x71])
        var cursor = data.startIndex
        while let found = data.range(of: magic, in: cursor ..< data.endIndex) {
            cursor = found.upperBound
            let header = found.lowerBound
            guard data.index(header, offsetBy: 8, limitedBy: data.endIndex) != nil else {
                continue
            }
            let length = data[data.index(header, offsetBy: 4) ..< data.index(header, offsetBy: 8)]
                .reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 8, length < 1 << 20,
                  let blobEnd = data.index(header, offsetBy: Int(length), limitedBy: data.endIndex) else {
                continue
            }
            let payload = data[data.index(header, offsetBy: 8) ..< blobEnd]
            guard let plist = (try? PropertyListSerialization.propertyList(from: payload, options: [], format: nil)) as? [String: Any],
                  plist["application-identifier"] != nil else {
                continue
            }
            self.values = plist
            return
        }
    }

    func grants(_ key: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.loadIfNeeded()
        return (self.values[key] as? Bool) == true
    }

    /// App Groups this process is actually entitled to, in the order the signature lists them.
    func appGroups() -> [String] {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.loadIfNeeded()
        return (self.values["com.apple.security.application-groups"] as? [String]) ?? []
    }
}

/// Whether the signature this process is running under grants `entitlement`.
///
/// Gate any system call that aborts on a missing entitlement on this rather than on a build-time
/// flag: the build flag says what was *asked for*, which on a re-signed build is not what was got.
public func rgSignatureGrants(_ entitlement: String) -> Bool {
    return RGGrantedEntitlements.shared.grants(entitlement)
}

public func rgOwnAppGroupIdentifier() -> String {
    return "group.com.regram.app"
}

private func rgAppGroupCandidates() -> [String] {
    return [rgOwnAppGroupIdentifier()]
}

/// Caches only a *successful* resolution.
///
/// `containerURL(forSecurityApplicationGroupIdentifier:)` can return nil for a group this process is
/// entitled to when called very early in launch. Caching that first answer pinned the process to an
/// unreachable identifier for its lifetime, which surfaced as a launch-time "Error 2" on a build
/// that was otherwise fine — so a nil is never remembered.
private final class RGAppGroupResolution {
    static let shared = RGAppGroupResolution()

    private let lock = NSLock()
    private var resolved: (identifier: String, url: URL)?

    func resolve() -> (identifier: String, url: URL)? {
        self.lock.lock()
        if let resolved = self.resolved {
            self.lock.unlock()
            return resolved
        }
        self.lock.unlock()

        for candidate in rgAppGroupCandidates() {
            guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: candidate) else {
                continue
            }
            self.lock.lock()
            self.resolved = (candidate, url)
            self.lock.unlock()
            return (candidate, url)
        }
        return nil
    }
}

/// The App Group that was actually granted and resolved, or nil when this build intentionally uses
/// its private sandbox. Callers that configure optional sharing APIs should use this instead of
/// synthesizing `group.<bundle id>`.
public func rgResolvedAppGroupIdentifier() -> String? {
    return RGAppGroupResolution.shared.resolve()?.identifier
}

/// The App Group this process shares with the rest of the app.
///
/// Returns the identifier that actually **resolved**, not `group.<bundle id>`: it is also used as a
/// `UserDefaults` suite name, so returning an unreachable identifier would silently send every
/// shared setting to the process's own preferences instead of the container the extensions read.
public func rgAppGroupIdentifier() -> String {
    let result: String = rgResolvedAppGroupIdentifier() ?? rgOwnAppGroupIdentifier()

    #if DEBUG
    print("APP_GROUP_IDENTIFIER: \(result)")
    #endif

    return result
}

/// Settings shared by the main application and extensions.
public func rgSharedUserDefaults() -> UserDefaults? {
    return UserDefaults(suiteName: rgAppGroupIdentifier())
}

/// The shared application container; no private-container fallback is used.
public func rgDataContainerURL() -> URL? {
    guard let resolved = RGAppGroupResolution.shared.resolve() else {
        rgRecordResolvedContainer("unavailable:\(rgOwnAppGroupIdentifier())")
        return nil
    }
    rgRecordResolvedContainer("group:\(resolved.identifier)")
    return resolved.url
}

// MARK: Regram
/// Records which container the process ended up on, so the outcome can be read back off a device.
///
/// Written to `UserDefaults.standard` deliberately: that lands in the app's own
/// `Library/Preferences/<bundle id>.plist`, which is one of the few files a host can actually read
/// back over the device file service — the data directories Telegram creates carry a protection
/// class that makes them invisible to it. Without this, the fallback in `rgDataContainerURL()` hides
/// its own outcome: a build that quietly dropped to the private container looks identical to one
/// that got the App Group, except for symptoms (generic notification text) that have several other
/// possible causes.
private func rgRecordResolvedContainer(_ value: String) {
    let key = "rg_resolved_container"
    let defaults = UserDefaults.standard
    guard defaults.string(forKey: key) != value else {
        return
    }
    defaults.set(value, forKey: key)
}
