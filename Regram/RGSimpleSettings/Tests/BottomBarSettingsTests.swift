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
        assert(!settings.isBottomBarVisible && !settings.showLabels && settings.buttonWidthFillRatio == 72)
        settings.isBottomBarVisible = true
        settings.moveBottomItem(from: 0, to: 3)
        assert(settings.visibleBottomItems == [.calls, .chats, .settings, .contacts])
        settings.hide(.calls)
        assert(!settings.isVisible(.calls))
        settings.hide(.chats)
        assert(settings.isVisible(.chats))
        settings.setSearchMode(.hidden)
        settings.moveToExternal(.settings)
        assert(settings.externalItem == .settings && !settings.visibleBottomItems.contains(.settings))
        settings.alignment = .center
        settings.save(to: defaults)
        assert(RGBottomBarSettings.load(from: defaults) == settings)
        settings.setSearchMode(.button)
        assert(settings.externalItem == .search && settings.isVisible(.settings))
        let invalid = RGBottomBarSettings(bottomItems: [.calls, .calls, .search], hiddenItems: [.contacts, .settings], buttonWidthFillRatio: 200)
        assert(Set(invalid.bottomItems).count == invalid.bottomItems.count)
        assert(!invalid.bottomItems.contains(.search) && invalid.visibleBottomItems.contains(.chats))
        assert(invalid.buttonWidthFillRatio == 100)
        var empty = RGBottomBarSettings(hiddenItems: [.contacts, .calls, .chats, .settings])
        assert(empty.showsOnlySearchButton)
        empty.setSearchMode(.bar)
        empty.save(to: defaults)
        assert(RGBottomBarSettings.load(from: defaults).visibleBottomItems.isEmpty)
        assert(RGDatacenterLocation.title(5) == "DC5 · Singapore")
        assert(RGDatacenterLocation.title(99) == "DC99")
        print("Bottom-bar checks passed: legacy migration, ordering, visibility, navigation protection, external slot, bounds and persistence")
    }
}
