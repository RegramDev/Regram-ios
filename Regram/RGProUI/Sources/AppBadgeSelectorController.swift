import Foundation
import SwiftUI
import UIKit
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import LegacyUI
import Display
import TelegramPresentationData
import AccountContext


struct AppBadge: Identifiable, Hashable {
    let displayName: String
    let assetName: String

    var id: String { self.assetName }

    func title(languageCode: String) -> String {
        ("AppBadge.Name." + self.displayName.lowercased()).i18n(languageCode)
    }
}

func getAvailableAppBadges() -> [AppBadge] {
    var appBadges: [AppBadge] = [
        // `Default` stays first: with nothing stored yet `customAppBadge` is empty and the window
        // falls back to this asset, so the selector's initial highlight is taken from index 0.
        .init(displayName: "Default", assetName: "Components/AppBadge"),
        .init(displayName: "Regram", assetName: "RegramAppBadge"),
        .init(displayName: "Zhiqiu", assetName: "ZhiqiuAppBadge"),
        .init(displayName: "Sky", assetName: "SkyAppBadge"),
        .init(displayName: "Night", assetName: "NightAppBadge"),
        .init(displayName: "Titanium", assetName: "TitaniumAppBadge"),
        .init(displayName: "Pro", assetName: "ProAppBadge"),
        .init(displayName: "Day", assetName: "DayAppBadge"),
    ]

    if RGSimpleSettings.shared.duckyAppIconAvailable {
        appBadges.append(.init(displayName: "Ducky", assetName: "DuckyAppBadge"))
    }
    appBadges += [
        .init(displayName: "Sparkling", assetName: "SparklingAppBadge"),
    ]

    return appBadges
}
    
@available(iOS 14.0, *)
struct AppBadgeSettingsView: View {
    weak var wrapperController: LegacyController?
    let context: AccountContext
    
    @Environment(\.lang) var lang: String
    @Environment(\.rgSettingsColors) private var settingsColors
    
    @State var selectedBadge: AppBadge
    let availableAppBadges: [AppBadge] = getAvailableAppBadges()

    init(wrapperController: LegacyController?, context: AccountContext) {
        self.wrapperController = wrapperController
        self.context = context
        
        for badge in self.availableAppBadges {
            if badge.assetName == RGSimpleSettings.shared.customAppBadge {
                self._selectedBadge = State(initialValue: badge)
                return
            }
        }
        
        self._selectedBadge = State(initialValue: self.availableAppBadges.first!)
    }
    
    private func onSelectBadge(_ badge: AppBadge) {
        let assetName = badge.assetName
        self.selectedBadge = badge
        let image = UIImage(bundleImageName: assetName) ?? UIImage(bundleImageName: "Components/AppBadge")
        // Regram badges are local assets; selection is always available.
        DispatchQueue.main.async {
            RGSimpleSettings.shared.customAppBadge = assetName
            if let window = self.context.sharedContext.mainWindow {
                window.badgeView.image = image
                // The badge can now live outside the main view tree. Relayout its new width.
                window.updateAppBadgeLayout()
            }
        }
    }
    
    var body: some View {
        RGSettingsList {
            RGSettingsSection(header: Text("AppBadge.Current".i18n(lang))) {
                VStack(spacing: 12) {
                    if let image = UIImage(bundleImageName: selectedBadge.assetName) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240)
                            .frame(height: 64)
                            .accessibilityHidden(true)
                    }
                    Text(selectedBadge.title(languageCode: lang))
                        .font(.body.weight(.medium))
                        .foregroundColor(primaryColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            RGSettingsSection(header: Text("AppBadge.Choose".i18n(lang)), footer: Text("AppBadge.Notice".i18n(lang)).foregroundColor(secondaryColor)) {
                ForEach(availableAppBadges) { badge in
                    Button {
                        onSelectBadge(badge)
                    } label: {
                        HStack(spacing: 12) {
                            if let image = UIImage(bundleImageName: badge.assetName) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 128, height: 40)
                                    .accessibilityHidden(true)
                            }

                            Text(badge.title(languageCode: lang))
                                .foregroundColor(primaryColor)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if selectedBadge.assetName == badge.assetName {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(accentColor)
                                    .frame(width: 24, height: 24)
                                    .accessibilityHidden(true)
                            } else {
                                Color.clear.frame(width: 24, height: 24)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                        .frame(minHeight: 56)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("regram.appBadge.\(badge.assetName)")
                    .accessibilityAddTraits(selectedBadge.assetName == badge.assetName ? .isSelected : [])
                }
            }
        }
    }

    private var primaryColor: Color {
        settingsColors.primary
    }

    private var accentColor: Color {
        settingsColors.accent
    }

    private var secondaryColor: Color {
        settingsColors.secondary
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
            AppBadgeSettingsView(wrapperController: legacyController, context: context)
        }
    )
    let controller = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: controller)

    return legacyController
}
