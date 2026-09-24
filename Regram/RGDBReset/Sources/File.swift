import RGAppGroupIdentifier
import RGStrings
import RGLogging
import UIKit
import Foundation
import Security

private let dbResetKey = "sg_db_reset"
private let dbHardResetKey = "sg_db_hard_reset"
// MARK: Regram — full wipe, see rgFullWipeIfNeeded.
private let fullWipeKey = "sg_full_wipe"

private func rgDefaultDataPath() -> String? {
    guard let containerUrl = rgDataContainerURL() else {
        return nil
    }
    return (containerUrl.path as NSString).appendingPathComponent("telegram-data")
}

public func rgDBResetIfNeeded(databasePath: String, present: ((UIViewController) -> ())?) {
    guard UserDefaults.standard.bool(forKey: dbResetKey) else {
        return
    }
    NSLog("[SG.DBReset] Resetting DB with system settings")
    let alert = UIAlertController(
        title: "Metadata Reset.\nDO NOT CLOSE THE APP\nPlease wait...",
        message: nil,
        preferredStyle: .alert
    )
    present?(alert)
    do {
        let _ = try FileManager.default.removeItem(atPath: databasePath)
        NSLog("[SG.DBReset] Done. Reset completed")
        let successAlert = UIAlertController(
            title: "Metadata Reset completed",
            message: nil,
            preferredStyle: .alert
        )
        successAlert.addAction(UIAlertAction(title: "Restart App", style: .cancel) { _ in
            exit(0)
        })
        successAlert.addAction(UIAlertAction(title: "OK", style: .default))
        alert.dismiss(animated: false) {
            present?(successAlert)
        }
    } catch {
        NSLog("[SG.DBReset] ERROR. Failed to reset database: \(error)")
        let failAlert = UIAlertController(
            title: "ERROR. Failed to Reset database",
            message: "\(error)",
            preferredStyle: .alert
        )
        alert.dismiss(animated: false) {
            present?(failAlert)
        }
    }
    UserDefaults.standard.set(false, forKey: dbResetKey)
//    let semaphore = DispatchSemaphore(value: 0)
//    semaphore.wait()
}

// MARK: Regram
/// Deletes everything this build persists, and returns the names it could not remove.
public func rgEraseAllLocalData() -> [String] {
    var failures: [String] = []
    let fileManager = FileManager.default

    // 1. The data container's contents (telegram-data, shared Library/Preferences, caches).
    if let containerPath = rgDataContainerURL()?.path,
       let items = try? fileManager.contentsOfDirectory(atPath: containerPath) {
        for item in items {
            let path = (containerPath as NSString).appendingPathComponent(item)
            do {
                try fileManager.removeItem(atPath: path)
                NSLog("[SG.FullWipe] removed %@", item)
            } catch {
                NSLog("[SG.FullWipe] failed to remove %@: %@", item, "\(error)")
                failures.append(item)
            }
        }
    }

    // 2. The app's own sandbox: Documents, Library, tmp (anything not in the group container).
    for directory in [FileManager.SearchPathDirectory.documentDirectory, .libraryDirectory, .cachesDirectory] {
        guard let url = fileManager.urls(for: directory, in: .userDomainMask).first else {
            continue
        }
        if let items = try? fileManager.contentsOfDirectory(atPath: url.path) {
            for item in items {
                let _ = try? fileManager.removeItem(atPath: (url.path as NSString).appendingPathComponent(item))
            }
        }
    }
    let _ = try? fileManager.removeItem(atPath: NSTemporaryDirectory())

    // 3. Standard and group defaults — the group suite is gone with its directory, but the in-memory
    //    cache would otherwise write it straight back on exit.
    if let bundleId = Bundle.main.bundleIdentifier {
        UserDefaults.standard.removePersistentDomain(forName: bundleId)
    }
    if !rgIsSandboxOnlyBuild {
        let appGroupIdentifier = rgAppGroupIdentifier()
        UserDefaults(suiteName: appGroupIdentifier)?.removePersistentDomain(forName: appGroupIdentifier)
    }
    UserDefaults.standard.synchronize()

    // 4. Keychain items (auth keys, encryption salt) live outside the container and would let the
    //    next install decrypt any leftover data. Remove everything this app can see.
    for secClass in [kSecClassGenericPassword, kSecClassInternetPassword, kSecClassCertificate, kSecClassKey, kSecClassIdentity] {
        let query: [CFString: Any] = [kSecClass: secClass]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            NSLog("[SG.FullWipe] keychain class %@ delete status %d", "\(secClass)", status)
        }
    }

    NSLog("[SG.FullWipe] Done. failures=%@", "\(failures)")
    return failures
}

