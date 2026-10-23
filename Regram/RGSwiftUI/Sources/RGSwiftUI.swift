import Display
import Foundation
import LegacyUI
import SwiftUI
import UIKit
import TelegramPresentationData
import SwiftSignalKit
import RGSimpleSettings
import RGTypography
import RGStrings


// MARK: Regram — use the selected language before Telegram's secondary fallback language.
public extension PresentationStrings {
    var rgLanguageCode: String { RGLocalizationManager.shared.preferredLocale(primary: self.primaryComponent.languageCode, secondary: self.secondaryComponent?.languageCode) }
}

@available(iOS 13.0, *)
public class ObservedValue<T>: ObservableObject {
    @Published public var value: T

    public init(_ value: T) {
        self.value = value
    }
}

@available(iOS 13.0, *)
public struct NavigationBarHeightKey: EnvironmentKey {
    public static let defaultValue: CGFloat = 0
}

@available(iOS 13.0, *)
public struct ContainerViewLayoutKey: EnvironmentKey {
    public static let defaultValue: ContainerViewLayout? = nil
}

@available(iOS 13.0, *)
public struct RGPresentationThemeKey: EnvironmentKey {
    public static let defaultValue: PresentationTheme? = nil
}

@available(iOS 13.0, *)
public struct LangKey: EnvironmentKey {
    public static let defaultValue: String = "en"
}

// MARK: Regram — semantic colors shared by every SwiftUI settings surface.
//
// Telegram's ItemList uses the presentation theme for both the canvas and the
// inset blocks.  SwiftUI's Form/List otherwise falls back to system grouped
// colors, which makes hosted settings look like a different application. Keep
// the mapping in one place so a theme change updates all hosted screens.
@available(iOS 13.0, *)
public struct RGSettingsSemanticColors {
    public let background: Color
    public let row: Color
    public let primary: Color
    public let secondary: Color
    public let disabled: Color
    public let accent: Color
    public let destructive: Color
    public let separator: Color
    public let sectionHeader: Color
    public let freeText: Color
    public let switchOn: Color
    public let switchFrame: Color
    public let switchContent: Color
    public let switchHandle: Color

    public init(theme: PresentationTheme?) {
        let list = theme?.list
        self.background = Color(uiColor: list?.blocksBackgroundColor ?? .systemGroupedBackground)
        self.row = Color(uiColor: list?.itemBlocksBackgroundColor ?? .secondarySystemGroupedBackground)
        self.primary = Color(uiColor: list?.itemPrimaryTextColor ?? .label)
        self.secondary = Color(uiColor: list?.itemSecondaryTextColor ?? .secondaryLabel)
        self.disabled = Color(uiColor: list?.itemDisabledTextColor ?? .tertiaryLabel)
        self.accent = Color(uiColor: list?.itemAccentColor ?? .systemBlue)
        self.destructive = Color(uiColor: list?.itemDestructiveColor ?? .systemRed)
        self.separator = Color(uiColor: list?.itemBlocksSeparatorColor ?? .separator)
        self.sectionHeader = Color(uiColor: list?.sectionHeaderTextColor ?? .secondaryLabel)
        self.freeText = Color(uiColor: list?.freeTextColor ?? list?.itemSecondaryTextColor ?? .secondaryLabel)
        self.switchOn = Color(uiColor: list?.itemSwitchColors.contentColor ?? list?.itemAccentColor ?? .systemGreen)
        self.switchFrame = Color(uiColor: list?.itemSwitchColors.frameColor ?? .systemGray)
        self.switchContent = Color(uiColor: list?.itemSwitchColors.contentColor ?? .systemGreen)
        self.switchHandle = Color(uiColor: list?.itemSwitchColors.handleColor ?? .white)
    }
}

@available(iOS 13.0, *)
public struct RGSettingsSemanticColorsKey: EnvironmentKey {
    public static let defaultValue = RGSettingsSemanticColors(theme: nil)
}

// Perhaps, affects Performance a lot
//@available(iOS 13.0, *)
//public struct ContainerViewLayoutUpdateCountKey: EnvironmentKey {
//    public static let defaultValue: ObservedValue<Int64> = ObservedValue(0)
//}

@available(iOS 13.0, *)
public extension EnvironmentValues {
    var navigationBarHeight: CGFloat {
        get { self[NavigationBarHeightKey.self] }
        set { self[NavigationBarHeightKey.self] = newValue }
    }
    
