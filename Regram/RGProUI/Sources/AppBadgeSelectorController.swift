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
import AppBundle


struct AppBadge: Identifiable, Hashable {
    let displayName: String
    let assetName: String

    var id: String { self.assetName }

    func title(languageCode: String) -> String {
        ("AppBadge.Name." + self.displayName.lowercased()).i18n(languageCode)
    }
}

func getAvailableAppBadges() -> [AppBadge] {
    [
        .init(displayName: "Conversation", assetName: RGAppBadgeNames.defaultName),
        .init(displayName: "Azure", assetName: "RGAzureBadge"),
        .init(displayName: "Iris", assetName: "RGIrisBadge"),
        .init(displayName: "Mint", assetName: "RGMintBadge"),
        .init(displayName: "Gathering", assetName: RGAppBadgeNames.alternateName),
        .init(displayName: "Amber", assetName: "RGAmberBadge"),
        .init(displayName: "Nebula", assetName: "RGNebulaBadge"),
        .init(displayName: "Jade", assetName: "RGJadeBadge"),
        .init(displayName: "Regram", assetName: "RegramAppBadge"),
        .init(displayName: "Zhiqiu", assetName: "ZhiqiuAppBadge"),
    ]
}
    
@available(iOS 14.0, *)
struct AppBadgeSettingsView: View {
    weak var wrapperController: LegacyController?
    let context: AccountContext
    
    @Environment(\.lang) var lang: String
    @Environment(\.rgSettingsColors) private var settingsColors
    @Environment(\.colorScheme) private var colorScheme
    
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
        // Regram badges are local assets; selection is always available.
        DispatchQueue.main.async {
            RGSimpleSettings.shared.customAppBadge = assetName
            if let window = self.context.sharedContext.mainWindow {
                // The badge can now live outside the main view tree. Relayout its new width.
                window.updateAppBadgeLayout()
            }
        }
    }
    
    var body: some View {
        RGSettingsList {
            RGSettingsSection(header: Text("AppBadge.Current".i18n(lang))) {
                VStack(spacing: 12) {
                    if let image = self.artwork(selectedBadge.assetName) {
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
                            if let image = self.artwork(badge.assetName) {
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

    private func artwork(_ name: String) -> UIImage? {
        UIImage(named: name, in: getAppBundle(), compatibleWith: UITraitCollection(userInterfaceStyle: self.colorScheme == .dark ? .dark : .light))
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
