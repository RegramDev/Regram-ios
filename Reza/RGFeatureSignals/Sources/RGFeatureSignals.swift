// MARK: Regram
import Foundation
import RGSimpleSettings
import SwiftSignalKit

public func rgFeatureBoolSignal(_ rawKey: String, defaultValue: Bool) -> Signal<Bool, NoError> {
    let key = RGFeaturePreferences.key(rawKey)
    func current() -> Bool { RGFeaturePreferences.bool(key, default: defaultValue) }
    return (Signal<Bool, NoError>.single(current()) |> then(Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: nil) { _ in subscriber.putNext(current()) }
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    })) |> distinctUntilChanged
}
public func rgFeatureStringSignal(_ rawKey: String, defaultValue: String) -> Signal<String, NoError> {
    let key = RGFeaturePreferences.key(rawKey)
    func current() -> String { RGFeaturePreferences.string(key, default: defaultValue) }
    return (Signal<String, NoError>.single(current()) |> then(Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: nil) { _ in subscriber.putNext(current()) }
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    })) |> distinctUntilChanged
}

public func rgFeatureBottomBarSettingsSignal() -> Signal<RGBottomBarSettings, NoError> {
    return (Signal<RGBottomBarSettings, NoError>.single(RGSimpleSettings.shared.bottomBarSettings) |> then(Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: nil) { _ in subscriber.putNext(RGSimpleSettings.shared.bottomBarSettings) }
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    })) |> distinctUntilChanged
}