// MARK: Regram
/// A genuine factory reset, unlike `rgHardReset` which deliberately keeps accounts logged in.
///
/// Deleting the app is normally enough to start over, since `rgDataContainerURL()` keeps the data in
/// a container iOS removes with the app. This exists for the cases that does not cover: wiping
/// without uninstalling, and clearing a shared App Group container that a re-signing tool keeps
/// alive by handing the same group to everything it signs.
///
/// Wipes the container (`telegram-data`, shared defaults, caches), the app's own sandbox and the
/// keychain, so the next launch is the same as a first install. Triggered from the iOS Settings
/// toggle `sg_full_wipe`, which lives in `UserDefaults.standard` — not in the container being
/// deleted — so the flag itself survives long enough to be read and cleared.
@discardableResult
public func rgFullWipeIfNeeded(present: ((UIViewController) -> ())?, beforePresent: (() -> ())? = nil) -> Bool {
    guard UserDefaults.standard.bool(forKey: fullWipeKey) else {
        return false
    }
    UserDefaults.standard.set(false, forKey: fullWipeKey)
    beforePresent?()

    guard rgDataContainerURL() != nil else {
        NSLog("[SG.FullWipe] ERROR. Data container unavailable")
        let failAlert = UIAlertController(title: "ERROR. Full wipe failed", message: "Data container unavailable", preferredStyle: .alert)
        failAlert.addAction(UIAlertAction(title: "Close", style: .cancel) { _ in exit(0) })
        present?(failAlert)
        return true
    }

    let confirm = UIAlertController(
        title: "⚠️ Erase All Data",
        message: "This logs out every account and deletes all local data, caches and settings of this app. The app then behaves like a fresh install.\n\nContinue?",
        preferredStyle: .alert
    )
    confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
        exit(0)
    })
    confirm.addAction(UIAlertAction(title: "Erase Everything", style: .destructive) { _ in
        let progress = UIAlertController(title: "Erasing…\nDO NOT CLOSE THE APP", message: nil, preferredStyle: .alert)
        confirm.dismiss(animated: false) {
            present?(progress)
        }

        let failures = rgEraseAllLocalData()
        let done = UIAlertController(
            title: failures.isEmpty ? "All data erased" : "Erased with errors",
            message: failures.isEmpty ? "The app will now close. Open it again to start fresh." : "Could not remove: \(failures.joined(separator: ", "))",
            preferredStyle: .alert
        )
        done.addAction(UIAlertAction(title: "Close App", style: .cancel) { _ in
            exit(0)
        })
        progress.dismiss(animated: false) {
            present?(done)
        }
    })
    present?(confirm)
    return true
}

