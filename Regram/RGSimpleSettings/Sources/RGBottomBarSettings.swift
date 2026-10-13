// MARK: Regram — layout adapted from NextAlone/Nagram-iOS (96ae08c), under the repository GPL license.
import Foundation

public enum RGBottomBarItemId: String, CaseIterable, Hashable {
    case contacts
    case calls
    case chats
    case settings
    case search

    public var isNavigationItem: Bool {
        switch self {
        case .contacts, .calls, .chats, .settings:
            return true
        case .search:
            return false
        }
    }
}

public enum RGBottomBarWidthMode: String {
    case full
    case adaptive
}

public enum RGBottomBarSlotMode: String {
    case visibleOnly
    case preserveHidden
}

public enum RGBottomBarAlignment: String {
    case spaceBetween
    case leftCenter
    case center = "overallCenter"

    init?(storedValue: String) {
        switch storedValue {
        case "left":
            self = .spaceBetween
        case "center":
            self = .leftCenter
        default:
            self.init(rawValue: storedValue)
        }
    }
}

public enum RGBottomBarSearchMode: String {
    case button
    case bar
    case hidden
}

public struct RGBottomBarSettings: Equatable {
    public static let defaultBottomItems: [RGBottomBarItemId] = [.contacts, .calls, .chats, .settings]
    public static let minimumVisibleNonSearchBottomItems = 2

    public var automaticWidth: Bool
    public var isBottomBarVisible: Bool
    public var bottomItems: [RGBottomBarItemId]
    public var externalItem: RGBottomBarItemId?
    public var hiddenItems: Set<RGBottomBarItemId>
    public var topSearchVisible: Bool
    public var showLabels: Bool
    public var widthMode: RGBottomBarWidthMode
    public var slotMode: RGBottomBarSlotMode
    public var buttonWidthFillRatio: Int32
    public var alignment: RGBottomBarAlignment
    public var searchMode: RGBottomBarSearchMode

    public init(
        automaticWidth: Bool = true,
        isBottomBarVisible: Bool = true,
        bottomItems: [RGBottomBarItemId] = RGBottomBarSettings.defaultBottomItems,
        externalItem: RGBottomBarItemId? = .search,
        hiddenItems: Set<RGBottomBarItemId> = [],
        topSearchVisible: Bool = true,
        showLabels: Bool = true,
        widthMode: RGBottomBarWidthMode = .full,
        slotMode: RGBottomBarSlotMode = .visibleOnly,
        buttonWidthFillRatio: Int32 = 100,
        alignment: RGBottomBarAlignment = .center,
        searchMode: RGBottomBarSearchMode = .button
    ) {
        self.automaticWidth = automaticWidth
        self.isBottomBarVisible = isBottomBarVisible
        self.bottomItems = bottomItems
        self.externalItem = externalItem
        self.hiddenItems = hiddenItems
        self.topSearchVisible = topSearchVisible
        self.showLabels = showLabels
        self.widthMode = widthMode
        self.slotMode = slotMode
        self.buttonWidthFillRatio = buttonWidthFillRatio
        self.alignment = alignment
        self.searchMode = searchMode
        self.normalize()
    }

    public var visibleBottomItems: [RGBottomBarItemId] {
        guard self.isBottomBarVisible else {
            return []
        }
        return self.activeBottomItems
    }

    public var visibleNavigationItems: [RGBottomBarItemId] {
        var result = self.visibleBottomItems.filter(\.isNavigationItem)
        if let externalItem = self.externalItem, externalItem.isNavigationItem, !self.hiddenItems.contains(externalItem) {
            result.append(externalItem)
        }
        return result
    }

    /// The bar is reduced to the standalone search button: no bottom items and no search bar.
    public var showsOnlySearchButton: Bool {
        return self.isBottomBarVisible && self.activeBottomItems.isEmpty && self.externalItem == .search && self.searchMode == .button
    }

    public func isVisible(_ item: RGBottomBarItemId) -> Bool {
        if item == .search {
            return self.searchMode != .hidden && !self.hiddenItems.contains(.search)
        }
        if self.hiddenItems.contains(item) {
            return false
        }
        return self.bottomItems.contains(item) || self.externalItem == item
    }

    public var hiddenOrAvailableItems: [RGBottomBarItemId] {
        let hiddenItems = RGBottomBarItemId.allCases.filter { self.hiddenItems.contains($0) }
        let availableItems = RGBottomBarItemId.allCases.filter { item in
            !self.hiddenItems.contains(item) && !self.isVisible(item)
        }
        return hiddenItems + availableItems
    }

