// MARK: Regram — width controls with a preview rendered by the production tab-bar component.
import Foundation
import UIKit
import SwiftUI
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import AccountContext
import TelegramPresentationData
import TelegramUIPreferences
import SwiftSignalKit
import Display
import LegacyUI
import ComponentFlow
import ComponentDisplayAdapters
import TabBarComponent

private final class RGTabBarPreviewView: UIView {
    private let componentView = ComponentView<Empty>()
    private var items: [TabBarComponent.Item] = []
    var presentationData: PresentationData?
    var widthPercent: Int32 = 0
    var showTabNames = true
    var measured: ((CGFloat) -> Void)?
    private var previousWidth: CGFloat = -1.0

    func setTabs(_ tabs: [(String, String)]) {
        self.items = tabs.enumerated().map { index, tab in
            let item = UITabBarItem(title: tab.0, image: UIImage(systemName: tab.1), tag: index)
            item.selectedImage = UIImage(systemName: tab.1)
            return TabBarComponent.Item(content: .tabBarItem(item), action: { _ in }, doubleTapAction: nil, contextAction: nil)
        }
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let presentationData, self.bounds.width > 0.0, !self.items.isEmpty else { return }
        let sideInset: CGFloat = (self.window?.safeAreaInsets.bottom ?? 0.0) > 28.0 ? 12.0 : 20.0
        let size = self.componentView.update(
            transition: .immediate,
            component: AnyComponent(TabBarComponent(theme: presentationData.theme, strings: presentationData.strings, items: self.items, search: nil, selectedId: self.items.first.flatMap { item in
                if case let .tabBarItem(tab) = item.content { return AnyHashable(ObjectIdentifier(tab)) }
                return nil
            }, outerInsets: .zero, widthPercent: self.widthPercent, showTabNames: self.showTabNames)),
            environment: {},
            containerSize: CGSize(width: max(0.0, self.bounds.width - sideInset * 2.0), height: 100.0)
        )
        if let view = self.componentView.view {
            if view.superview == nil { self.addSubview(view) }
            view.isUserInteractionEnabled = false
            view.frame = CGRect(x: floor((self.bounds.width - size.width) * 0.5), y: floor((self.bounds.height - size.height) * 0.5), width: size.width, height: size.height)
        }
        if abs(size.width - self.previousWidth) > 0.1 {
            self.previousWidth = size.width
            self.measured?(size.width)
        }
    }
}

private struct RGTabBarWidthPreview: UIViewRepresentable {
    let presentationData: PresentationData
    let widthPercent: Int32
    let showTabNames: Bool
    let showContacts: Bool
    let showCalls: Bool
    @Binding var measuredWidth: CGFloat

    func makeUIView(context: Context) -> RGTabBarPreviewView {
        let view = RGTabBarPreviewView()
        view.accessibilityIdentifier = "regram.tabBarWidth.preview"
        return view
    }

    func updateUIView(_ view: RGTabBarPreviewView, context: Context) {
        let strings = self.presentationData.strings
        var tabs: [(String, String)] = []
        if self.showContacts { tabs.append((strings.Contacts_Title, "person.crop.circle")) }
        tabs.append((strings.DialogList_Title, "bubble.left.and.bubble.right"))
        if self.showCalls { tabs.append((strings.CallSettings_TabIcon, "phone")) }
        tabs.append((strings.Settings_Title, "gearshape"))
        view.presentationData = self.presentationData
        view.widthPercent = self.widthPercent
        view.showTabNames = self.showTabNames
        view.measured = { width in
            DispatchQueue.main.async { self.measuredWidth = width }
        }
        view.setTabs(tabs)
    }
}

private struct RGTabBarWidthSettingsView: SwiftUI.View {
    let context: AccountContext
    let presentationData: PresentationData
    @SwiftUI.Environment(\.lang) private var lang
    @State private var widthPercent = RGTabBarLayoutPolicy.normalizedPercent(RGSimpleSettings.shared.tabBarWidthPercent)
    @State private var measuredWidth: CGFloat = 0.0
    @State private var showContacts = false
    @State private var showCalls = false
    @State private var settingsDisposable: Disposable?

