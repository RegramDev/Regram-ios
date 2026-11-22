import Display
import ItemListUI

/// Combines settings from different owners without duplicating preference writes or routing.
/// Every row keeps its own arguments, setting tag and copyable deep link.
public struct RGSettingsBoundEntry: ItemListNodeEntry {
    public struct Id: Hashable {
        let scope: String
        let value: AnyHashable
    }

    public let stableId: Id
    public let section: ItemListSectionId
    public var tag: ItemListItemTag? { self.entry.tag }
    private let entry: ItemListNodeAnyEntry
    private let arguments: Any
    private var order: Int

    public init<T: ItemListNodeEntry>(_ entry: T, arguments: Any, scope: String, order: Int) {
        self.stableId = Id(scope: scope, value: entry.anyId)
        self.section = entry.section
        self.entry = entry
        self.arguments = arguments
        self.order = order
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stableId == rhs.stableId && lhs.order == rhs.order && lhs.entry.isEqual(rhs.entry)
    }

    public func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        self.entry.item(presentationData: presentationData, arguments: self.arguments)
    }

    public func withOrder(_ order: Int) -> Self {
        var result = self
        result.order = order
        return result
    }
}