    var containerViewLayout: ContainerViewLayout? {
        get { self[ContainerViewLayoutKey.self] }
        set { self[ContainerViewLayoutKey.self] = newValue }
    }

    var rgPresentationTheme: PresentationTheme? {
        get { self[RGPresentationThemeKey.self] }
        set { self[RGPresentationThemeKey.self] = newValue }
    }

    var lang: String {
        get { self[LangKey.self] }
        set { self[LangKey.self] = newValue }
    }

    var rgSettingsColors: RGSettingsSemanticColors {
        get { self[RGSettingsSemanticColorsKey.self] }
        set { self[RGSettingsSemanticColorsKey.self] = newValue }
    }
    
//    var containerViewLayoutUpdateCount: ObservedValue<Int64> {
//        get { self[ContainerViewLayoutUpdateCountKey.self] }
//        set { self[ContainerViewLayoutUpdateCountKey.self] = newValue }
//    }
}


@available(iOS 13.0, *)
public struct RGSwiftUIView<Content: View>: View {
    public let content: Content
    public let manageSafeArea: Bool

    @ObservedObject var navigationBarHeight: ObservedValue<CGFloat>
    @ObservedObject var containerViewLayout: ObservedValue<ContainerViewLayout?>
//    @ObservedObject var containerViewLayoutUpdateCount: ObservedValue<Int64>

    @ObservedObject private var languageModel: ObservedValue<String>
    @ObservedObject private var themeModel: ObservedValue<PresentationTheme?>
    
    public init(
        legacyController: LegacySwiftUIController,
        manageSafeArea: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        #if DEBUG
        if manageSafeArea {
            print("WARNING RGSwiftUIView: manageSafeArea is deprecated, use @Environment(\\.navigationBarHeight) and @Environment(\\.containerViewLayout)")
        }
        #endif
        self.navigationBarHeight = legacyController.navigationBarHeightModel
        self.containerViewLayout = legacyController.containerViewLayoutModel
        self.languageModel = legacyController.languageModel
        self.themeModel = legacyController.themeModel
//        self.containerViewLayoutUpdateCount = legacyController.containerViewLayoutUpdateCountModel
        self.manageSafeArea = manageSafeArea
        self.content = content()
    }

    public var body: some View {
        content
            .if(manageSafeArea) { $0.modifier(CustomSafeArea()) }
            .environment(\.navigationBarHeight, navigationBarHeight.value)
            .environment(\.containerViewLayout, containerViewLayout.value)
            .environment(\.lang, languageModel.value)
            .environment(\.rgPresentationTheme, themeModel.value)
            .environment(\.rgSettingsColors, RGSettingsSemanticColors(theme: themeModel.value))
            .foregroundColor(RGSettingsSemanticColors(theme: themeModel.value).primary)
            .preferredColorScheme(themeModel.value.map { $0.overallDarkAppearance ? .dark : .light })
            .accentColor(RGSettingsSemanticColors(theme: themeModel.value).accent)
            // MARK: Regram — list actions use the surrounding row, not iOS's filled button capsule.
            .buttonStyle(RGListActionButtonStyle(theme: themeModel.value))
            .menuStyle(.borderlessButton)
            .modifier(RGSettingsListSurface(theme: themeModel.value))
            .font(RGTypography.font(configuration: RGSimpleSettings.shared.fontConfiguration, area: .interface, size: UIFont.preferredFont(forTextStyle: .body).pointSize).map { SwiftUI.Font($0) })
//            .environment(\.containerViewLayoutUpdateCount, containerViewLayoutUpdateCount)
//            .onReceive(containerViewLayoutUpdateCount.$value) { _ in
//                // Make sure View is updated when containerViewLayoutUpdateCount changes,
//                // in case it does not depend on containerViewLayout
//            }
    }
    
}

@available(iOS 13.0, *)
public struct CustomSafeArea: ViewModifier {
    @Environment(\.navigationBarHeight) var navigationBarHeight: CGFloat
    @Environment(\.containerViewLayout) var containerViewLayout: ContainerViewLayout?

    public func body(content: Content) -> some View {
        content
            .edgesIgnoringSafeArea(.all)
//            .padding(.top, /*totalTopSafeArea > navigationBarHeight.value ? totalTopSafeArea :*/ navigationBarHeight.value)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
            .padding(.leading, leftInset)
            .padding(.trailing, rightInset)
    }

