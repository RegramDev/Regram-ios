import Foundation

@main enum UpdatePromptTests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
    static func main() {
        let release = RGUpdateRelease(version: "13.0", build: 34606, downloadURL: URL(string: "https://github.com/RegramDev/Regram-ios/releases/download/v13.0-b34606/Regram-13.0-b34606.ipa")!, sha256: String(repeating: "a", count: 64), size: 100, notes: "")
        let available = RGUpdatePrompt(release: release, kind: .available)
        let ready = RGUpdatePrompt(release: release, kind: .ready)
        var policy = RGUpdatePromptPolicy()
        expect(!policy.claim(available, enabled: false, busy: false, currentRelease: release, currentKind: .available), "Disabled automatic checking must never prompt")
        expect(!policy.claim(available, enabled: true, busy: true, currentRelease: release, currentKind: .available), "Downloading must not display discovery prompts")
        expect(policy.claim(available, enabled: true, busy: false, currentRelease: release, currentKind: .available), "Discovery should prompt once when available")
        expect(!policy.claim(available, enabled: true, busy: false, currentRelease: release, currentKind: .available), "Multiple accounts and foreground callbacks must share deduplication")
        expect(!policy.claim(available, enabled: true, busy: false, currentRelease: release, currentKind: .ready), "A delayed discovery event must not appear after the package is ready")
        expect(policy.claim(ready, enabled: true, busy: false, currentRelease: release, currentKind: .ready), "Ready must offer installation after discovery was consumed")
        expect(!policy.claim(ready, enabled: true, busy: false, currentRelease: release, currentKind: .ready), "Returning from the installer must not duplicate the installation prompt")
        var freshSession = RGUpdatePromptPolicy()
        expect(!freshSession.claim(available, enabled: true, busy: false, currentRelease: release, currentKind: .ready), "Restored ready packages must never be classified as discovery")
        expect(freshSession.claim(ready, enabled: true, busy: false, currentRelease: release, currentKind: .ready), "A restored package should remain installable on the next launch")
        expect(!freshSession.claim(available, enabled: true, busy: false, currentRelease: release, currentKind: nil), "Installation handoff must not reopen discovery")
        let replacement = RGUpdateRelease(version: release.version, build: release.build, downloadURL: release.downloadURL, sha256: String(repeating: "b", count: 64), size: release.size, notes: "")
        expect(!policy.claim(ready, enabled: true, busy: false, currentRelease: replacement, currentKind: .ready), "Stale prompts must not install a replaced asset")
        expect(policy.claim(RGUpdatePrompt(release: replacement, kind: .available), enabled: true, busy: false, currentRelease: replacement, currentKind: .available), "A replacement asset has its own prompt identity")
        let failed = RGUpdatePrompt(release: replacement, kind: .failed("AppUpdate.NetworkError"))
        expect(policy.claim(failed, enabled: true, busy: false, currentRelease: replacement, currentKind: failed.kind), "An accepted silent update must expose failure recovery")
        var installationPolicy = RGUpdatePromptPolicy()
        expect(installationPolicy.claim(ready, enabled: true, busy: false, currentRelease: release, currentKind: .ready), "Restored updates must offer direct installation")
        let rejected = RGUpdatePrompt(release: release, kind: .failed("AppUpdate.InstallationRejected"))
        expect(installationPolicy.claim(rejected, enabled: true, busy: false, currentRelease: release, currentKind: rejected.kind), "Installer failure must remain visible after a ready prompt")
        expect(!installationPolicy.claim(ready, enabled: true, busy: false, currentRelease: release, currentKind: rejected.kind), "An installation failure must not reopen the installation prompt")
        print("Update prompt checks passed: discovery, ready restoration, stale/busy events, shared deduplication, and failure recovery.")
    }
}
