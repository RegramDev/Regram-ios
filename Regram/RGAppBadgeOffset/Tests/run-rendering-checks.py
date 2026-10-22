#!/usr/bin/env python3
"""Exercise production badge rendering in an isolated UIKit fixture, without Regram or account data."""
from pathlib import Path
import argparse
import json
import os
import plistlib
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--simulator', required=True)
parser.add_argument('--output', default='build-input/badge-rendering-checks')
args = parser.parse_args()
work = ROOT / args.output
work.mkdir(parents=True, exist_ok=True)
env = dict(os.environ)
env.setdefault('DEVELOPER_DIR', '/Applications/Xcode-27.0.app/Contents/Developer')
app = work / 'BadgeChecks.app'
app.mkdir(exist_ok=True)
bundle_id = 'test.regram.badgerendering'

production = '\n'.join((ROOT / f'Regram/RGAppBadgeOffset/Sources/{name}.swift').read_text()
                       .replace('import AppBundle', '').replace('import RGSimpleSettings', '')
                       for name in ('RGAppBadgeImageView', 'RGAppBadgeOverlay'))
(work / 'Production.swift').write_text(production)
(work / 'App.swift').write_text(r'''
import UIKit
import ObjectiveC

final class RGSimpleSettings {
    static let shared = RGSimpleSettings()
    var customAppBadge = "RGConversationBadge"
}
func getAppBundle() -> Bundle { Bundle.main }
enum Probe {
    static weak var view: UIImageView?
    static var assignments = 0
}
extension UIImageView {
    @objc func rg_countedSetImage(_ value: UIImage?) {
        if self === Probe.view { Probe.assignments += 1 }
        self.rg_countedSetImage(value)
    }
}
@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = Scene.self
        return configuration
    }
}
final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var started = false
    var results: [String: Bool] = [:]
    var badge: RGAppBadgeImageView!
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        let window = UIWindow(windowScene: scene as! UIWindowScene)
        window.rootViewController = UIViewController()
        window.rootViewController!.view.backgroundColor = .systemBackground
        window.overrideUserInterfaceStyle = .light
        self.window = window
        window.makeKeyAndVisible()
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard !started else { return }; started = true
        DispatchQueue.main.async { self.checkLight() }
    }
    func background(_ image: UIImage?, matches color: [UInt8]) -> Bool {
        guard let cg = image?.cgImage else { return false }
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let bitmap = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = CGContext(data: &bytes, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmap)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let i = (cg.width + cg.width / 2) * 4
        return (0..<3).allSatisfy { abs(Int(bytes[i + $0]) - Int(color[$0])) < 3 } && bytes[i + 3] == 255
    }
    func checkLight() {
        method_exchangeImplementations(class_getInstanceMethod(UIImageView.self, #selector(setter: UIImageView.image))!,
                                       class_getInstanceMethod(UIImageView.self, #selector(UIImageView.rg_countedSetImage(_:)))!)
        badge = RGAppBadgeImageView(frame: CGRect(x: 50, y: 80, width: 112, height: 28))
        window!.rootViewController!.view.addSubview(badge)
        badge.reloadArtwork()
        Probe.view = badge
        for _ in 0..<1000 { badge.reloadArtwork() }
        results["unchanged_layout_zero_image_assignments"] = Probe.assignments == 0
        results["light_asset_and_logical_size"] = background(badge.image, matches: [243, 234, 220]) && badge.image?.size == CGSize(width: 112, height: 28)
        window!.overrideUserInterfaceStyle = .dark
        self.awaitDarkAppearance()
    }
    func awaitDarkAppearance(_ attempt: Int = 0) {
        // UIKit propagates an override during its update pass, not necessarily the next dispatch.
        if badge.traitCollection.userInterfaceStyle != .dark && attempt < 60 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.awaitDarkAppearance(attempt + 1) }
            return
        }
        self.checkDark()
    }
    func checkDark() {
        results["dark_asset_automatically_reloaded"] = background(badge.image, matches: [229, 229, 234])
        let before = Probe.assignments
        RGSimpleSettings.shared.customAppBadge = "RGGatheringBadge"
        badge.reloadArtwork()
        results["one_selection_reloads_once"] = Probe.assignments == before + 1 && background(badge.image, matches: [229, 229, 234])
        let overlay = RGAppBadgeOverlay(badgeView: badge)
        let fallback = window!.rootViewController!.view!
        let frame = CGRect(x: 50, y: 80, width: 112, height: 28)
        overlay.update(hostWindow: window, fallbackView: fallback, badgeFrame: frame, enabled: true)
        let overlayWindow = window!.windowScene!.windows.first { $0 is RGAppBadgeWindow }!
        let mask = overlayWindow.layer.mask as! CAShapeLayer
        let original = mask.path
        for _ in 0..<1000 { overlay.update(hostWindow: window, fallbackView: fallback, badgeFrame: frame, enabled: true) }
        results["unchanged_layout_reuses_mask_path"] = mask.path === original
        let moved = frame.offsetBy(dx: 40, dy: 15)
        overlay.update(hostWindow: window, fallbackView: fallback, badgeFrame: moved, enabled: true)
        results["changed_geometry_updates_mask"] = mask.path !== original && mask.path?.boundingBoxOfPath == overlayWindow.convert(moved, from: window)
        results["overlay_inherits_dark_appearance"] = overlayWindow.traitCollection.userInterfaceStyle == .dark && background(badge.image, matches: [229, 229, 234])
        badge.isHidden = true; overlay.updateVisibility()
        results["hidden_badge_hides_overlay"] = overlayWindow.isHidden
        badge.isHidden = false; overlay.updateVisibility()
        results["visible_badge_restores_overlay"] = !overlayWindow.isHidden
        overlay.update(hostWindow: window, fallbackView: fallback, badgeFrame: moved, enabled: false)
        results["fallback_reattaches_without_window"] = badge.superview === fallback && overlayWindow.isHidden && overlayWindow.rootViewController == nil
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("results.json")
        try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: output)
    }
}
''')
info = {'CFBundleExecutable': 'BadgeChecks', 'CFBundleIdentifier': bundle_id, 'CFBundleName': 'BadgeChecks',
        'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0', 'CFBundlePackageType': 'APPL',
        'CFBundleSupportedPlatforms': ['iPhoneSimulator'], 'MinimumOSVersion': '15.0', 'UIDeviceFamily': [1, 2],
        'LSRequiresIPhoneOS': True, 'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False},
        'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft',
                                           'UIInterfaceOrientationLandscapeRight', 'UIInterfaceOrientationPortraitUpsideDown']}
