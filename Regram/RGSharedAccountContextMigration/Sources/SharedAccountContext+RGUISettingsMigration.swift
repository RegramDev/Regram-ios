// MARK: Regram
import RGLogging
import RGAppGroupIdentifier
import RGSimpleSettings
import SwiftSignalKit
import TelegramUIPreferences
import AccountContext
import Postbox
import Foundation

extension SharedAccountContextImpl {
    // MARK: Regram
    func performRGUISettingsMigrationIfNecessary() {
        if self.didPerformRGUISettingsMigration {
            return
        }
        let rgMigrationKey = "sg_migrated_sgui_settings_v1"
        if UserDefaults.standard.bool(forKey: rgMigrationKey) {
            self.didPerformRGUISettingsMigration = true
            return
        }
        guard let rgPrimary = self.rgPrimaryAccountContextForMigration() else {
            return
        }
        self.didPerformRGUISettingsMigration = true
        
        let rgPreferences: Signal<PreferencesView, NoError> = rgPrimary.account.postbox.preferencesView(keys: [ApplicationSpecificPreferencesKeys.RGUISettings])
        let _ = (rgPreferences
        |> take(1)
        |> deliverOnMainQueue).start(next: { view in
            let rgSettings: RGUISettings = view.values[ApplicationSpecificPreferencesKeys.RGUISettings]?.get(RGUISettings.self) ?? .default
            let rgDefaults = UserDefaults.standard
            let rgDomainName = rgBaseBundleIdentifier()
            let rgDomain = rgDefaults.persistentDomain(forName: rgDomainName) ?? [:]
            if rgDomain[RGSimpleSettings.Keys.hideStories.rawValue] == nil {
                RGSimpleSettings.shared.hideStories = rgSettings.hideStories
                RGLogger.shared.log("SGSimpleSettings", "Migrated hideStories: \(rgSettings.hideStories)")
            }
            if rgDomain[RGSimpleSettings.Keys.warnOnStoriesOpen.rawValue] == nil {
                RGSimpleSettings.shared.warnOnStoriesOpen = rgSettings.warnOnStoriesOpen
                RGLogger.shared.log("SGSimpleSettings", "Migrated warnOnStoriesOpen: \(rgSettings.warnOnStoriesOpen)")
            }
            if rgDomain[RGSimpleSettings.Keys.showProfileId.rawValue] == nil {
                RGSimpleSettings.shared.showProfileId = rgSettings.showProfileId
                RGLogger.shared.log("SGSimpleSettings", "Migrated showProfileId: \(rgSettings.showProfileId)")
            }
            if rgDomain[RGSimpleSettings.Keys.sendWithReturnKey.rawValue] == nil {
                RGSimpleSettings.shared.sendWithReturnKey = rgSettings.sendWithReturnKey
                RGLogger.shared.log("SGSimpleSettings", "Migrated sendWithReturnKey: \(rgSettings.sendWithReturnKey)")
            }
            rgDefaults.set(true, forKey: rgMigrationKey)
        })
    }
}
