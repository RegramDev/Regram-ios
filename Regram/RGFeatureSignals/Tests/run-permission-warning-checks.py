#!/usr/bin/env python3
"""Exercise production permission-badge gates and signals with isolated preferences."""
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap

ROOT = Path(__file__).resolve().parents[3]
PEER_INFO = ROOT / 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources'


def between(source, start, end):
    return source[source.index(start):source.index(end, source.index(start))].strip()


screen = (PEER_INFO / 'PeerInfoScreen.swift').read_text()
data = (PEER_INFO / 'PeerInfoData.swift').read_text()
items = (PEER_INFO / 'PeerInfoSettingsItems.swift').read_text()
access = (ROOT / 'submodules/AccountContext/Sources/AccountContext.swift').read_text()
device = (ROOT / 'submodules/DeviceAccess/Sources/DeviceAccess.swift').read_text()
features = (ROOT / 'Regram/RGSimpleSettings/Sources/RGChatFeatures.swift').read_text()
signals = (ROOT / 'Regram/RGFeatureSignals/Sources/RGFeatureSignals.swift').read_text()

# Keep the actual combination, tuple unpacking and model arguments. Only external
# account/presentation inputs are replaced; the warning gates remain unchanged.
tab = between(screen, 'let tabBarItem: Signal<', 'self.tabBarItemDisposable =')
tab = tab.replace('self.context.sharedContext.presentationData', '.single(PresentationData())')
tab = tab.replace('context.engine.notices.getServerProvidedSuggestions()', 'suggestions.get()')
row_inputs = re.search(r'combineLatest\(notificationExceptions,.*\),', data)[0][:-1]
row_unpack = re.search(r'let \(notificationExceptions,.* = notifications', data)[0]
model_args = between(data, 'notificationAuthorizationStatus: notificationsAuthorizationStatus,', 'notificationExceptions: notificationExceptions,')
model_args = re.sub(r',\s*(?://[^\n]*)?\s*$', '\n', model_args)
row_gate = between(items, 'let notificationsWarning: Bool', 'items[.advanced]!.append')
contacts = (ROOT / 'submodules/ContactListUI/Sources/ContactsController.swift').read_text()
contacts_gate = re.search(r'tabBarItem.badgeValue = (.*)', contacts)[1]