@discardableResult
public func rgHardReset(dataPath: String? = nil, present: ((UIViewController) -> ())?, beforePresent: (() -> ())? = nil) -> Bool {
    guard UserDefaults.standard.bool(forKey: dbHardResetKey) else {
        return false
    }
    UserDefaults.standard.set(false, forKey: dbHardResetKey)
    beforePresent?()
    guard let dataPath = dataPath ?? rgDefaultDataPath() else {
        NSLog("[SG.DBReset] ERROR. Reset All failed: Error 2")
        let failAlert = UIAlertController(
            title: "ERROR. Reset All failed",
            message: "Error 2",
            preferredStyle: .alert
        )
        present?(failAlert)
        return true
    }
    let startAlert = UIAlertController(
        title: "ATTENTION",
        message: "Confirm RESET ALL?",
        preferredStyle: .alert
    )
    
    startAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
        exit(0)
    })
    startAlert.addAction(UIAlertAction(title: "RESET", style: .destructive) { _ in
        let ensureAlert = UIAlertController(
            title: "⚠️ ATTENTION ⚠️",
            message: "ARE YOU SURE you want to make a RESET ALL?",
            preferredStyle: .alert
        )
        
        ensureAlert.addAction(UIAlertAction(title: "Cancel", style: .default) { _ in
            exit(0)
        })
        ensureAlert.addAction(UIAlertAction(title: "RESET NOW", style: .destructive) { _ in
            NSLog("[SG.DBReset] Reset All with system settings")
            let alert = UIAlertController(
                title: "Reset All.\nDO NOT CLOSE THE APP\nPlease wait...",
                message: nil,
                preferredStyle: .alert
            )
            ensureAlert.dismiss(animated: false) {
                present?(alert)
            }
            
            do {
                let fileManager = FileManager.default
                for metadataItem in ["db", "guard_db", "media", "spotlight"] {
                    let metadataItemPath = (dataPath as NSString).appendingPathComponent("accounts-metadata/\(metadataItem)")
                    if fileManager.fileExists(atPath: metadataItemPath) {
                        NSLog("[SG.DBReset] Trying to delete accounts-metadata/\(metadataItem)")
                        try fileManager.removeItem(atPath: metadataItemPath)
                        NSLog("[SG.DBReset] OK. Deleted accounts-metadata/\(metadataItem)")
                    }
                }
                let contents = try fileManager.contentsOfDirectory(atPath: dataPath)

                // Filter directories that match our criteria
                let accountDirectories = contents.compactMap { filename in
                    let fullPath = (dataPath as NSString).appendingPathComponent(filename)
                    
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory), isDirectory.boolValue {
                        if filename.hasPrefix("account-") {
                            return fullPath
                        }
                    }
                    return nil
                }

                NSLog("[SG.DBReset] Found \(accountDirectories.count) account dirs...")
                var deletedPostboxCount = 0
                for accountDir in accountDirectories {
                    let accountName = (accountDir as NSString).lastPathComponent
                    let postboxPath = (accountDir as NSString).appendingPathComponent("postbox")
                    
                    var isPostboxDir: ObjCBool = false
                    if fileManager.fileExists(atPath: postboxPath, isDirectory: &isPostboxDir), isPostboxDir.boolValue {
                        // Delete postbox/db
                        let dbPath = (postboxPath as NSString).appendingPathComponent("db")
                        var isDbDir: ObjCBool = false
                        if fileManager.fileExists(atPath: dbPath, isDirectory: &isDbDir), isDbDir.boolValue {
                            NSLog("[SG.DBReset] Trying to delete postbox/db in: \(accountName)")
                            try fileManager.removeItem(atPath: dbPath)
                            NSLog("[SG.DBReset] OK. Deleted postbox/db directory in: \(accountName)")
                        }
                        
                        // Delete postbox/media
                        let mediaPath = (postboxPath as NSString).appendingPathComponent("media")
                        var isMediaDir: ObjCBool = false
                        if fileManager.fileExists(atPath: mediaPath, isDirectory: &isMediaDir), isMediaDir.boolValue {
                            NSLog("[SG.DBReset] Trying to delete postbox/media in: \(accountName)")
                            try fileManager.removeItem(atPath: mediaPath)
                            NSLog("[SG.DBReset] OK. Deleted postbox/media directory in: \(accountName)")
                        }
                        
                        deletedPostboxCount += 1
                    }
                }


                NSLog("[SG.DBReset] Done. Reset All completed")
                let successAlert = UIAlertController(
                    title: "Reset All completed",
                    message: nil,
                    preferredStyle: .alert
                )
                successAlert.addAction(UIAlertAction(title: "Restart App", style: .cancel) { _ in
                    exit(0)
                })
                alert.dismiss(animated: false) {
                    present?(successAlert)
                }
            } catch {
                NSLog("[SG.DBReset] ERROR. Reset All failed: \(error)")
                let failAlert = UIAlertController(
                    title: "ERROR. Reset All failed",
                    message: "\(error)",
                    preferredStyle: .alert
                )
                alert.dismiss(animated: false) {
                    present?(failAlert)
                }
            }
        })
        ensureAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            exit(0)
        })
        
        present?(ensureAlert)
    })
             
    present?(startAlert)
    return true
}