(app / 'Info.plist').write_bytes(plistlib.dumps(info))
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], env=env, text=True).strip()
env['SDKROOT'] = sdk
subprocess.run(['xcrun', 'actool', str(ROOT / 'Regram/RGAppBadgeAssets/Images.xcassets'), '--compile', str(app),
                '--platform', 'iphonesimulator', '--minimum-deployment-target', '15.0', '--target-device', 'iphone',
                '--target-device', 'ipad'], env=env, check=True, capture_output=True, timeout=90)
subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-target', 'arm64-apple-ios15.0-simulator', '-sdk', sdk,
                str(work / 'Production.swift'), str(work / 'App.swift'), '-o', str(app / 'BadgeChecks')],
               env=env, check=True, timeout=90)
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], env=env, check=True, capture_output=True)
try:
    subprocess.run(['xcrun', 'simctl', 'install', args.simulator, str(app)], env=env, check=True, capture_output=True, timeout=45)
    container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.simulator, bundle_id, 'data'], env=env, text=True).strip())
    report = container / 'Documents/results.json'
    report.unlink(missing_ok=True)
    subprocess.run(['xcrun', 'simctl', 'launch', args.simulator, bundle_id], env=env, check=True, capture_output=True, timeout=30)
    for _ in range(60):
        if report.exists(): break
        time.sleep(.25)
    if not report.exists(): raise RuntimeError('UIKit badge fixture did not produce a result')
    results = json.loads(report.read_text())
    (work / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps(results))
    assert all(results.values()), 'Production badge rendering regression'
finally:
    subprocess.run(['xcrun', 'simctl', 'terminate', args.simulator, bundle_id], env=env, capture_output=True, timeout=15)
    subprocess.run(['xcrun', 'simctl', 'uninstall', args.simulator, bundle_id], env=env, capture_output=True, timeout=30)
