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
// Pro is on. It is a small in-app browser: a "Recommended" landing page generated locally, plus two
// external sites. Content is gated behind an 18+ confirmation shown once and remembered.
//
// Deliberately self-contained in this module (WebKit is a system framework, no new Bazel dep) so it
// can be pushed straight from `PeerInfoScreenSettingsActions`.

private enum RGNSFWSource: Int, CaseIterable {
    case recommendations
    case novel
    case missav

    var externalURL: URL? {
        switch self {
        case .recommendations:
            return nil
        case .novel:
            return URL(string: "https://nv-pu-sa.pages.dev")
        case .missav:
            return URL(string: "https://missav.ws/")
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

private final class RGNSFWControllerNode: ASDisplayNode, WKNavigationDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData

    private let topPanelNode: ASDisplayNode
    private let separatorNode: ASDisplayNode
    private let segmentedControl: UISegmentedControl
    private let progressView: UIProgressView
    private let webView: WKWebView

    private var currentSource: RGNSFWSource = .recommendations
    private var progressObservation: NSKeyValueObservation?
    private var contentRevealed = false

    private var validLayout: (ContainerViewLayout, CGFloat)?

    init(context: AccountContext, presentationData: PresentationData) {
        self.context = context
        self.presentationData = presentationData

        self.topPanelNode = ASDisplayNode()
        self.separatorNode = ASDisplayNode()

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        self.webView = WKWebView(frame: CGRect(), configuration: configuration)
        self.webView.allowsBackForwardNavigationGestures = true
        self.webView.isOpaque = false

        self.segmentedControl = UISegmentedControl(items: [
            "NSFW.Tab.Recommend".i18n(presentationData.strings.baseLanguageCode),
            "Nv",
            "MissAV"
        ])
        self.segmentedControl.selectedSegmentIndex = 0

        self.progressView = UIProgressView(progressViewStyle: .bar)

        super.init()

        self.backgroundColor = presentationData.theme.list.plainBackgroundColor
        self.topPanelNode.backgroundColor = presentationData.theme.rootController.navigationBar.opaqueBackgroundColor
        self.separatorNode.backgroundColor = presentationData.theme.rootController.navigationBar.separatorColor

        self.addSubnode(self.topPanelNode)
        self.addSubnode(self.separatorNode)
    }

    deinit {
        self.progressObservation?.invalidate()
    }

    override func didLoad() {
        super.didLoad()

        self.webView.navigationDelegate = self
        self.webView.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        self.webView.scrollView.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        self.view.addSubview(self.webView)

        self.segmentedControl.addTarget(self, action: #selector(self.segmentChanged), for: .valueChanged)
        self.topPanelNode.view.addSubview(self.segmentedControl)

        self.progressView.progressTintColor = self.presentationData.theme.rootController.navigationBar.accentTextColor
        self.progressView.trackTintColor = .clear
        self.topPanelNode.view.addSubview(self.progressView)

        self.progressObservation = self.webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self else {
                return
            }
            let progress = Float(webView.estimatedProgress)
            self.progressView.setProgress(progress, animated: true)
            self.progressView.isHidden = progress >= 1.0 || progress <= 0.0
        }

        // The webview stays hidden until the 18+ gate is cleared.
        self.webView.isHidden = true
    }

    /// Loads the initial content once the age gate has passed.
    func revealContentIfNeeded() {
        if self.contentRevealed {
            return
        }
        self.contentRevealed = true
        self.webView.isHidden = false
        self.loadSource(self.currentSource)
    }

    @objc private func segmentChanged() {
        if let source = RGNSFWSource(rawValue: self.segmentedControl.selectedSegmentIndex) {
            self.loadSource(source)
        }
    }

    func reload() {
        if self.currentSource == .recommendations {
            self.loadSource(.recommendations)
        } else {
            self.webView.reload()
        }
    }

    private func loadSource(_ source: RGNSFWSource) {
        self.currentSource = source
        switch source {
        case .recommendations:
            let html = rgNSFWRecommendationsHTML(theme: self.presentationData.theme, lang: self.presentationData.strings.baseLanguageCode)
            self.webView.loadHTMLString(html, baseURL: URL(string: "https://missav.ws/"))
        default:
            if let url = source.externalURL {
                self.webView.load(URLRequest(url: url))
            }
        }
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = (layout, navigationBarHeight)

        let leftInset = layout.safeInsets.left
        let rightInset = layout.safeInsets.right
        let bottomInset = layout.intrinsicInsets.bottom

        let panelHeight: CGFloat = 44.0
        let topPanelFrame = CGRect(origin: CGPoint(x: 0.0, y: navigationBarHeight), size: CGSize(width: layout.size.width, height: panelHeight))
        transition.updateFrame(node: self.topPanelNode, frame: topPanelFrame)
        transition.updateFrame(node: self.separatorNode, frame: CGRect(origin: CGPoint(x: 0.0, y: topPanelFrame.maxY), size: CGSize(width: layout.size.width, height: UIScreenPixel)))

        let controlInset: CGFloat = 8.0
        self.segmentedControl.frame = CGRect(x: leftInset + controlInset, y: 6.0, width: layout.size.width - leftInset - rightInset - controlInset * 2.0, height: panelHeight - 12.0)
        self.progressView.frame = CGRect(x: 0.0, y: panelHeight - 2.5, width: layout.size.width, height: 2.5)

        let webViewFrame = CGRect(x: leftInset, y: topPanelFrame.maxY + UIScreenPixel, width: layout.size.width - leftInset - rightInset, height: max(1.0, layout.size.height - topPanelFrame.maxY - bottomInset))
        transition.updateFrame(view: self.webView, frame: webViewFrame)
    }

    // MARK: WKNavigationDelegate — keep every tap inside the in-app browser.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }
}

private final class RGNSFWControllerImpl: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData

    private var controllerNode: RGNSFWControllerNode {
        return self.displayNode as! RGNSFWControllerNode
    }

    init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))

        self.title = "NSFW.Title".i18n(self.presentationData.strings.baseLanguageCode)
        self.navigationPresentation = .default

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(self.reloadPressed))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = RGNSFWControllerNode(context: self.context, presentationData: self.presentationData)
        self.displayNodeDidLoad()
    }

    @objc private func reloadPressed() {
        self.controllerNode.reload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.presentAgeGateIfNeeded()
    }

    private func presentAgeGateIfNeeded() {
        if RGSimpleSettings.shared.nsfwAgeConfirmed {
            self.controllerNode.revealContentIfNeeded()
            return
        }
        let lang = self.presentationData.strings.baseLanguageCode
        let controller = textAlertController(
            context: self.context,
            title: "NSFW.AgeGate.Title".i18n(lang),
            text: "NSFW.AgeGate.Text".i18n(lang),
            actions: [
                TextAlertAction(type: .genericAction, title: "NSFW.AgeGate.Leave".i18n(lang), action: { [weak self] in
                    guard let self else {
                        return
                    }
                    if let navigationController = self.navigationController as? NavigationController {
                        let _ = navigationController.popViewController(animated: true)
                    }
                }),
                TextAlertAction(type: .defaultAction, title: "NSFW.AgeGate.Confirm".i18n(lang), action: { [weak self] in
                    guard let self else {
                        return
                    }
                    RGSimpleSettings.shared.nsfwAgeConfirmed = true
                    self.controllerNode.revealContentIfNeeded()
                })
            ],
            actionLayout: .vertical,
            dismissOnOutsideTap: false
        )
        self.present(controller, in: .window(.root))
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        let navigationHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: transition)
    }
}

public func rgNSFWController(context: AccountContext) -> ViewController {
    return RGNSFWControllerImpl(context: context)
}
