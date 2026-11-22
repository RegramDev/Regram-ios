import Foundation
import SwiftSignalKit

@main enum GroupMemberUIFlowTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { fatalError(message) }
    }
    static func settle() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.015)) }
    static func user(_ id: Int64, _ title: String) -> EnginePeer {
        .user(TelegramUser(id: .init(id), accessHash: nil, firstName: title, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil))
    }
    static func add(_ controller: ItemListController) {
        guard let action = controller.items.compactMap({ $0 as? ItemListActionItem }).first else { fatalError("Missing add action") }
        action.action(); settle()
    }
    static func rows(_ controller: ItemListController) -> [ItemListPeerItem] { controller.items.compactMap { $0 as? ItemListPeerItem } }
    static func main() {
        let settings = RGSimpleSettings.shared
        let context = AccountContext(11)
        let me = user(11, "Self"), alice = user(31, "Alice"), bob = user(32, "Bob")
        let group = EnginePeer.legacyGroup(TestGroup(id: .init(21), title: "Group One"))
        let supergroup = EnginePeer.channel(TestChannel(id: .init(22), title: "Group Two", info: .group))
        let channel = EnginePeer.channel(TestChannel(id: .init(23), title: "Broadcast", info: .broadcast))
        for peer in [me, alice, bob, group, supergroup, channel] { context.engine.data.peers[peer.id] = peer }
        let navigation = NavigationController()
        let root = rgGroupMemberSettingsController(context: context, mode: .reminders) as! ItemListController
        navigation.pushViewController(root); settle()
        expect(root.backTitle == "Back", "The settings page must retain a native back action")
        expect(rows(root).isEmpty, "No selected members must mean an empty configured-groups list")

        add(root)
        guard let picker = context.sharedContext.lastGroupPicker else { fatalError("Missing group picker") }
        expect(picker.navigationController === navigation && navigation.viewControllers.last === picker, "Group selection must be pushed into Telegram navigation; a bare window presentation has no working back/close path")
        expect(root.presented.isEmpty, "The group picker must not be mounted as a root-window overlay")
        expect(!picker.params.hasContactSelector, "A group-only picker must not expose the contacts tab")
        picker.peerSelected?(alice, nil); settle()
        expect(navigation.viewControllers.last === picker && settings.groupNotificationSenders.isEmpty, "Selecting a private user must not create a fake group configuration")
        picker.peerSelected?(channel, nil); settle()
        expect(navigation.viewControllers.last === picker, "Broadcast channels must not become group reminder targets")
        picker.dismiss(); settle()
        expect(navigation.viewControllers.count == 1 && navigation.viewControllers.last === root, "Cancelling group selection must return to the settings page")
        expect(settings.groupNotificationSenders.isEmpty, "Cancelling must not create preferences")

        add(root)
        guard let selectedGroupPicker = context.sharedContext.lastGroupPicker else { fatalError("Missing second group picker") }
        selectedGroupPicker.peerSelected?(group, nil); settle()
        guard let members = navigation.viewControllers.last as? ItemListController else { fatalError("Missing group member settings") }
        expect(navigation.viewControllers.count == 2 && navigation.viewControllers.last !== selectedGroupPicker, "Choosing a group must replace the picker, leaving one back step to the groups list")
        expect(members.title == .textWithSubtitle("GroupMembers.Reminders.Title", "Group One"), "Member settings must identify the current group")
        expect(members.backTitle == "Back", "Member settings must retain their native back action")
        expect(settings.groupNotificationSenders.isEmpty, "Choosing a group without a member must not turn alerts on")

        add(members)
        guard let cancelled = context.sharedContext.lastMemberPicker else { fatalError("Missing member picker") }
        expect(cancelled.navigationController === navigation && navigation.viewControllers.count == 3, "Member selection also needs the native navigation container")
        cancelled.dismiss(); settle()
        expect(navigation.viewControllers.last === members && settings.groupNotificationSenders.isEmpty, "Cancelling member selection must restore the member list without changes")

        add(members)
        guard let memberPicker = context.sharedContext.lastMemberPicker else { fatalError("Missing member picker") }
        memberPicker.params.openPeer(me, nil); settle()
        expect(navigation.viewControllers.last === memberPicker && settings.groupNotificationSenders.isEmpty, "Choosing yourself must not add a member or dismiss the picker")
        memberPicker.params.openPeer(alice, nil); settle()
        expect(navigation.viewControllers.last === members && navigation.viewControllers.count == 2, "Selecting a member must close only the picker")
        expect(settings.groupNotificationSenders.contains(accountId: 11, groupId: 21, senderId: 31), "The selected member must be saved under the current account and group")
        expect(rows(members).count == 1 && rows(members)[0].text.string == "GroupMembers.Reminders.Enabled", "A newly selected member must visibly show its enabled state")
        expect(rows(root).count == 1 && rows(root)[0].text.string == "1 members", "The groups list must show the actual saved member count")

        add(members)
        guard let repeated = context.sharedContext.lastMemberPicker else { fatalError("Missing repeated member picker") }
        let exclusions = repeated.params.filters.flatMap { filter -> [EnginePeer.Id] in if case let .exclude(ids) = filter { return ids }; return [] }
        expect(exclusions.contains(me.id) && exclusions.contains(alice.id), "The member picker must exclude self and already selected members")
        repeated.dismiss(); settle()
        settings.blockedPeerIds = [31]; settings.changed(); settle()
        expect(rows(members)[0].text.string == "GroupMembers.Reminders.Suppressed", "A blocked sender must not be misleadingly displayed as an effective alert")
        settings.blockedPeerIds = []; settings.changed(); settle()
        expect(rows(members)[0].text.string == "GroupMembers.Reminders.Enabled", "Unhiding the sender must refresh its visible reminder state")
        settings.setGroupMemberReminder(accountId: 11, groupId: 21, senderId: 32, enabled: true); settle()
        expect(rows(root)[0].text.string == "2 members", "A count-only change must update an otherwise identical group row")
        let aliceRow = rows(members).first { $0.peer.id == alice.id }!
        aliceRow.removePeer(alice.id); settle()
        expect(rows(members).count == 1 && rows(members)[0].peer.id == bob.id, "Turning off a member must remove the same member from the enabled list")
        expect(rows(root)[0].text.string == "1 members", "Removing one member must refresh the group count")

        // Simulate a preference change whose notification was missed while the page was covered.
        settings.groupNotificationSenders.set(accountId: 11, groupId: 21, senderId: 32, selected: false)
        members.dismiss(); settle()
        expect(navigation.viewControllers.last === root && rows(root).isEmpty, "Returning must reread saved state even if a change notification was missed")

        let direct = rgGroupMemberSettingsController(context: context, groupId: supergroup.id, mode: .reminders) as! ItemListController
        navigation.pushViewController(direct); settle()
        expect(direct.title == .textWithSubtitle("GroupMembers.Reminders.Title", "Group Two"), "The group-profile entry must show the same scoped state and group name")
        add(direct)
        context.sharedContext.lastMemberPicker!.params.openPeer(alice, nil); settle()
        expect(settings.groupNotificationSenders.contains(accountId: 11, groupId: 22, senderId: 31), "Supergroup selection must keep its own group scope")
        expect(!settings.groupNotificationSenders.contains(accountId: 11, groupId: 21, senderId: 31), "A new group must not restore removed selections in another group")
        direct.dismiss(); settle()
        expect(rows(root).count == 1 && rows(root)[0].peer.id == supergroup.id, "Returning from the group-profile flow must update the same global list")

        let other = AccountContext(12)
        other.engine.data.peers = context.engine.data.peers
        let otherRoot = rgGroupMemberSettingsController(context: other, mode: .reminders) as! ItemListController
        let otherNavigation = NavigationController(); otherNavigation.pushViewController(otherRoot); settle()
        expect(rows(otherRoot).isEmpty, "Another account must not inherit this account's configured groups")

        let hidden = rgGroupMemberSettingsController(context: context, groupId: supergroup.id, mode: .hidden) as! ItemListController
        navigation.pushViewController(hidden); settle()
        expect(rows(hidden).isEmpty, "The hidden-member list must stay independent from reminders")
        add(hidden)
        context.sharedContext.lastMemberPicker!.params.openPeer(alice, nil); settle()
        expect(rows(hidden).count == 1 && rows(hidden)[0].text.string == "GroupMembers.Hidden.Status", "The shared hidden-member flow must retain its scoped status")
        expect(settings.groupNotificationSenders.contains(accountId: 11, groupId: 22, senderId: 31), "Hiding a sender must not erase its independent selected reminder")
        hidden.dismiss(); settle()
        context.engine.data.deferResponses = true
        settings.setGroupMemberReminder(accountId: 11, groupId: 22, senderId: 32, enabled: true); settle()
        expect(rows(root)[0].text.string == "1 members", "An in-flight peer lookup must not mix previous rows with newer preference counts")
        context.engine.data.completeResponses(); settle()
        expect(rows(root)[0].text.string == "2 members", "Peer rows and saved counts must arrive together as one snapshot")
        context.engine.data.deferResponses = false
        rows(root)[0].removePeer(supergroup.id); settle()
        expect(rows(root).isEmpty && settings.groupHiddenSenders.contains(accountId: 11, groupId: 22, senderId: 31), "Removing a reminder group must leave the independent hidden settings intact")
        expect(root.presented.isEmpty && members.presented.isEmpty && direct.presented.isEmpty && hidden.presented.isEmpty, "Every picker route must use navigation instead of a bare window overlay")
        print("Group member UI flow checks passed: \(checks) assertions; real SwiftSignalKit, production picker callbacks, back/cancel/replace, scoped titles, live counts, hidden status and return refresh")
    }
}