    private var topInset: CGFloat {
        max(
            (containerViewLayout?.safeInsets.top ?? 0) + (containerViewLayout?.intrinsicInsets.top ?? 0),
            navigationBarHeight
        )
    }
    
    private var bottomInset: CGFloat {
        (containerViewLayout?.safeInsets.bottom ?? 0)
// DEPRECATED, do not change
//        + (containerViewLayout.value?.intrinsicInsets.bottom ?? 0)
    }
    
    private var leftInset: CGFloat {
        containerViewLayout?.safeInsets.left ?? 0
    }
    
    private var rightInset: CGFloat {
        containerViewLayout?.safeInsets.right ?? 0
    }
}

@available(iOS 13.0, *)
public extension View {
    func rgTopSafeAreaInset(_ containerViewLayout: ContainerViewLayout?, _ navigationBarHeight: CGFloat) -> CGFloat {
        return max(
            (containerViewLayout?.safeInsets.top ?? 0) + (containerViewLayout?.intrinsicInsets.top ?? 0),
            navigationBarHeight
        )
    }
    
    func rgBottomSafeAreaInset(_ containerViewLayout: ContainerViewLayout?) -> CGFloat {
        return (containerViewLayout?.safeInsets.bottom ?? 0) + (containerViewLayout?.intrinsicInsets.bottom ?? 0)
    }
    
    func rgLeftSafeAreaInset(_ containerViewLayout: ContainerViewLayout?) -> CGFloat {
        return containerViewLayout?.safeInsets.left ?? 0
    }

    func rgRightSafeAreaInset(_ containerViewLayout: ContainerViewLayout?) -> CGFloat {
        return containerViewLayout?.safeInsets.right ?? 0
    }

}


@available(iOS 13.0, *)
public final class LegacySwiftUIController: LegacyController {
    // Share the upstream unified glass bar and interactive back gesture with native ItemList pages.
    public var navigationBarHeightModel: ObservedValue<CGFloat>
    public var containerViewLayoutModel: ObservedValue<ContainerViewLayout?>
    public var inputHeightModel: ObservedValue<CGFloat?>
    public let languageModel: ObservedValue<String>
    public let themeModel: ObservedValue<PresentationTheme?>
    public var lang: String { self.languageModel.value }
    private let appearanceDisposable = MetaDisposable()
//    public var containerViewLayoutUpdateCountModel: ObservedValue<Int64>

    override public init(presentation: LegacyControllerPresentation, theme: PresentationTheme? = nil, strings: PresentationStrings? = nil, initialLayout: ContainerViewLayout? = nil) {
        navigationBarHeightModel = ObservedValue<CGFloat>(0.0)
        containerViewLayoutModel = ObservedValue<ContainerViewLayout?>(initialLayout)
        inputHeightModel = ObservedValue<CGFloat?>(nil)
        languageModel = ObservedValue(strings?.rgLanguageCode ?? "en")
        themeModel = ObservedValue(theme)
//        containerViewLayoutUpdateCountModel = ObservedValue<Int64>(0)
        super.init(presentation: presentation, theme: theme, strings: strings, initialLayout: initialLayout)
        self._hasGlassStyle = true
        // MARK: Regram — hosted settings share Telegram navigation and its localized back item.
        if let strings { self.navigationItem.backBarButtonItem = UIBarButtonItem(title: strings.Common_Back, style: .plain, target: nil, action: nil) }
    }

    public func bindAppearance(_ signal: Signal<PresentationData, NoError>) {
        self.appearanceDisposable.set((signal |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self else { return }
            self.themeModel.value = data.theme
            self.legacyController?.overrideUserInterfaceStyle = data.theme.overallDarkAppearance ? .dark : .light
            self.languageModel.value = data.strings.rgLanguageCode
            self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: data, glassStyle: .default), transition: .immediate)
            self.statusBar.statusBarStyle = data.theme.rootController.statusBarStyle.style
        }))
    }
    deinit { self.appearanceDisposable.dispose() }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