    public func canHide(_ item: RGBottomBarItemId) -> Bool {
        return item != .chats && item != .settings
    }

    public mutating func toggleHidden(_ item: RGBottomBarItemId) {
        if item == .search {
            if self.hiddenItems.contains(.search) {
                self.hiddenItems.remove(.search)
                self.searchMode = .button
                self.externalItem = .search
            } else {
                self.hiddenItems.insert(.search)
                self.searchMode = .hidden
                if self.externalItem == .search {
                    self.externalItem = nil
                }
            }
            self.bottomItems.removeAll(where: { $0 == .search })
            self.normalize()
            return
        }
        if self.hiddenItems.contains(item) {
            self.hiddenItems.remove(item)
            if self.externalItem != item && !self.bottomItems.contains(item) {
                self.bottomItems.append(item)
            }
        } else {
            self.hide(item)
            return
        }
        self.normalize()
    }

    public mutating func hide(_ item: RGBottomBarItemId) {
        guard self.canHide(item) else {
            return
        }
        if !self.hiddenItems.contains(item) {
            self.hiddenItems.insert(item)
        }
        if item == .search {
            self.searchMode = .hidden
        }
        self.bottomItems.removeAll(where: { $0 == item })
        if self.externalItem == item {
            self.externalItem = nil
        }
        self.normalize()
    }

    public mutating func show(_ item: RGBottomBarItemId) {
        if item == .search {
            self.hiddenItems.remove(.search)
            if self.searchMode == .hidden {
                self.searchMode = .button
            }
            self.normalize()
            return
        }
        self.hiddenItems.remove(item)
        if self.externalItem != item && !self.bottomItems.contains(item) {
            self.bottomItems.append(item)
        }
        self.normalize()
    }

    public mutating func setVisible(_ item: RGBottomBarItemId, visible: Bool) {
        if visible {
            self.show(item)
        } else {
            self.hide(item)
        }
    }

    public mutating func moveBottomItem(from sourceIndex: Int, to targetIndex: Int) {
        guard self.bottomItems.indices.contains(sourceIndex) else {
            return
        }
        let item = self.bottomItems.remove(at: sourceIndex)
        let index = max(0, min(targetIndex, self.bottomItems.count))
        self.bottomItems.insert(item, at: index)
        self.normalize()
    }

    public mutating func moveToExternal(_ item: RGBottomBarItemId) {
        if item == .search {
            self.hiddenItems.remove(.search)
            self.searchMode = .button
            self.bottomItems.removeAll(where: { $0 == .search })
            self.externalItem = .search
            self.normalize()
            return
        }
        self.hiddenItems.remove(item)
        let replacementIndex = self.bottomItems.firstIndex(of: item) ?? self.bottomItems.count
        self.bottomItems.removeAll(where: { $0 == item })
        if let previous = self.externalItem, previous != item, !self.hiddenItems.contains(previous) {
            let index = max(0, min(replacementIndex, self.bottomItems.count))
            self.bottomItems.insert(previous, at: index)
        }
        self.externalItem = item
        self.normalize()
    }

    public mutating func moveToBottom(_ item: RGBottomBarItemId, at targetIndex: Int) {
        if item == .search {
            self.hiddenItems.remove(.search)
            self.searchMode = .button
            self.bottomItems.removeAll(where: { $0 == .search })
            self.externalItem = .search
            self.normalize()
            return
        }
        self.hiddenItems.remove(item)
        if self.externalItem == item {
            self.externalItem = nil
        }
        self.bottomItems.removeAll(where: { $0 == item })
        let index = max(0, min(targetIndex, self.bottomItems.count))
        self.bottomItems.insert(item, at: index)
        self.normalize()
    }

    public mutating func setSearchMode(_ mode: RGBottomBarSearchMode) {
        self.searchMode = mode
        if mode == .hidden {
            self.hiddenItems.insert(.search)
        } else {
            self.hiddenItems.remove(.search)
        }
        self.normalize()
    }

    public mutating func reset() {
        self = RGBottomBarSettings()
    }

