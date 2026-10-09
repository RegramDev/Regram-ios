import Foundation
import UIKit
import WebKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import RGSimpleSettings
import RGStrings

// MARK: Regram — the NSFW section.
//
// Reached from the settings row that appears (between My Profile and Proxy) once the switch in Regram
// Pro is on. It is a small in-app browser: a "Recommended" landing page generated locally, plus external
// sites. Content is gated behind an 18+ confirmation shown once and remembered.
//
// Deliberately self-contained in this module (WebKit is a system framework, no new Bazel dep) so it
// can be pushed straight from `PeerInfoScreenSettingsActions`.

private enum RGNSFWSource: Int, CaseIterable {
    case recommendations
    case novel
    case missav
    case huangguo
    case javranking

    var externalURL: URL? {
        switch self {
        case .recommendations:
            return nil
        case .novel:
            return URL(string: "https://nv-pu-sa.pages.dev")
        case .missav:
            return URL(string: "https://missav.ws/")
        case .huangguo:
            return URL(string: "https://huangguoai.com/")
        case .javranking:
            return URL(string: "https://javranking.cc/zh-hans/")
        }
    }
}

/// A curated set of codes shown on the recommendations page; each links into MissAV.
private let rgNSFWRecommendedCodes: [String] = [
    "SONE-289", "SSIS-698", "MIDV-661", "STARS-949", "IPX-811", "ABW-352",
    "MIAA-742", "JUL-889", "PRED-451", "CAWD-503", "FSDSS-670", "OFJE-505",
    "MEYD-782", "WAAA-201", "DLDSS-201", "ROE-201"
]

