import Foundation

@main struct BottomBarSettingsTests {
    static func main() {
        let suite = "regram.layout.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "hideTabBar")
        defaults.set(false, forKey: "showTabNames")
        defaults.set(72, forKey: "tabBarWidthPercent")
        var settings = RGBottomBarSettings.load(from: defaults)
        assert(settings.automaticWidth && !settings.isBottomBarVisible && !settings.showLabels)
        settings.isBottomBarVisible = true
        settings.moveBottomItem(from: 0, to: 3)
        assert(settings.visibleBottomItems == [.calls, .chats, .settings, .contacts])
        settings.hide(.calls)
        assert(!settings.isVisible(.calls))
        for required in [RGBottomBarItemId.chats, .settings] {
            assert(!settings.canHide(required))
            settings.hide(required); settings.toggleHidden(required)
            assert(settings.isVisible(required))
        }
        assert(!settings.isVisible(.search) && settings.externalItem == nil)
        settings.setSearchMode(.button)
        assert(!settings.isVisible(.search))
        settings.setSearchMode(.hidden)
        settings.moveToExternal(.settings)
        assert(settings.externalItem == .settings && settings.isVisible(.settings))
        settings.isBottomBarVisible = false
        assert(settings.visibleNavigationItems.isEmpty)
        settings.isBottomBarVisible = true
        settings.automaticWidth = false
        settings.buttonWidthFillRatio = 80
        settings.save(to: defaults)
        assert(RGBottomBarSettings.load(from: defaults) == settings)
        let previous = defaults.dictionary(forKey: RGBottomBarSettings.storageKey) as! [String: String]
        var legacy = previous
        legacy.removeValue(forKey: "automaticWidth")
        legacy["hidden"] = "chats,settings,contacts,calls"
        legacy["items"] = "contacts,calls"
        legacy["alignment"] = "spaceBetween"
        defaults.set(legacy, forKey: RGBottomBarSettings.storageKey)
        let restored = RGBottomBarSettings.load(from: defaults)
        assert(restored.automaticWidth && restored.alignment == .center)
        assert(restored.isVisible(.chats) && restored.isVisible(.settings))
        assert(restored.visibleNavigationItems.count >= 2)
        let invalid = RGBottomBarSettings(bottomItems: [.calls, .calls, .search], hiddenItems: [.contacts, .settings], buttonWidthFillRatio: 200)
        assert(Set(invalid.bottomItems).count == invalid.bottomItems.count)
        assert(!invalid.bottomItems.contains(.search) && invalid.visibleBottomItems.contains(.chats) && invalid.visibleBottomItems.contains(.settings))
        assert(invalid.buttonWidthFillRatio == 100)
        let onlyRequired = RGBottomBarSettings(hiddenItems: Set(RGBottomBarItemId.allCases))
        assert(onlyRequired.visibleBottomItems == [.chats, .settings])
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 2, percent: 0) == 320)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 3, percent: 0) == 320)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 2, percent: 0, naturalItemWidths: [100, 120]) == 320)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 2, percent: 0, searchButtonWidth: 64, naturalItemWidths: [64, 90]) == 320)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 320, itemCount: 4, percent: 0, naturalItemWidths: [120, 120, 120, 120]) == 320)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 2, percent: 80, naturalItemWidths: [64, 64]) == 288)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 800, itemCount: 5, percent: 100) == 500)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 500, itemCount: 2, percent: 0) == 320)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 4, percent: 0) == 360)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 2, percent: 0, naturalItemWidths: [180, 140]) == 360)
        assert(RGDatacenterLocation.title(5) == "DC5 · Singapore")
        print("Bottom-bar checks passed: required tabs, legacy/backup recovery, automatic/manual width, centering and persistence")
    }
}
