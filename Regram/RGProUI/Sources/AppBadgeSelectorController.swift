import SwiftUI
import UIKit
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import LegacyUI
import Display
import TelegramPresentationData
import AccountContext
import AppBundle


@available(iOS 14.0, *)
private struct AppBadgeSettingsView: View {
    let context: AccountContext

    @Environment(\.lang) private var lang
    @Environment(\.rgSettingsColors) private var settingsColors
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sizeCategory) private var sizeCategory

    @State private var enabled: Bool
    @State private var selectedBadge: String

    init(context: AccountContext) {
        self.context = context
        let settings = RGSimpleSettings.shared
        self._enabled = State(initialValue: settings.screenshotBadgeEnabled)
        self._selectedBadge = State(initialValue: settings.customAppBadge)
    }

    private func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        RGSimpleSettings.shared.screenshotBadgeEnabled = enabled
        self.context.sharedContext.mainWindow?.updateAppBadgeLayout()
    }

    private func selectBadge(_ name: String) {
        guard self.enabled else { return }
        self.selectedBadge = name
        RGSimpleSettings.shared.customAppBadge = name
        self.context.sharedContext.mainWindow?.updateAppBadgeLayout()
    }

    var body: some View {
        RGSettingsList {
            RGSettingsSection {
                Toggle("AppBadge.Enable".i18n(lang), isOn: Binding(get: { self.enabled }, set: self.setEnabled))
                    .accessibilityIdentifier("regram.appBadge.enabled")
            }
            if self.enabled {
                RGSettingsSection(header: Text("AppBadge.Preview".i18n(lang)), footer: Text("AppBadge.Notice".i18n(lang))) {
                    if let image = self.artwork(self.selectedBadge) {
                        VStack(spacing: 8) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: image.size.width, height: image.size.height)
                                .accessibilityHidden(true)
                            Text(RGAppBadgeNames.titleKey(self.selectedBadge).i18n(lang))
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(settingsColors.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                }
                RGSettingsSection(header: Text("AppBadge.Choose".i18n(lang))) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: sizeCategory.isAccessibilityCategory ? 1 : 2), spacing: 8) {
                        ForEach(RGAppBadgeNames.allNames, id: \.self) { name in
                            self.badgeOption(name)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func badgeOption(_ name: String) -> some View {
        let isSelected = self.selectedBadge == name
        return Button {
            self.selectBadge(name)
        } label: {
            VStack(spacing: 6) {
                Group {
                    if let image = self.artwork(name) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 120)
                    }
                }
                .frame(height: 30)
                .accessibilityHidden(true)

                HStack(spacing: 4) {
                    Text(RGAppBadgeNames.titleKey(name).i18n(lang))
                        .foregroundColor(settingsColors.primary)
                        .multilineTextAlignment(.center)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(settingsColors.accent)
                            .accessibilityHidden(true)
                    }
                }
                .font(.footnote.weight(isSelected ? .semibold : .regular))
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(RoundedRectangle(cornerRadius: 12).fill(settingsColors.background))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? settingsColors.accent : settingsColors.separator.opacity(0.4), lineWidth: isSelected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("regram.appBadge.\(name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func artwork(_ name: String) -> UIImage? {
        return UIImage(named: name, in: getAppBundle(), compatibleWith: UITraitCollection(userInterfaceStyle: self.colorScheme == .dark ? .dark : .light))
    }
}

@available(iOS 14.0, *)
public func rgAppBadgeSettingsController(context: AccountContext, presentationData: PresentationData? = nil) -> ViewController {
    let theme = presentationData?.theme ?? (UITraitCollection.current.userInterfaceStyle == .dark ? defaultDarkColorPresentationTheme : defaultPresentationTheme)
    let strings = presentationData?.strings ?? defaultPresentationStrings

    let legacyController = LegacySwiftUIController(
        presentation: .navigation,
        theme: theme,
        strings: strings
    )
    legacyController.bindAppearance(context.sharedContext.presentationData)

    legacyController.statusBar.statusBarStyle = theme.rootController
        .statusBarStyle.style
    legacyController.title = "AppBadge.Title".i18n(strings.rgLanguageCode)
    
    let swiftUIView = RGSwiftUIView<AppBadgeSettingsView>(
        legacyController: legacyController,
        manageSafeArea: true,
        content: {
            AppBadgeSettingsView(context: context)
        }
    )
    let controller = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: controller)

    return legacyController
}