//        containerViewLayoutUpdateCountModel.value += 1
        
        var newNavigationBarHeight = navigationLayout(layout: layout).navigationFrame.maxY
        if !self.displayNavigationBar || self.navigationPresentation == .modal {
            newNavigationBarHeight = 0.0
        }
        if navigationBarHeightModel.value != newNavigationBarHeight {
            navigationBarHeightModel.value = newNavigationBarHeight
        }
        if containerViewLayoutModel.value != layout {
            containerViewLayoutModel.value = layout
        }
        if inputHeightModel.value != layout.inputHeight {
            inputHeightModel.value = layout.inputHeight
        }
    }

    override public func bind(controller: UIViewController) {
        super.bind(controller: controller)
        addChild(controller)
        controller.didMove(toParent: self)
    }

    @available(*, unavailable)
    public required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(iOS 13.0, *)
extension UIHostingController {
    public convenience init(rootView: Content, ignoreSafeArea: Bool) {
        self.init(rootView: rootView)

        if ignoreSafeArea {
            disableSafeArea()
        }
    }

    func disableSafeArea() {
        guard let viewClass = object_getClass(view) else {
            return
        }

        func encodeText(string: String, key: Int16) -> String {
            let nsString = string as NSString
            let result = NSMutableString()
            for i in 0 ..< nsString.length {
                var c: unichar = nsString.character(at: i)
                c = unichar(Int16(c) + key)
                result.append(NSString(characters: &c, length: 1) as String)
            }
            return result as String
        }

        let viewSubclassName = String(cString: class_getName(viewClass)).appending(encodeText(string: "`JhopsfTbgfBsfb", key: -1))

        if let viewSubclass = NSClassFromString(viewSubclassName) {
            object_setClass(view, viewSubclass)
        } else {
            guard
                let viewClassNameUtf8 = (viewSubclassName as NSString).utf8String,
                let viewSubclass = objc_allocateClassPair(viewClass, viewClassNameUtf8, 0)
            else {
                return
            }

            if let method = class_getInstanceMethod(UIView.self, #selector(getter: UIView.safeAreaInsets)) {
                let safeAreaInsets: @convention(block) (AnyObject) -> UIEdgeInsets = { _ in
                    .zero
                }

                class_addMethod(
                    viewSubclass,
                    #selector(getter: UIView.safeAreaInsets),
                    imp_implementationWithBlock(safeAreaInsets),
                    method_getTypeEncoding(method)
                )
            }

            objc_registerClassPair(viewSubclass)
            object_setClass(view, viewSubclass)
        }
    }
}


@available(iOS 13.0, *)
public struct TGNavigationBackButtonModifier: ViewModifier {
    weak var wrapperController: LegacyController?
    
    public func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .navigationBarItems(leading:
                NavigationBarBackButton(action: {
                    wrapperController?.dismiss()
                })
                .padding(.leading, -8)
            )
    }
}

@available(iOS 13.0, *)
public extension View {
    func tgNavigationBackButton(wrapperController: LegacyController?) -> some View {
        modifier(TGNavigationBackButtonModifier(wrapperController: wrapperController))
    }
}


@available(iOS 13.0, *)
public struct NavigationBarBackButton: View {
    let text: String
    let color: Color
    let action: () -> Void
    
    public init(text: String = "Back", color: Color = .accentColor, action: @escaping () -> Void) {
        self.text = text
        self.color = color
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let customBackArrow = navigationBarBackArrowImage(color: color.uiColor()) {
                    Image(uiImage: customBackArrow)
                } else {
                    Image(systemName: "chevron.left")
                        .font(Font.body.weight(.bold))
                        .foregroundColor(color)
                }
                Text(text)
                    .foregroundColor(color)
            }
            .contentShape(Rectangle())
        }
    }
}

@available(iOS 13.0, *)
public extension View {
    func apply<V: View>(@ViewBuilder _ block: (Self) -> V) -> V { block(self) }
    
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: @escaping () -> Bool, transform: (Self) -> Content) -> some View {
        if condition() {
            transform(self)
        } else {
            self
        }
    }
}

@available(iOS 13.0, *)
public extension Color {
 
    func uiColor() -> UIColor {

        if #available(iOS 14.0, *) {
            return UIColor(self)
        }