    private var automatic: Binding<Bool> {
        Binding(get: { self.widthPercent == 0 }, set: { self.widthPercent = $0 ? 0 : RGTabBarLayoutPolicy.maximumPercent })
    }

    private var sliderValue: Binding<Double> {
        Binding(get: { Double(self.widthPercent == 0 ? RGTabBarLayoutPolicy.maximumPercent : self.widthPercent) }, set: { self.widthPercent = RGTabBarLayoutPolicy.normalizedPercent(Int32($0.rounded())) })
    }

    var body: some SwiftUI.View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20.0) {
                Text("Settings.Tabs.Width.Preview".i18n(lang))
                    .font(.headline)
                RGTabBarWidthPreview(presentationData: self.presentationData, widthPercent: self.widthPercent, showTabNames: RGSimpleSettings.shared.showTabNames, showContacts: self.showContacts, showCalls: self.showCalls, measuredWidth: self.$measuredWidth)
                    .frame(height: 100.0)
                    .padding(.horizontal, -20.0)
                    .accessibilityLabel("Settings.Tabs.Width.Preview".i18n(lang))
                Text(self.widthPercent == 0 ? "Settings.Tabs.Width.Automatic".i18n(lang) : "\(self.widthPercent)%")
                    .font(.title2.monospacedDigit())
                    .accessibilityIdentifier("regram.tabBarWidth.percent")
                Text("Settings.Tabs.Width.Actual".i18n(lang, args: String(format: "%.0f", Double(self.measuredWidth))))
                    .font(.body.monospacedDigit())
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("regram.tabBarWidth.points")
                Toggle("Settings.Tabs.Width.Automatic".i18n(lang), isOn: self.automatic)
                    .accessibilityIdentifier("regram.tabBarWidth.automatic")
                Slider(value: self.sliderValue, in: Double(RGTabBarLayoutPolicy.minimumPercent)...Double(RGTabBarLayoutPolicy.maximumPercent), step: 1.0)
                    .disabled(self.widthPercent == 0)
                    .accessibilityLabel("Settings.Tabs.Width".i18n(lang))
                    .accessibilityValue(self.widthPercent == 0 ? "Settings.Tabs.Width.Automatic".i18n(lang) : "\(self.widthPercent)%")
                    .accessibilityIdentifier("regram.tabBarWidth.slider")
                HStack {
                    Text("\(RGTabBarLayoutPolicy.minimumPercent)%")
                    Spacer()
                    Text("\(RGTabBarLayoutPolicy.maximumPercent)%")
                }
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                Text("Settings.Tabs.Width.Notice".i18n(lang))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                if RGSimpleSettings.shared.hideTabBar {
                    Text("Settings.Tabs.Width.Hidden".i18n(lang))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Button("Settings.Tabs.Width.Reset".i18n(lang)) { self.widthPercent = 0 }
                    .accessibilityIdentifier("regram.tabBarWidth.reset")
            }
            .padding(20.0)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .onChange(of: self.widthPercent) { value in
            RGSimpleSettings.shared.tabBarWidthPercent = RGTabBarLayoutPolicy.normalizedPercent(value)
        }
        .onAppear {
            self.settingsDisposable = (self.context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings]) |> deliverOnMainQueue).start(next: { data in
                let settings = data.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) ?? .defaultSettings
                self.showContacts = settings.showContactsTab
                self.showCalls = settings.showTab
            })
        }
        .onDisappear { self.settingsDisposable?.dispose(); self.settingsDisposable = nil }
    }
}

public func rgTabBarWidthController(context: AccountContext) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: presentationData.theme, strings: presentationData.strings)
    controller.title = "Settings.Tabs.Width".i18n(presentationData.strings.baseLanguageCode)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: {
        RGTabBarWidthSettingsView(context: context, presentationData: presentationData)
    })
    controller.bind(controller: UIHostingController(rootView: content.preferredColorScheme(presentationData.theme.overallDarkAppearance ? .dark : .light).tint(Color(uiColor: presentationData.theme.list.itemAccentColor)), ignoreSafeArea: true))
    return controller
}
