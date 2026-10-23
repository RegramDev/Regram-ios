import Foundation

@main enum LaunchResetTests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
    static func main() {
        let suite = "Regram.Reset.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "rg_full_wipe")
        defaults.set(true, forKey: "rg_db_hard_reset")
        let firstLaunch = RGLaunchResetCoordinator(defaults: defaults)
        expect(firstLaunch.request == .fullWipe, "A full wipe must take priority without opening the database")
        expect(firstLaunch.claimPresentation(sceneConnected: false, active: true) == nil, "The pre-Scene launch must not present")
        expect(firstLaunch.claimPresentation(sceneConnected: true, active: false) == nil, "Scene connection alone is too early")
        expect(defaults.bool(forKey: "rg_full_wipe"), "Waiting for a scene must not consume the reset request")
        let restarted = RGLaunchResetCoordinator(defaults: defaults)
        expect(restarted.claimPresentation(sceneConnected: true, active: true) == .fullWipe, "Restarting before confirmation must retain a usable request")
        expect(restarted.claimPresentation(sceneConnected: true, active: true) == nil, "Foreground callbacks must not duplicate confirmation")
        expect(defaults.bool(forKey: "rg_full_wipe"), "Displaying confirmation must not authorize deletion")
        RGLaunchResetCoordinator.resolve(.fullWipe, defaults: defaults)
        expect(RGLaunchResetCoordinator(defaults: defaults).request == .database, "Resolving a request must leave other explicit requests intact")
        RGLaunchResetCoordinator.resolve(.database, defaults: defaults)
        expect(RGLaunchResetCoordinator(defaults: defaults).request == nil, "Cancel/confirm must resolve the corresponding request")
        defaults.set(true, forKey: "sg_full_wipe")
        expect(RGLaunchResetCoordinator(defaults: defaults).request == nil, "A saved false value must override a legacy true value")
        defaults.removeObject(forKey: "rg_full_wipe")
        expect(RGLaunchResetCoordinator(defaults: defaults).request == nil, "Swiftgram reset keys must not arm a Regram wipe")
        RGLaunchResetCoordinator.resolve(.fullWipe, defaults: defaults)
        expect(defaults.bool(forKey: "sg_full_wipe") && RGLaunchResetCoordinator(defaults: defaults).request == nil, "Swiftgram state must remain ignored")
        print("Startup reset checks passed; only an isolated preference suite was used, no data was erased.")
    }
}