fixture = '''
import Foundation
import SwiftSignalKit
ACCESS
WARNING
PREFERENCES
BOOL_SIGNAL

let suite = "app.regram.permission-warning-tests." + UUID().uuidString
let testDefaults = UserDefaults(suiteName: suite)!
// Adapters for unrelated settings keys and the message-presentation notification.
final class RGSimpleSettings {
    enum Keys: String, CaseIterable { case unrelated }
    static let featureMessagePresentationDidChange = Notification.Name("unused")
    static let shareSettingsDidChange = Notification.Name("share-settings")
    HIDE_SETTING
}
struct UIImage {}
struct PresentationData {
    struct Strings { let Settings_Title = "Settings" }
    struct DateTimeFormat { let decimalSeparator = "." }
    let strings = Strings(), dateTimeFormat = DateTimeFormat(), reduceMotion = false
}
enum Suggestion { case validatePhoneNumber, validatePassword }
func compactNumericCountString(_ count: Int, decimalSeparator: String) -> String { String(count) }
struct Settings {
    let notificationAuthorizationStatus: AccessType
    let notificationWarningSuppressed: Bool
    let hidePermissionWarnings: Bool
}
struct ScreenData { let globalSettings: Settings? }
func rowWarning(_ settings: Settings?) -> Bool {
    let data = ScreenData(globalSettings: settings)
    ROW_GATE
    return notificationsWarning
}
func contactBadge(_ status: AccessType, _ suppressed: Bool, _ hidePermissionWarnings: Bool) -> String? {
    return CONTACTS_GATE
}
func observeRows(_ notificationsAuthorizationStatus: ValuePromise<AccessType>, _ notificationsWarningSuppressed: ValuePromise<Bool>) -> Signal<Settings, NoError> {
    let notificationExceptions: Signal<Int?, NoError> = .single(nil)
    return ROW_INPUTS
    |> map { notifications -> Settings in
        ROW_UNPACK
        _ = notificationExceptions
        return Settings(
            MODEL_ARGS
        )
    }
}
func observeTab(_ notificationsAuthorizationStatus: ValuePromise<AccessType>, _ notificationsWarningSuppressed: ValuePromise<Bool>, _ suggestions: ValuePromise<Set<Suggestion>>, _ unread: ValuePromise<Int32>) -> Signal<String?, NoError> {
    let hidePermissionWarnings = rgFeatureBoolSignal("features.hideTabBarPermissionWarnings", defaultValue: false)
    let icon: UIImage? = nil
    let accountTabBarAvatar: Signal<(UIImage, UIImage)?, NoError> = .single(nil)
    let accountTabBarAvatarBadge = unread.get()
    TAB
    return tabBarItem |> map { $0.3 }
}
@main enum Tests {
    static func main() {
        defer { testDefaults.removePersistentDomain(forName: suite) }
        let settings = RGSimpleSettings()
        let statuses: [AccessType] = [.notDetermined, .allowed, .denied, .restricted, .unreachable, .limited]
        var scenarios = 0
        for status in statuses { for suppressed in [false, true] {
            for reminders: Set<Suggestion> in [[], [.validatePhoneNumber], [.validatePassword], [.validatePhoneNumber, .validatePassword]] {
                for unread: Int32 in [0, 7] {
                    settings.hideTabBarPermissionWarnings = false
                    let authorization = ValuePromise<AccessType>(status)
                    let suppression = ValuePromise<Bool>(suppressed)
                    let suggestions = ValuePromise<Set<Suggestion>>(reminders)
                    let unreadCount = ValuePromise<Int32>(unread)
                    var badges: [String?] = [], rows: [Settings] = []
                    let tab = observeTab(authorization, suppression, suggestions, unreadCount).start(next: { badges.append($0) })
                    let row = observeRows(authorization, suppression).start(next: { rows.append($0) })
                    for hidden in [false, true, false, true] {
                        settings.hideTabBarPermissionWarnings = hidden
                        let warning = !hidden && shouldDisplayNotificationsPermissionWarning(status: status, suppressed: suppressed)
                        let expectedBadge = warning || !reminders.isEmpty ? "!" : unread > 0 ? String(unread) : nil
                        precondition(!badges.isEmpty && badges.last! == expectedBadge, "Settings tab must honor the override and preserve other reminders/unread counts")
                        precondition(!rows.isEmpty && rowWarning(rows.last!) == warning, "Notification row must update without reopening settings")
                        let expectedContact = ![AccessType.allowed, .limited].contains(status) && !suppressed && !hidden ? "!" : nil
                        precondition(contactBadge(status, suppressed, hidden) == expectedContact)
                        precondition(rows.last!.notificationAuthorizationStatus == status, "Hiding a badge must preserve actual authorization status")
                        scenarios += 1
                    }
                    // Subscribe with the preference already enabled, as after a cold start.
                    var initial: String??
                    let cold = observeTab(authorization, suppression, suggestions, unreadCount).start(next: { initial = .some($0) })
                    let expectedInitial = !reminders.isEmpty ? "!" : unread > 0 ? String(unread) : nil
                    precondition(initial != nil && initial! == expectedInitial)
                    cold.dispose(); tab.dispose(); row.dispose()
                }
            }
        }}
        precondition(!rowWarning(nil))
        print("Permission warning checks passed: \\(scenarios) scenarios, all access states, live toggles, saved preference, contacts, account reminders and unread counts.")
    }
}
'''
replacements = {
    'ACCESS': between(access, 'public enum AccessType {', 'public enum TelegramAppBuildType'),
    'WARNING': between(device, 'public func shouldDisplayNotificationsPermissionWarning(', '// A single shared probe'),
    'PREFERENCES': between(features, 'public final class RGFeaturePreferences {', 'public enum RGFeatureChatListSwipeAction'),
    'BOOL_SIGNAL': between(signals, 'public func rgFeatureBoolSignal(', 'public func rgFeatureStringSignal('),
    'HIDE_SETTING': between(features, 'var hideTabBarPermissionWarnings: Bool {', 'var keepNewChatsVisibleAtTop:'),
    'TAB': tab, 'ROW_INPUTS': row_inputs, 'ROW_UNPACK': row_unpack,
    'MODEL_ARGS': model_args, 'ROW_GATE': row_gate, 'CONTACTS_GATE': contacts_gate,
}
for key, value in replacements.items():
    fixture = fixture.replace(key, textwrap.dedent(value))
fixture = fixture.replace('UserDefaults.standard', 'testDefaults')

with tempfile.TemporaryDirectory(prefix='regram-permission-warning-checks-') as temporary:
    work = Path(temporary)
    signal_sources = sorted((ROOT / 'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'))
    signal_sources += sorted((ROOT / 'Regram/RGSwiftSignalKit/Sources').glob('*.swift'))
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-emit-library', '-emit-module',
                    '-module-name', 'SwiftSignalKit', *map(str, signal_sources),
                    '-emit-module-path', str(work / 'SwiftSignalKit.swiftmodule'),
                    '-o', str(work / 'libSwiftSignalKit.dylib')], check=True)
    (work / 'Tests.swift').write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-parse-as-library',
                    '-I', str(work), '-L', str(work), '-lSwiftSignalKit',
                    '-Xlinker', '-rpath', '-Xlinker', str(work),
                    str(work / 'Tests.swift'), '-o', str(work / 'tests')], check=True)
    subprocess.run([str(work / 'tests')], check=True, timeout=30)