        let components = self.components()
        return UIColor(red: components.r, green: components.g, blue: components.b, alpha: components.a)
    }

    private func components() -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {

        let scanner = Scanner(string: self.description.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var hexNumber: UInt64 = 0
        var r: CGFloat = 0.0, g: CGFloat = 0.0, b: CGFloat = 0.0, a: CGFloat = 0.0

        let result = scanner.scanHexInt64(&hexNumber)
        if result {
            r = CGFloat((hexNumber & 0xff000000) >> 24) / 255
            g = CGFloat((hexNumber & 0x00ff0000) >> 16) / 255
            b = CGFloat((hexNumber & 0x0000ff00) >> 8) / 255
            a = CGFloat(hexNumber & 0x000000ff) / 255
        }
        return (r, g, b, a)
    }
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB (No alpha)
            (a, r, g, b) = (255, (int >> 16) & 0xff, (int >> 8) & 0xff, int & 0xff)
        case 8: // ARGB
            (a, r, g, b) = ((int >> 24) & 0xff, (int >> 16) & 0xff, (int >> 8) & 0xff, int & 0xff)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}


public enum BackgroundMaterial {
    case ultraThinMaterial
    case thinMaterial
    case regularMaterial
    case thickMaterial
    case ultraThickMaterial
    
    @available(iOS 15.0, *)
    var material: Material {
        switch self {
        case .ultraThinMaterial: return .ultraThinMaterial
        case .thinMaterial: return .thinMaterial
        case .regularMaterial: return .regularMaterial
        case .thickMaterial: return .thickMaterial
        case .ultraThickMaterial: return .ultraThickMaterial
        }
    }
}

public enum BounceBehavior {
    case automatic
    case always
    case basedOnSize
    
    @available(iOS 16.4, *)
    var behavior: ScrollBounceBehavior {
        switch self {
        case .automatic: return .automatic
        case .always: return .always
        case .basedOnSize: return .basedOnSize
        }
    }
}


@available(iOS 13.0, *)
public extension View {
    func fontWeightIfAvailable(_ weight: SwiftUI.Font.Weight) -> some View {
        if #available(iOS 16.0, *) {
            return self.fontWeight(weight)
        } else {
            return self
        }
    }
    
    func backgroundIfAvailable(material: BackgroundMaterial) -> some View {
        if #available(iOS 15.0, *) {
            return self.background(material.material)
        } else {
            return self.background(
                Color(.systemBackground)
                    .opacity(0.75)
                    .blur(radius: 3)
                    .overlay(Color.white.opacity(0.1))
            )
        }
    }
}

@available(iOS 13.0, *)
public extension View {
    func scrollBounceBehaviorIfAvailable(_ behavior: BounceBehavior) -> some View {
        if #available(iOS 16.4, *) {
            return self.scrollBounceBehavior(behavior.behavior)
        } else {
            return self
        }
    }
}

@available(iOS 13.0, *)
public extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

@available(iOS 13.0, *)
public struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    public func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

@available(iOS 13.0, *)
public struct ContentSizeModifier: ViewModifier {
    @Binding var size: CGSize
    
    public func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry -> Color in
                    if geometry.size != size {
                        DispatchQueue.main.async {
                            self.size = geometry.size
                        }
                    }
                    return Color.clear
                }
            )
    }
}

@available(iOS 13.0, *)
public extension View {
    func trackSize(_ size: Binding<CGSize>) -> some View {
        self.modifier(ContentSizeModifier(size: size))
    }
}

// MARK: Regram — theme-aware hosted settings keep native list rows and action roles.
@available(iOS 13.0, *)
private struct RGListActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    let theme: PresentationTheme?
    private func actionColor(_ configuration: Configuration) -> UIColor {
        if #available(iOS 15.0, *), configuration.role == .destructive { return theme?.list.itemDestructiveColor ?? .systemRed }
        return theme?.list.itemAccentColor ?? .systemBlue
    }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundColor(Color(uiColor: actionColor(configuration))).opacity(!enabled ? 0.4 : configuration.isPressed ? 0.6 : 1)
    }
}

/// Applies Telegram's grouped-list surface to a SwiftUI Form/List.
///
/// This modifier intentionally uses only the view subtree. It does not touch
/// UITableView.appearance(), so a hosted settings screen cannot leak its theme
/// into Telegram's other screens.
@available(iOS 13.0, *)
public struct RGSettingsListSurface: ViewModifier {
    private let theme: PresentationTheme?
    @Environment(\.rgPresentationTheme) private var environmentTheme

    public init(theme: PresentationTheme? = nil) {
        self.theme = theme
    }

