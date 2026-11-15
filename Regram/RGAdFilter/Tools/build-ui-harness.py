from pathlib import Path
import argparse, json, os, plistlib, re, subprocess

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description='Build production ad correction UIKit controllers with isolated adapters for simulator checks.')
parser.add_argument('--output', type=Path, default=root / 'build-input/ad-filter-ui-checks')
work = parser.parse_args().output.resolve()
work.mkdir(parents=True, exist_ok=True)
source = (root / 'Regram/RGProUI/Sources/RGAdSamplesController.swift').read_text()
source = '\n'.join(line for line in source.splitlines() if not line.startswith('import ')).replace('public ', '')
strings = {}
for line in (root / 'Regram/RGStrings/Strings/zh-hans.lproj/RGLocalizable.strings').read_text().splitlines():
    match = re.fullmatch(r'("AdSamples\.[^"]+") = (".*");', line)
    if match: strings[json.loads(match[1])] = json.loads(match[2])
localization = 'let localized: [String: String] = [' + ',\n'.join(json.dumps(k, ensure_ascii=False) + ': ' + json.dumps(v, ensure_ascii=False) for k,v in strings.items()) + ']\n'
adapters = r'''
import UIKit
import Foundation

extension String { func i18n(_ language: String) -> String { localized[self] ?? self } }
struct Strings { let rgLanguageCode = "zh-hans", Common_Back = "返回", Common_OK = "好", Common_Cancel = "取消", Common_Delete = "删除" }
struct Theme {
    let overallDarkAppearance = true
    struct List {
        let blocksBackgroundColor = UIColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        let itemBlocksBackgroundColor = UIColor(red: 0.16, green: 0.18, blue: 0.21, alpha: 1)
        let itemBlocksSeparatorColor = UIColor.darkGray, itemAccentColor = UIColor.systemBlue
        let itemPrimaryTextColor = UIColor.white, itemSecondaryTextColor = UIColor.lightGray
        let itemHighlightedBackgroundColor = UIColor.darkGray
    }
    struct Root { struct Style { let style = UIStatusBarStyle.lightContent }; let statusBarStyle = Style() }
    let list = List(), rootController = Root()
}
struct PresentationData { let strings = Strings(), theme = Theme() }
struct Holder { func with<T>(_ body: (PresentationData) -> T) -> T { body(PresentationData()) } }
final class Disposable {}
struct Signal { func start(next: (PresentationData) -> Void) -> Disposable { next(PresentationData()); return Disposable() } }
infix operator |> : AdditionPrecedence
func |> (lhs: Signal, rhs: (Signal) -> Signal) -> Signal { rhs(lhs) }
func deliverOnMainQueue(_ signal: Signal) -> Signal { signal }
final class MetaDisposable { func set(_ value: Disposable) {}; func dispose() {} }
final class Shared { let currentPresentationData = Holder(), presentationData = Signal() }
final class AccountContext { let sharedContext = Shared() }
enum GlassStyle { case `default` }
struct NavigationBarPresentationData { init(presentationData: PresentationData, glassStyle: GlassStyle) {} }
enum ContainedViewLayoutTransition {
    case immediate
    func updateFrame(view: UIView, frame: CGRect) { view.frame = frame }
}
final class FakeBar { func updatePresentationData(_ data: NavigationBarPresentationData, transition: ContainedViewLayoutTransition) {} }
final class FakeStatus { var statusBarStyle = UIStatusBarStyle.lightContent }
final class ASDisplayNode {
    let view = UIView()
    var backgroundColor: UIColor? { get { view.backgroundColor } set { view.backgroundColor = newValue } }
}
struct ContainerViewLayout {
    let size: CGSize, safe: UIEdgeInsets
    func insets(options: Set<Int>) -> UIEdgeInsets { safe }
}
struct NavigationLayout { let navigationFrame: CGRect }
class ViewController: UIViewController {
    var displayNode = ASDisplayNode(), navigationBar: FakeBar? = FakeBar(), statusBar = FakeStatus()
    var _hasGlassStyle = false, attemptNavigation: (@escaping () -> Void) -> Bool = { _ in true }
    var isNodeLoaded: Bool { isViewLoaded }
    init(navigationBarPresentationData: NavigationBarPresentationData) { super.init(nibName: nil, bundle: nil) }
    required init(coder: NSCoder) { fatalError() }
    func loadDisplayNode() {}
    func displayNodeDidLoad() {}
    override func loadView() { loadDisplayNode(); view = displayNode.view }
    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {}
    func navigationLayout(layout: ContainerViewLayout) -> NavigationLayout { NavigationLayout(navigationFrame: CGRect(x: 0, y: 0, width: layout.size.width, height: layout.safe.top)) }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); containerLayoutUpdated(ContainerViewLayout(size: view.bounds.size, safe: view.safeAreaInsets), transition: .immediate) }
}
final class NavigationController: UINavigationController {
    func pushViewController(_ value: ViewController) { pushViewController(value, animated: false) }
}
struct PeerId { func toInt64() -> Int64 { 1 } }
struct MessageId { let peerId = PeerId(); let namespace: Int32 = 0, id: Int32 = 1 }
class Media { let id: Int64? = 1 }
final class TelegramMediaWebpage: Media {}
final class TelegramMediaImage: Media {}
final class TelegramMediaFile: Media { let isVideo = true, isVoice = false }
final class Message { let id = MessageId(), media: [Media] = [] }
func rgAdOriginalMessage(_ value: Message) -> Message { value }
func rgCanCorrectAds(_ value: Message) -> Bool { true }
func rgAdInput(_ value: Message) -> RGAdInput { RGAdInput(text: "fixture") }
final class RGAdFilterSession {
    static let shared = RGAdFilterSession()
    static func get(_ context: AccountContext) -> RGAdFilterSession { shared }
    let store = RGAdSampleStore(accountDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("fixture-account"))
    func perform<T>(changes: Bool = false, _ work: @escaping (RGAdSampleStore) throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        completion(Result { try work(store) })
    }
}
'''
main = r'''
func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
@main final class Harness: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    var checks: [String] = []
    func check(_ value: Bool, _ name: String) { precondition(value, name); checks.append(name) }
    func screenshot(_ name: String) {
        let image = UIGraphicsImageRenderer(bounds: window!.bounds).image { _ in window!.drawHierarchy(in: window!.bounds, afterScreenUpdates: true) }
        try! image.pngData()!.write(to: documents.appendingPathComponent(name))
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Checks", sessionRole: session.role); config.delegateClass = HarnessScene.self; return config
    }
    func start(_ scene: UIWindowScene) {
        let context = AccountContext(), text = "剧名：春日旅程\n简介：两人一起寻找答案。\n类型：剧情 / 奇幻\n@search_helper\n\n0充值，免费体验，中奖可提现 → @promotion_user"
        let input = RGAdInput(text: text, peerId: 99, buttons: [[RGAdButton(id: "0:0", title: "电影搜索", target: "https://t.me/search_helper"), RGAdButton(id: "0:1", title: "广告入口", target: "https://example.org/promo")]], hasMedia: true)
        let store = RGAdFilterSession.shared.store
        let sample = try! store.draft(input: input, messageKey: UUID().uuidString, mediaKinds: ["video"], mediaIdentity: "synthetic-video")
        let editor = RGAdEditorController(context: context, sample: sample)
        let navigation = NavigationController(rootViewController: UIViewController())
        window = UIWindow(windowScene: scene); window!.rootViewController = navigation; window!.overrideUserInterfaceStyle = .dark; window!.makeKeyAndVisible()
        navigation.pushViewController(editor, animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            editor.view.layoutIfNeeded()
            let views = descendants(editor.view)
            let textView = views.compactMap { $0 as? UITextView }.first!
            self.check(textView.text == text && !textView.isEditable, "original text intact and read-only")
            self.check(textView.frame.height >= 300, "native text selection area laid out")
            textView.selectedRange = (text as NSString).range(of: "0充值，免费体验，中奖可提现 → @promotion_user")
            let button = views.compactMap { $0 as? UIButton }.first { $0.tag == 1 && $0.title(for: .normal) == "广告" }!
            button.sendActions(for: .touchUpInside)
            self.check(textView.attributedText.attribute(.backgroundColor, at: textView.selectedRange.location, effectiveRange: nil) != nil, "selection highlight rendered")
            self.screenshot("editor.png")
            editor.table.scrollToRow(at: IndexPath(row: 1, section: 1), at: .middle, animated: false)
            editor.table.layoutIfNeeded()
            let segments = descendants(editor.table).compactMap { $0 as? UISegmentedControl }
            let adButton = segments.first { $0.tag == 1 }!
            adButton.selectedSegmentIndex = 1; adButton.sendActions(for: .valueChanged)
            editor.table.delegate?.tableView?(editor.table, didSelectRowAt: IndexPath(row: 0, section: 3))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                let preview = navigation.topViewController!
                preview.view.layoutIfNeeded()
                let labels = descendants(preview.view).compactMap { ($0 as? UILabel)?.text }
                self.check(labels.contains { $0.contains("剧名：春日旅程") && !$0.contains("中奖") }, "preview keeps body and removes marked promotion")
                self.check(labels.contains("电影搜索") && !labels.contains { $0.contains("广告入口") }, "button correction is independent of text")
                self.screenshot("preview.png")
                _ = navigation.popViewController(animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let save = editor.navigationItem.rightBarButtonItem!
                    UIApplication.shared.sendAction(save.action!, to: save.target, from: save, for: nil)
                    let records = try! store.load()
                    self.check(records.contains { $0.id == sample.id && $0.spans.count == 1 && $0.hasUncertainty && $0.buttonLabels["0:1"] == .ad }, "saved reviewed spans and button labels")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.check(navigation.topViewController !== editor, "save returns through native navigation")
                        try! JSONSerialization.data(withJSONObject: ["passed": true, "checks": self.checks, "scope": "Production UIKit controllers and storage on iOS simulator; account/theme/navigation adapters, synthetic input."], options: [.prettyPrinted, .sortedKeys]).write(to: self.documents.appendingPathComponent("result.json"))
                    }
                }
            }
        }
    }
}
final class HarnessScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene, let app = UIApplication.shared.delegate as? Harness else { return }
        app.start(scene); window = app.window
    }
}
'''
(work / 'Harness.swift').write_text(localization + adapters + source + main)
app = work / 'AdSamplesChecks.app'
app.mkdir(exist_ok=True)
with (app / 'Info.plist').open('wb') as stream:
    plistlib.dump({'CFBundleIdentifier':'org.regram.tests.ad-samples','CFBundleExecutable':'AdSamplesChecks','CFBundleName':'Ad Samples Checks','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','CFBundlePackageType':'APPL','MinimumOSVersion':'16.0','UILaunchScreen':{},'UIDeviceFamily':[1,2],'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False}},stream)
sdk = subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-target','arm64-apple-ios16.0-simulator','-sdk',sdk,*map(str,sorted((root/'Regram/RGAdFilter/Sources').glob('*.swift'))),str(work/'Harness.swift'),'-o',str(app/'AdSamplesChecks')],check=True,env={**os.environ,'SDKROOT':sdk})
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print(app)