    private mutating func normalize() {
        // Required tabs are restored even in old backups or externally modified preferences.
        self.hiddenItems.subtract([.chats, .settings])
        self.alignment = .center
        if self.searchMode == .bar { self.searchMode = .button }

        self.bottomItems.removeAll(where: { $0 == .search })

        if self.searchMode == .hidden || self.hiddenItems.contains(.search) {
            self.searchMode = .hidden
            self.hiddenItems.insert(.search)
            if self.externalItem == .search {
                self.externalItem = nil
            }
        } else {
            if self.searchMode != .bar {
                self.searchMode = .button
            }
            self.hiddenItems.remove(.search)
            if let externalItem = self.externalItem, externalItem != .search, !self.hiddenItems.contains(externalItem), !self.bottomItems.contains(externalItem) {
                self.bottomItems.append(externalItem)
            }
            self.externalItem = self.searchMode == .bar ? nil : .search
        }

        var seen = Set<RGBottomBarItemId>()
        self.bottomItems = self.bottomItems.compactMap { item in
            guard !seen.contains(item), !self.hiddenItems.contains(item), self.externalItem != item else {
                return nil
            }
            seen.insert(item)
            return item
        }

        if let externalItem = self.externalItem {
            if self.hiddenItems.contains(externalItem) {
                self.externalItem = nil
            } else {
                seen.insert(externalItem)
            }
        }

        self.hiddenItems = self.hiddenItems.filter { RGBottomBarItemId.allCases.contains($0) }
        for item in self.hiddenItems {
            seen.insert(item)
        }

        for item in RGBottomBarItemId.allCases where !seen.contains(item) && item != .search {
            self.bottomItems.append(item)
            seen.insert(item)
        }
        self.buttonWidthFillRatio = max(0, min(100, self.buttonWidthFillRatio))
    }

    private var activeBottomItems: [RGBottomBarItemId] {
        return self.bottomItems.filter { item in
            return item != .search && !self.hiddenItems.contains(item) && self.externalItem != item
        }
    }
}

public extension RGBottomBarSettings {
    static let storageKey = "bottomBarLayout"

    static func load(from defaults: UserDefaults = .standard) -> RGBottomBarSettings {
        guard let values = defaults.dictionary(forKey: storageKey) as? [String: String] else {
            return RGBottomBarSettings(
                isBottomBarVisible: !defaults.bool(forKey: "hideTabBar"),
                showLabels: defaults.object(forKey: "showTabNames") as? Bool ?? true,
                buttonWidthFillRatio: (defaults.object(forKey: "tabBarWidthPercent") as? NSNumber)?.int32Value ?? 100
            )
        }
        return RGBottomBarSettings(
            automaticWidth: values["automaticWidth"] != "false",
            isBottomBarVisible: values["visible"] != "false",
            bottomItems: (values["items"] ?? "").split(separator: ",").compactMap { RGBottomBarItemId(rawValue: String($0)) },
            externalItem: values["external"].flatMap(RGBottomBarItemId.init(rawValue:)),
            hiddenItems: Set((values["hidden"] ?? "").split(separator: ",").compactMap { RGBottomBarItemId(rawValue: String($0)) }),
            topSearchVisible: values["topSearch"] != "false",
            showLabels: values["labels"] != "false",
            widthMode: values["width"].flatMap(RGBottomBarWidthMode.init(rawValue:)) ?? .full,
            slotMode: values["slots"].flatMap(RGBottomBarSlotMode.init(rawValue:)) ?? .visibleOnly,
            buttonWidthFillRatio: values["fill"].flatMap(Int32.init) ?? 100,
            alignment: values["alignment"].flatMap(RGBottomBarAlignment.init(rawValue:)) ?? .center,
            searchMode: values["search"].flatMap(RGBottomBarSearchMode.init(rawValue:)) ?? .button
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        var value = self
        value.normalize()
        defaults.set([
            "automaticWidth": String(value.automaticWidth), "visible": String(value.isBottomBarVisible), "items": value.bottomItems.map(\.rawValue).joined(separator: ","),
            "external": value.externalItem?.rawValue ?? "", "hidden": RGBottomBarItemId.allCases.filter { value.hiddenItems.contains($0) }.map(\.rawValue).joined(separator: ","),
            "topSearch": String(value.topSearchVisible), "labels": String(value.showLabels),
            "width": value.widthMode.rawValue, "slots": value.slotMode.rawValue, "fill": String(value.buttonWidthFillRatio),
            "alignment": value.alignment.rawValue, "search": value.searchMode.rawValue
        ], forKey: Self.storageKey)
    }
}
