import AppKit
import WebKit
import Foundation

// Runs the production script in WebKit's isolated world against local HTML, with no account or API.
@main final class WebTranslationScriptTests: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private let webView = WKWebView()
    static func main() {
        let app = NSApplication.shared
        let delegate = WebTranslationScriptTests()
        app.setActivationPolicy(.prohibited)
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        webView.navigationDelegate = self
        webView.frame = CGRect(x: 0, y: 0, width: 500, height: 600)
        webView.loadHTMLString("""
        <h1>Hello world</h1><p><span>Text &amp; symbols</span><a href="https://example.com/path?x=1">A link</a></p>
        <input value="Private input"><textarea>Private textarea</textarea><pre>Code</pre><code>Inline code</code>
        <p contenteditable>Private editor</p><p hidden>Hidden text</p><p style="display:none">Invisible text</p><p translate="no">Untouched</p>
        """, baseURL: URL(string: "https://example.com"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { fatalError("WebKit fixture timed out") }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        evaluate(RGWebTranslationScript.collect) { value in
            assert(value as? [String] == ["Hello world", "Text & symbols", "A link"], String(describing: value))
            let translated = "Quote '\" \\ newline\n<script>window.injected=1</script> 中文"
            self.evaluate(RGWebTranslationScript.apply(index: 0, translation: translated)!) { _ in
                self.webView.evaluateJavaScript("[document.querySelector('h1').textContent, document.querySelector('input').value, document.querySelector('a').getAttribute('href'), window.injected || null, document.querySelector('textarea').textContent]") { value, error in
                    assert(error == nil)
                    let values = value as! [Any]
                    assert(values[0] as? String == translated)
                    assert(values[1] as? String == "Private input")
                    assert(values[2] as? String == "https://example.com/path?x=1")
                    assert(values[3] is NSNull)
                    assert(values[4] as? String == "Private textarea")
                    self.evaluate(RGWebTranslationScript.restore) { _ in
                        self.webView.evaluateJavaScript("document.querySelector('h1').textContent") { value, error in
                            assert(error == nil && value as? String == "Hello world")
                            // A site update made after translation must survive restoring the original.
                            self.evaluate(RGWebTranslationScript.collect) { _ in
                                self.evaluate(RGWebTranslationScript.apply(index: 0, translation: "Translated")!) { _ in
                                    self.webView.evaluateJavaScript("document.querySelector('h1').textContent = 'Site update'") { _, _ in
                                        self.evaluate(RGWebTranslationScript.restore) { _ in
                                            self.webView.evaluateJavaScript("document.querySelector('h1').textContent") { value, _ in
                                                assert(value as? String == "Site update")
                                                print("WebKit translation checks passed: readable text, private fields excluded, escaped text, links preserved, reversible changes, dynamic updates retained")
                                                NSApplication.shared.terminate(nil)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    private func evaluate(_ script: String, completion: @escaping (Any?) -> Void) {
        webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
            switch result { case let .success(value): completion(value); case let .failure(error): fatalError("\(error)") }
        }
    }
}
