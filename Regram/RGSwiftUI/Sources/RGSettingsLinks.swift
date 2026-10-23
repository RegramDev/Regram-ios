// MARK: Regram — hosted settings copy stable links and scroll to the requested control.
import TelegramPresentationData
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
    @Environment(\.rgSettingsColors) private var colors
    func body(content: Content) -> some View {
        let row = content
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
            // Telegram ItemList rows keep a stable touch target and use the
            // theme's block color instead of iOS's white Form cell.
            .listRowBackground(RGSettingsRowBackground(color: colors.row, highlight: focus == item ? colors.accent.opacity(0.12) : nil))

        if #available(iOS 15.0, *) {
            row.listRowSeparatorTint(colors.separator)
        } else {
            row
        }
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

@available(iOS 13.0, *)
private struct RGSettingsRowModifier: ViewModifier {
    @Environment(\.rgSettingsColors) private var colors

    func body(content: Content) -> some View {
        let row = content
            .listRowBackground(RGSettingsRowBackground(color: colors.row))
        if #available(iOS 15.0, *) {
            row.listRowSeparatorTint(colors.separator)
        } else {
            row
        }
    }
}

@available(iOS 13.0, *)
private struct RGSettingsSectionModifier: ViewModifier {
    @Environment(\.rgSettingsColors) private var colors

    @ViewBuilder
    func body(content: Content) -> some View {
        let section = content.listRowBackground(RGSettingsRowBackground(color: colors.row))
        if #available(iOS 15.0, *) {
            section
                .listSectionSeparator(.hidden)
                .listRowSeparatorTint(colors.separator)
        } else {
            section
        }
    }
}

@available(iOS 13.0, *)
private struct RGSettingsSectionHeader<Content: View>: View {
    @Environment(\.rgSettingsColors) private var colors
    let content: Content

    var body: some View {
        content
            .font(.footnote.weight(.medium))
            .foregroundColor(colors.sectionHeader)
    }
}

@available(iOS 13.0, *)
private struct RGSettingsSectionFooter<Content: View>: View {
    @Environment(\.rgSettingsColors) private var colors
    let content: Content

    var body: some View {
        content
            .font(.footnote)
            .foregroundColor(colors.freeText)
    }
}

/// Telegram-styled replacement for SwiftUI's Section. The value-style
/// overloads mirror SwiftUI's four common Section initializers, so existing
/// `Section(header: Text(...)) { ... }` code can be migrated mechanically.
@available(iOS 13.0, *)
public struct RGSettingsSection<Content: View, Header: View, Footer: View>: View {
    private let content: Content
    private let header: Header
    private let footer: Footer

    public init(@ViewBuilder content: () -> Content) where Header == EmptyView, Footer == EmptyView {
        self.content = content()
        self.header = EmptyView()
        self.footer = EmptyView()
    }

    public init(header: Header, @ViewBuilder content: () -> Content) where Footer == EmptyView {
        self.content = content()
        self.header = header
        self.footer = EmptyView()
    }

    public init(footer: Footer, @ViewBuilder content: () -> Content) where Header == EmptyView {
        self.content = content()
        self.header = EmptyView()
        self.footer = footer
    }

    public init(header: Header, footer: Footer, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.header = header
        self.footer = footer
    }

    public var body: some View {
        Section(
            header: RGSettingsSectionHeader(content: header),
            footer: RGSettingsSectionFooter(content: footer),
            content: { content.rgSettingsRow() }
        )
        .modifier(RGSettingsSectionModifier())
    }
}

@available(iOS 13.0, *)
private struct RGSettingsPrimaryTextModifier: ViewModifier {
    @Environment(\.rgSettingsColors) private var colors
    func body(content: Content) -> some View { content.foregroundColor(colors.primary) }
}

@available(iOS 13.0, *)
private struct RGSettingsSecondaryTextModifier: ViewModifier {
    @Environment(\.rgSettingsColors) private var colors
    func body(content: Content) -> some View { content.foregroundColor(colors.secondary) }
}

public extension View {
    func rgSettingsLink(_ item: String) -> some View { modifier(RGSettingLinkModifier(item: item)) }
    func rgSettingsPage(_ page: String, focus: String? = nil) -> some View { modifier(RGSettingsPageModifier(page: page, focus: focus)) }

    /// Applies the same inset block background and separator used by a
    /// Telegram settings section. This is intentionally a row/section
    /// modifier, so callers can still attach List's onMove/onDelete handlers.
    func rgSettingsRow() -> some View { modifier(RGSettingsRowModifier()) }

    /// Marks a section as a Telegram-style grouped section. Header/footer
    /// typography remains owned by SwiftUI so Dynamic Type and localization
    /// continue to work, while the row surface follows the current theme.
    func rgSettingsSection() -> some View { modifier(RGSettingsSectionModifier()) }

    /// Semantic Telegram text colors for custom rows and diagnostic values.
    func rgPrimaryText() -> some View { modifier(RGSettingsPrimaryTextModifier()) }
    func rgSecondaryText() -> some View { modifier(RGSettingsSecondaryTextModifier()) }
}
