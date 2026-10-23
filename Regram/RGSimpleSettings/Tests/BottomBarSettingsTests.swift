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
        assert(settings.isVisible(.search) && settings.externalItem == nil && !settings.visibleBottomItems.contains(.search))
        assert(settings.visibleNavigationItems == [.chats, .settings, .contacts])
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

        // Fresh installs keep search off. Legacy placements migrate into the native search control.
        assert(RGBottomBarSettings().externalItem == nil && !RGBottomBarSettings().isVisible(.search))
        assert(!RGBottomBarItemId.search.isNavigationItem)
        for mode in [RGBottomBarSearchMode.button, .bar] {
            defaults.set(["items": "chats,settings", "external": "search", "search": mode.rawValue, "hidden": "contacts,calls"], forKey: RGBottomBarSettings.storageKey)
            let migrated = RGBottomBarSettings.load(from: defaults)
            assert(migrated.externalItem == nil && migrated.visibleBottomItems == [.chats, .settings] && migrated.isVisible(.search))
            migrated.save(to: defaults)
            assert(RGBottomBarSettings.load(from: defaults) == migrated)
            let serialized = defaults.dictionary(forKey: RGBottomBarSettings.storageKey) as! [String: String]
            assert(serialized["external"] == "" && serialized["items"] == "chats,settings")
        }
        defaults.set(["items": "chats,settings", "hidden": "contacts,calls"], forKey: RGBottomBarSettings.storageKey)
        assert(!RGBottomBarSettings.load(from: defaults).isVisible(.search))
        let legacySearch = RGBottomBarSettings(bottomItems: [.search, .chats, .settings], searchMode: .button)
        assert(legacySearch.isVisible(.search) && !legacySearch.visibleBottomItems.contains(.search) && legacySearch.externalItem == nil)
        let hiddenSearch = RGBottomBarSettings(bottomItems: [.search, .chats, .settings], externalItem: .search, hiddenItems: [.search], searchMode: .button)
        assert(!hiddenSearch.isVisible(.search) && hiddenSearch.externalItem == nil)

        // Native search preserves navigation placement; it never becomes a reorderable controller tab.
        for item in RGBottomBarItemId.allCases where item.isNavigationItem {
            var layout = RGBottomBarSettings()
            layout.moveToExternal(item)
            let navigationItems = Set(layout.visibleNavigationItems)
            layout.setVisible(.search, visible: true)
            assert(layout.externalItem == item && layout.isVisible(.search) && !layout.visibleBottomItems.contains(.search))
            assert(Set(layout.visibleNavigationItems) == navigationItems)
            layout.moveToBottom(.search, at: 0)
            assert(layout.isVisible(.search) && layout.externalItem == item && !layout.visibleBottomItems.contains(.search))
            layout.topSearchVisible = false
            layout.showLabels = false
            layout.save(to: defaults)
            assert(RGBottomBarSettings.load(from: defaults) == layout)
            layout.isBottomBarVisible = false
            assert(layout.visibleBottomItems.isEmpty && layout.visibleNavigationItems.isEmpty)
            layout.isBottomBarVisible = true
            assert(layout.isVisible(.search))
            layout.toggleHidden(.search)
            assert(!layout.isVisible(.search) && layout.externalItem == item)
            layout.toggleHidden(.search)
            assert(layout.isVisible(.search) && !layout.visibleBottomItems.contains(.search))
            layout.moveToExternal(.search) // Old placement callers enable the native control, not an external tab lens.
            assert(layout.externalItem == item && layout.isVisible(.search) && !layout.visibleBottomItems.contains(.search))
            layout.setSearchMode(.bar)
            assert(layout.searchMode == .button && layout.isVisible(.search))
            layout.setSearchMode(.hidden)
            assert(!layout.isVisible(.search))
            layout.reset()
            assert(layout == RGBottomBarSettings())
        }
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 2, percent: 0) == 184)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 3, percent: 0) == 232)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 2, percent: 0, naturalItemWidths: [100, 120]) == 184)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 2, percent: 0, searchButtonWidth: 64, naturalItemWidths: [64, 90]) == 240)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 320, itemCount: 4, percent: 0, naturalItemWidths: [120, 120, 120, 120]) == 264)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 2, percent: 80, naturalItemWidths: [64, 64]) == 288)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 800, itemCount: 5, percent: 100) == 500)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 500, itemCount: 2, percent: 0) == 500.0 / 1.5 - 56)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 4, percent: 0) == 304)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 2, percent: 0, naturalItemWidths: [180, 140]) == 184)
        for containerWidth in [280.0, 320.0, 390.0, 1024.0] {
            for count in 2...4 {
                for percent: Int32 in [0, 50, 80, 100] {
                    let width = RGTabBarLayoutPolicy.width(containerWidth: containerWidth, itemCount: count, percent: percent, searchButtonWidth: 72)
                    assert(width <= min(containerWidth, RGTabBarLayoutPolicy.maximumWidth))
                    assert(width - 72 >= Double(count) * RGTabBarLayoutPolicy.minimumItemWidth + 8)
                }
            }
        }
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 2, percent: 0, searchButtonWidth: 72, searchActive: true) == 360)
        assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 2, percent: 0, searchButtonWidth: 72) < RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: 3, percent: 0, searchButtonWidth: 72))
        // Swiftgram automatic geometry, both with labels and with icon-only tabs.
        for (count, withSearch, withoutSearch) in [(2, 240.0, 184.0), (3, 288.0, 232.0), (4, 360.0, 304.0)] {
            for widths in [Array(repeating: 64.0, count: count), Array(repeating: 96.0, count: count)] {
                assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: count, percent: 0, searchButtonWidth: 72, naturalItemWidths: widths) == withSearch)
                assert(RGTabBarLayoutPolicy.width(containerWidth: 360, itemCount: count, percent: 0, naturalItemWidths: widths) == withoutSearch)
            }
            for container in [320.0, 1024.0] {
                for reserved in [0.0, 72.0] {
                    let width = RGTabBarLayoutPolicy.width(containerWidth: container, itemCount: count, percent: 0, searchButtonWidth: reserved)
                    assert(width <= min(500, container))
                    assert(width - reserved - 8 >= Double(count) * 44)
                    assert(RGTabBarLayoutPolicy.width(containerWidth: container, itemCount: count, percent: 50, searchButtonWidth: reserved, searchActive: true) == min(500, container))
                }
            }
        }
        assert(RGDatacenterLocation.title(5) == "DC5 · Singapore")
        print("Bottom-bar checks passed: opt-in native search, legacy migration and standalone navigation preservation, top search independence, required tabs, legacy/backup recovery, automatic/manual width, centering and persistence")
    }
}