private func rgNSFWRecommendationsHTML(theme: PresentationTheme, lang: String) -> String {
    let isDark = theme.overallDarkAppearance
    let bg = isDark ? "#0e0e10" : "#f2f2f7"
    let cardBg = isDark ? "#1c1c1e" : "#ffffff"
    let fg = isDark ? "#ffffff" : "#1c1c1e"
    let sub = isDark ? "#98989f" : "#8a8a8e"
    let accent = "#ff2d55"
    let colorScheme = isDark ? "dark" : "light"

    let title = "NSFW.Recommend.Header".i18n(lang)
    let subtitle = "NSFW.Recommend.Subtitle".i18n(lang)
    let searchPlaceholder = "NSFW.Recommend.SearchPlaceholder".i18n(lang)

    // Curated fallback list, passed to JS as a literal array. Shown immediately, and if the live
    // fetch below succeeds it is replaced with real covers from today's listing.
    let codesJS = rgNSFWRecommendedCodes.map { "\"\($0)\"" }.joined(separator: ",")

    // Raw string (#"""…"""#) so the JS regex backslashes are preserved; Swift values are injected
    // with \#(...). Scheme 2 (real covers) + scheme 3 (dynamic scrape): the page is served with
    // baseURL missav.ws, so a same-origin fetch of the listing works, and the covers/links are the
    // site's own.
    return #"""
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    <style>
    :root { color-scheme: \#(colorScheme); }
    * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
    body { margin: 0; padding: 16px; background: \#(bg); color: \#(fg);
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
    h1 { font-size: 22px; margin: 4px 0 2px; }
    p.sub { font-size: 13px; color: \#(sub); margin: 0 0 16px; }
    form { display: flex; gap: 8px; margin-bottom: 18px; }
    input[type=search] { flex: 1; border: none; border-radius: 10px; padding: 11px 14px;
        font-size: 16px; background: \#(cardBg); color: \#(fg); }
    button { border: none; border-radius: 10px; padding: 0 16px; font-size: 15px; font-weight: 600;
        background: \#(accent); color: #fff; }
    .grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; }
    .card { display: block; text-decoration: none; color: \#(fg); background: \#(cardBg);
        border-radius: 14px; overflow: hidden; }
    .thumb { position: relative; width: 100%; aspect-ratio: 16 / 10; display: flex;
        align-items: center; justify-content: center; font-size: 30px; font-weight: 800;
        letter-spacing: 1px; color: #fff; background: linear-gradient(135deg, \#(accent), #8e2de2);
        background-size: cover; background-position: center; }
    .thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
    .code { padding: 9px 11px; font-size: 13px; font-weight: 600; white-space: nowrap;
        overflow: hidden; text-overflow: ellipsis; }
    </style>
    </head>
    <body>
    <h1>\#(title)</h1>
    <p class="sub">\#(subtitle)</p>
    <form onsubmit="var v=this.q.value.trim(); if(v){location.href='https://missav.ws/search/'+encodeURIComponent(v);} return false;">
        <input type="search" name="q" placeholder="\#(searchPlaceholder)" autocapitalize="off" autocorrect="off">
        <button type="submit">GO</button>
    </form>
    <div class="grid" id="grid"></div>
    <script>
    var FALLBACK = [\#(codesJS)];
    var BASE = "https://missav.ws/";

    function esc(s){ return (s||"").replace(/[&<>"]/g, function(c){ return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]; }); }

    function cardHTML(item){
        var thumb = item.cover
            ? '<div class="thumb"><img loading="lazy" src="'+esc(item.cover)+'" onerror="this.remove()"></div>'
            : '<div class="thumb">'+esc(item.code.slice(0,3))+'</div>';
        return '<a class="card" href="'+esc(item.href)+'">'+thumb+'<div class="code">'+esc(item.code)+'</div></a>';
    }

    function render(items){
        var grid = document.getElementById('grid');
        grid.innerHTML = items.map(cardHTML).join('');
    }

    // Immediate fallback: the curated list as plain code tiles.
    render(FALLBACK.map(function(code){ return { code: code, href: BASE + code.toLowerCase(), cover: null }; }));

    function absolutize(href){
        try { return new URL(href, BASE).href; } catch(e){ return href; }
    }

    function extractItems(doc){
        var out = [], seen = {};
        var anchors = doc.querySelectorAll('a[href]');
        for (var i = 0; i < anchors.length; i++){
            var a = anchors[i];
            var href = a.getAttribute('href') || '';
            var m = href.match(/\/([a-z]+-\d+)(?:\/|\?|$)/i);
            if (!m) continue;
            var code = m[1].toUpperCase();
            if (seen[code]) continue;
            seen[code] = true;
            var img = a.querySelector('img');
            var src = '';
            if (img) { src = img.getAttribute('data-src') || img.getAttribute('src') || ''; }
            if (src.indexOf('//') === 0) { src = 'https:' + src; }
            else if (src && src.indexOf('http') !== 0) { src = absolutize(src); }
            out.push({ code: code, href: absolutize(href), cover: src || null });
            if (out.length >= 30) break;
        }
        return out;
    }

    // Live listing (scheme 3). Same-origin, so no CORS. First candidate that yields cards wins.
    (function loadHot(){
        var candidates = [BASE + 'today-hot', BASE + 'weekly-hot', BASE];
        var idx = 0;
        function tryNext(){
            if (idx >= candidates.length) return;
            var url = candidates[idx++];
            fetch(url, { credentials: 'omit' })
                .then(function(r){ return r.ok ? r.text() : Promise.reject(); })
                .then(function(html){
                    var doc = new DOMParser().parseFromString(html, 'text/html');
                    var items = extractItems(doc);
                    if (items.length) { render(items); } else { tryNext(); }
                })
                .catch(function(){ tryNext(); });
        }
        tryNext();
    })();
    </script>
    </body>
    </html>
    """#
}

// MARK: Regram — choose a destination first; each destination owns its webpage history.
private extension RGNSFWSource {
    func title(lang: String) -> String {
        switch self {
        case .recommendations: return "NSFW.Tab.Recommend".i18n(lang)
        case .novel: return "Nv"
        case .missav: return "MissAV"
        case .huangguo: return "黄果"
        case .javranking: return "JAV Ranking"
        }
    }
}

private final class RGNSFWControllerNode: ASDisplayNode, WKNavigationDelegate, WKUIDelegate {
    private let presentationData: PresentationData
    private let source: RGNSFWSource?
    private let openSource: (RGNSFWSource) -> Void
    private let menuScrollView = UIScrollView()
    private let menuStack = UIStackView()
    private let topPanel = UIView()
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []
    private var contentRevealed = false

    var canGoBack: Bool { self.webView.canGoBack }

    init(presentationData: PresentationData, source: RGNSFWSource?, openSource: @escaping (RGNSFWSource) -> Void) {
        self.presentationData = presentationData
        self.source = source
        self.openSource = openSource
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.allowsBackForwardNavigationGestures = true
        self.webView.isOpaque = false
        super.init()
        self.backgroundColor = presentationData.theme.list.plainBackgroundColor
    }

    override func didLoad() {
        super.didLoad()
        let theme = self.presentationData.theme
        let lang = self.presentationData.strings.baseLanguageCode
        self.menuStack.axis = .vertical
        self.menuStack.spacing = 12
        self.menuScrollView.addSubview(self.menuStack)
        self.view.addSubview(self.menuScrollView)
        for source in RGNSFWSource.allCases {
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.plain()
            configuration.title = source.title(lang: lang)
            configuration.subtitle = source.externalURL?.host
            configuration.image = UIImage(systemName: "chevron.right")
            configuration.imagePlacement = .trailing
            configuration.imagePadding = 12
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
            configuration.baseForegroundColor = theme.list.itemPrimaryTextColor
            configuration.background.backgroundColor = theme.list.itemBlocksBackgroundColor
            configuration.background.cornerRadius = 12
            button.configuration = configuration
            button.contentHorizontalAlignment = .leading
            button.accessibilityIdentifier = "regram.nsfw.destination.\(source.rawValue)"
            button.addAction(UIAction { [weak self] _ in self?.openSource(source) }, for: .touchUpInside)
            self.menuStack.addArrangedSubview(button)
        }

        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self
        self.webView.backgroundColor = theme.list.plainBackgroundColor
        self.webView.scrollView.backgroundColor = theme.list.plainBackgroundColor
        self.view.addSubview(self.webView)
        self.topPanel.backgroundColor = theme.rootController.navigationBar.opaqueBackgroundColor
        self.view.addSubview(self.topPanel)
        self.backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        self.forwardButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        self.backButton.accessibilityLabel = "NSFW.Back".i18n(lang)
        self.forwardButton.accessibilityLabel = lang.hasPrefix("zh") ? "网页前进" : "Forward"
        self.backButton.accessibilityIdentifier = "regram.nsfw.web.back"
        self.forwardButton.accessibilityIdentifier = "regram.nsfw.web.forward"
        for button in [self.backButton, self.forwardButton] {
            button.tintColor = theme.rootController.navigationBar.accentTextColor
            button.isEnabled = false
            self.topPanel.addSubview(button)
        }
        self.backButton.addTarget(self, action: #selector(self.goBack), for: .touchUpInside)
        self.forwardButton.addTarget(self, action: #selector(self.goForward), for: .touchUpInside)
        self.progressView.progressTintColor = theme.rootController.navigationBar.accentTextColor
        self.progressView.trackTintColor = .clear
        self.topPanel.addSubview(self.progressView)
        self.observations = [
            self.webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] web, _ in self?.backButton.isEnabled = web.canGoBack },
            self.webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] web, _ in self?.forwardButton.isEnabled = web.canGoForward },
            self.webView.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in
                guard let self else { return }
                self.progressView.setProgress(Float(web.estimatedProgress), animated: true)
                self.progressView.isHidden = web.estimatedProgress >= 1 || web.estimatedProgress <= 0
            }
        ]
        self.menuScrollView.isHidden = true
        self.webView.isHidden = true
        self.topPanel.isHidden = true
        if self.source != nil {
            // Disable Telegram's parent pop recognizer even at the screen edge. WKWebView owns
            // back/forward swipes, so a right swipe never exits to Settings or the directory.
            self.view.disablesInteractiveTransitionGestureRecognizerNow = { true }
        }
    }

    func revealContentIfNeeded() {
        guard !self.contentRevealed else { return }
        self.contentRevealed = true
        if let source = self.source {
            self.webView.isHidden = false
            self.topPanel.isHidden = false
            if let url = source.externalURL {
                self.webView.load(URLRequest(url: url))
            } else {
                self.webView.loadHTMLString(rgNSFWRecommendationsHTML(theme: self.presentationData.theme, lang: self.presentationData.strings.baseLanguageCode), baseURL: URL(string: "https://missav.ws/"))
            }
        } else {
            self.menuScrollView.isHidden = false
        }
    }

    @objc func goBack() { if self.webView.canGoBack { self.webView.goBack() } }
    @objc private func goForward() { if self.webView.canGoForward { self.webView.goForward() } }
    func reload() { self.webView.reload() }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let left = layout.safeInsets.left
        let right = layout.safeInsets.right
        let width = max(1, layout.size.width - left - right)
        let bottom = max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom)
        self.menuScrollView.frame = CGRect(x: left, y: navigationBarHeight, width: width, height: max(1, layout.size.height - navigationBarHeight - bottom))
        let menuWidth = max(1, width - 32)
        let menuSize = self.menuStack.systemLayoutSizeFitting(CGSize(width: menuWidth, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        self.menuStack.frame = CGRect(x: 16, y: 20, width: menuWidth, height: menuSize.height)
        self.menuScrollView.contentSize = CGSize(width: width, height: menuSize.height + 40)
        self.topPanel.frame = CGRect(x: left, y: navigationBarHeight, width: width, height: 44)
        self.backButton.frame = CGRect(x: 0, y: 0, width: 52, height: 44)
        self.forwardButton.frame = CGRect(x: 52, y: 0, width: 52, height: 44)
        self.progressView.frame = CGRect(x: 0, y: 41.5, width: width, height: 2.5)
        transition.updateFrame(view: self.webView, frame: CGRect(x: left, y: navigationBarHeight + 44, width: width, height: max(1, layout.size.height - navigationBarHeight - 44 - bottom)))
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }
}

private final class RGNSFWControllerImpl: ViewController {
    private let context: AccountContext
    private let presentationData: PresentationData
    private let source: RGNSFWSource?
    private var ageGatePresented = false
    private var controllerNode: RGNSFWControllerNode { self.displayNode as! RGNSFWControllerNode }

    init(context: AccountContext, source: RGNSFWSource? = nil) {
        self.context = context
        self.source = source
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        let lang = self.presentationData.strings.baseLanguageCode
        self.title = source?.title(lang: lang) ?? "NSFW.Title".i18n(lang)
        self.navigationPresentation = .default
        if source != nil {
            let directory = UIBarButtonItem(image: UIImage(systemName: "list.bullet"), style: .plain, target: self, action: #selector(self.openDirectory))
            directory.accessibilityLabel = lang.hasPrefix("zh") ? "返回网站列表" : "Website List"
            self.navigationItem.rightBarButtonItems = [directory, UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(self.reloadPressed))]
            // The navigation-bar back arrow follows webpage history first. The directory button
            // explicitly exits this browser, while webpage swipes never pop the app controller.
            self.attemptNavigation = { [weak self] _ in
                guard let self, self.isNodeLoaded else { return true }
                if self.controllerNode.canGoBack { self.controllerNode.goBack(); return false }
                return true
            }
        }
    }
    required init(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadDisplayNode() {
        self.displayNode = RGNSFWControllerNode(presentationData: self.presentationData, source: self.source, openSource: { [weak self] source in
            guard let self, RGSimpleSettings.shared.nsfwAgeConfirmed else { return }
            self.navigationController?.pushViewController(RGNSFWControllerImpl(context: self.context, source: source), animated: true)
        })
        self.displayNodeDidLoad()
    }
    @objc private func reloadPressed() { self.controllerNode.reload() }
    @objc private func openDirectory() {
        if let navigation = self.navigationController as? NavigationController { navigation.filterController(self, animated: true) }
        else { self.navigationController?.popViewController(animated: true) }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.presentAgeGateIfNeeded()
    }
    private func presentAgeGateIfNeeded() {
        if RGSimpleSettings.shared.nsfwAgeConfirmed { self.controllerNode.revealContentIfNeeded(); return }
        guard !self.ageGatePresented else { return }
        self.ageGatePresented = true
        let lang = self.presentationData.strings.baseLanguageCode
        let controller = textAlertController(context: self.context, title: "NSFW.AgeGate.Title".i18n(lang), text: "NSFW.AgeGate.Text".i18n(lang), actions: [
            TextAlertAction(type: .genericAction, title: "NSFW.AgeGate.Leave".i18n(lang), action: { [weak self] in self?.openDirectory() }),
            TextAlertAction(type: .defaultAction, title: "NSFW.AgeGate.Confirm".i18n(lang), action: { [weak self] in
                RGSimpleSettings.shared.nsfwAgeConfirmed = true
                self?.controllerNode.revealContentIfNeeded()
            })
        ], actionLayout: .vertical, dismissOnOutsideTap: false)
        self.present(controller, in: .window(.root))
    }
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }
}

public func rgNSFWController(context: AccountContext) -> ViewController { RGNSFWControllerImpl(context: context) }
