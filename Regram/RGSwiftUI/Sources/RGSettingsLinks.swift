// MARK: Regram — hosted settings copy stable links and scroll to the requested control.
import Foundation
import RGStrings
import SwiftUI
import UIKit

private struct RGSettingsPageKey: EnvironmentKey { static let defaultValue = "" }
private struct RGSettingsFocusKey: EnvironmentKey { static let defaultValue: String? = nil }
private extension EnvironmentValues {
    var rgSettingsPage: String { get { self[RGSettingsPageKey.self] } set { self[RGSettingsPageKey.self] = newValue } }
    var rgSettingsFocus: String? { get { self[RGSettingsFocusKey.self] } set { self[RGSettingsFocusKey.self] = newValue } }
}
private struct RGSettingLinkModifier: ViewModifier {
    let item: String
    @Environment(\.rgSettingsPage) private var page
    @Environment(\.rgSettingsFocus) private var focus
    @Environment(\.lang) private var language
    func body(content: Content) -> some View {
        content
            .id(item)
            .accessibilityIdentifier("regram.setting." + page + "." + item)
            .contextMenu {
                if let destination = RGSettingsDestination(page: page, item: item) {
                    Button("Settings.Link.Copy".i18n(language)) {
                        UIPasteboard.general.string = destination.url.absoluteString
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
            .listRowBackground(focus == item ? Color.accentColor.opacity(0.12) : nil)
    }
}
private struct RGSettingsPageModifier: ViewModifier {
    let page: String
    let focus: String?
    @State private var didScroll = false
    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.environment(\.rgSettingsPage, page).environment(\.rgSettingsFocus, focus)
                .onAppear {
                    guard !didScroll, let focus else { return }
                    didScroll = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { proxy.scrollTo(focus, anchor: .center) }
                }
        }
    }
}
public extension View {
    func rgSettingsLink(_ item: String) -> some View { modifier(RGSettingLinkModifier(item: item)) }
    func rgSettingsPage(_ page: String, focus: String? = nil) -> some View { modifier(RGSettingsPageModifier(page: page, focus: focus)) }
}