    @ViewBuilder public func body(content: Content) -> some View {
        let resolvedTheme = theme ?? environmentTheme
        let colors = RGSettingsSemanticColors(theme: resolvedTheme)
        content
            // Use the same grouped-list structure on every hosted settings page.
            .listStyle(InsetGroupedListStyle())
            .environment(\.rgPresentationTheme, resolvedTheme)
            .environment(\.rgSettingsColors, colors)
            .foregroundColor(colors.primary)
            .environment(\.defaultMinListRowHeight, 44.0)
            .modifier(RGSettingsTintModifier(color: colors.accent))
            .toggleStyle(SwitchToggleStyle(tint: colors.switchOn))
            .modifier(RGSettingsScrollBackgroundModifier(color: colors.background))
    }
}

/// A Telegram-colored list row background. On iOS 16 and later the hidden
/// scroll content background is enough; on iOS 13–15 SwiftUI's List keeps a
/// UIKit table behind the rows, so the small local bridge below updates that
/// table without changing any global UIAppearance setting.
@available(iOS 13.0, *)
public struct RGSettingsRowBackground: View {
    private let row: Color
    private let highlight: Color
    @Environment(\.rgSettingsColors) private var colors
    @Environment(\.rgPresentationTheme) private var theme

    public init(color: Color, highlight: Color? = nil) {
        self.row = color
        self.highlight = highlight ?? .clear
    }

    public var body: some View {
        let fill = row.overlay(highlight)
        if #available(iOS 16.0, *) {
            fill
        } else {
            fill.overlay(RGSettingsTableBridge(theme: theme, canvas: colors.background))
        }
    }
}

@available(iOS 13.0, *)
private struct RGSettingsTableBridge: UIViewRepresentable {
    let theme: PresentationTheme?
    let canvas: Color

    func makeUIView(context: Context) -> RGSettingsTableBridgeView {
        let view = RGSettingsTableBridgeView()
        view.alpha = 0.0
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: RGSettingsTableBridgeView, context: Context) {
        view.theme = theme
        view.canvas = canvas
        view.applyIfVisible()
        DispatchQueue.main.async { view.applyIfVisible() }
    }
}

@available(iOS 13.0, *)
private final class RGSettingsTableBridgeView: UIView {
    var theme: PresentationTheme?
    var canvas: Color = Color(.systemGroupedBackground)

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyIfVisible()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyIfVisible()
    }

    func applyIfVisible() {
        guard self.window != nil else { return }
        var current: UIView? = self
        while let candidate = current {
            if let table = candidate as? UITableView {
                let list = theme?.list
                if #available(iOS 14.0, *) {
                    table.backgroundColor = UIColor(canvas)
                } else {
                    table.backgroundColor = list?.blocksBackgroundColor ?? .systemGroupedBackground
                }
                table.separatorColor = list?.itemBlocksSeparatorColor ?? .separator
                table.tintColor = list?.itemAccentColor ?? .systemBlue
                table.indicatorStyle = theme?.overallDarkAppearance == true ? .white : .default
                return
            }
            current = candidate.superview
        }
    }
}

@available(iOS 13.0, *)
private struct RGSettingsTintModifier: ViewModifier {
    let color: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content.tint(color)
        } else {
            content.accentColor(color)
        }
    }
}

@available(iOS 13.0, *)
private struct RGSettingsScrollBackgroundModifier: ViewModifier {
    let color: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden).background(color)
        } else {
            content.background(color)
        }
    }
}

// MARK: Regram — opt-in wrappers for pages that own their List/Form root.
// Existing pages may continue to use List/Form directly; RGSwiftUIView applies
// the same surface globally to hosted pages. These wrappers are useful when a
// page is composed outside RGSwiftUIView and preserve List's normal row
// behavior, including onMove/onDelete attached inside the content closure.
@available(iOS 13.0, *)
public struct RGSettingsList<Content: View>: View {
    private let content: Content
    private let theme: PresentationTheme?

    public init(theme: PresentationTheme? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.theme = theme
    }

    public var body: some View {
        List { content.rgSettingsRow() }
            .modifier(RGSettingsListSurface(theme: theme))
    }
}

@available(iOS 13.0, *)
public struct RGSettingsForm<Content: View>: View {
    private let content: Content
    private let theme: PresentationTheme?

    public init(theme: PresentationTheme? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.theme = theme
    }

    public var body: some View {
        // Form uses a platform-dependent list style on older iOS releases.
        // List with an explicit inset-grouped style keeps the Telegram block
        // geometry stable across every supported device.
        List { content.rgSettingsRow() }
            .modifier(RGSettingsListSurface(theme: theme))
    }
}
