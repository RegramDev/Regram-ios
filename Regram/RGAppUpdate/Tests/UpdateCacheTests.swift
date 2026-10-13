import Foundation
import CryptoKit

@main struct UpdateCacheTests {
    static func require(_ condition: @autoclosure () throws -> Bool) throws {
        let result = try condition()
        assert(result)
    }
    static func main() throws {
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--verify-restart" {
            let cache = RGUpdateCache(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
            let state = try cache.load(installedVersion: "13.0", installedBuild: "34598", signer: CommandLine.arguments[3])!
            try require(try Data(contentsOf: state.downloaded!) == Data((0..<32768).map { UInt8($0 % 251) }))
            try require(try Data(contentsOf: state.prepared!) == Data("synthetic signed archive".utf8))
            print("Separate process restored the complete downloaded and signed artifacts.")
            return
        }
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent("updates")
        let unrelated = parent.appendingPathComponent("unrelated")
        try Data("keep".utf8).write(to: unrelated)
        let bytes = Data((0..<32768).map { UInt8($0 % 251) })
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let release = RGUpdateRelease(version: "13.0", build: 34599, downloadURL: URL(string: "https://github.com/RegramDev/Regram-ios/releases/download/v13.0-b34599/Regram-13.0-b34599.ipa")!, sha256: digest, size: Int64(bytes.count), notes: "first notes")
        let certificate = Data("synthetic-private-certificate".utf8)
        let profiles = [Data("profile one".utf8), Data("profile two".utf8)]
        let signer = RGUpdateCache.signerFingerprint(certificate: certificate, profiles: profiles, bundleId: "com.example.Regram", installedBuild: "34598")
        assert(signer == RGUpdateCache.signerFingerprint(certificate: certificate, profiles: profiles.reversed(), bundleId: "com.example.Regram", installedBuild: "34598"))
        let rawInput = parent.appendingPathComponent("download.ipa")
        let signedInput = parent.appendingPathComponent("signed-input.ipa")
        let signedBytes = Data("synthetic signed archive".utf8)
        let cache = RGUpdateCache(directory: directory)
        try cache.select(release)
        // A partial or uncommitted download is never accepted as a verified source.
        try Data("partial".utf8).write(to: directory.appendingPathComponent("release.ipa"))
        try require(try cache.load(installedVersion: "13.0", installedBuild: "34598", signer: signer)?.downloaded == nil)
        try bytes.write(to: rawInput)
        let savedRaw = try cache.saveDownloaded(rawInput, release: release)
        assert(!FileManager.default.fileExists(atPath: rawInput.path))
        var restarted = RGUpdateCache(directory: directory)
        var state = try restarted.load(installedVersion: "13.0", installedBuild: "34598", signer: signer)!
        assert(state.downloaded == savedRaw && state.prepared == nil)
        try signedBytes.write(to: signedInput)
        let savedSigned = try restarted.saveSigned(signedInput, release: release, signer: signer)
        restarted = RGUpdateCache(directory: directory)
        state = try restarted.load(installedVersion: "13.0", installedBuild: "34598", signer: signer)!
        try require(try Data(contentsOf: state.downloaded!) == bytes)
        try require(try Data(contentsOf: state.prepared!) == signedBytes && state.prepared == savedSigned)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--verify-restart", directory.path, signer]
        try child.run(); child.waitUntilExit()
        assert(child.terminationStatus == 0, "Cache did not survive a separate process")
        // A temporarily unavailable Keychain does not destroy a signed artifact.
        state = try restarted.load(installedVersion: "13.0", installedBuild: "34598", signer: nil)!
        assert(state.downloaded != nil && state.prepared == nil)
        state = try restarted.load(installedVersion: "13.0", installedBuild: "34598", signer: signer)!
        assert(state.prepared != nil)
        let metadata = try String(contentsOf: directory.appendingPathComponent("update.json"), encoding: .utf8)
        assert(!metadata.contains("synthetic-private-certificate"))
        // Editing Release notes must not discard either artifact.
        let edited = RGUpdateRelease(version: release.version, build: release.build, downloadURL: release.downloadURL, sha256: release.sha256, size: release.size, notes: "edited notes")
        try restarted.select(edited)
        state = try restarted.load(installedVersion: "13.0", installedBuild: "34598", signer: signer)!
        assert(state.downloaded != nil && state.prepared != nil && state.release.notes == "edited notes")
        // Changing signing material retains the original download for another signature.
        state = try restarted.load(installedVersion: "13.0", installedBuild: "34598", signer: "changed signer")!
        assert(state.downloaded != nil && state.prepared == nil)
        try signedBytes.write(to: signedInput)
        _ = try restarted.saveSigned(signedInput, release: edited, signer: signer)
        try Data("corrupt".utf8).write(to: savedSigned)
        state = try restarted.load(installedVersion: "13.0", installedBuild: "34598", signer: signer)!
        assert(state.downloaded != nil && state.prepared == nil)
        try signedBytes.write(to: signedInput)
        _ = try restarted.saveSigned(signedInput, release: edited, signer: signer)
        // Same-size source corruption is detected by SHA-256; a valid signed copy survives.
        try Data(repeating: 0, count: bytes.count).write(to: savedRaw)
        state = try restarted.load(installedVersion: "13.0", installedBuild: "34598", signer: signer)!
        assert(state.downloaded == nil && state.prepared != nil)
        // An already installed build removes only the dedicated update cache.
        try require(try restarted.load(installedVersion: "13.0", installedBuild: "34599", signer: signer) == nil)
        assert(!FileManager.default.fileExists(atPath: directory.path))
        try require(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
        try restarted.select(release)
        try bytes.write(to: rawInput)
        _ = try restarted.saveDownloaded(rawInput, release: release)
        let replacement = RGUpdateRelease(version: "13.0", build: 34600, downloadURL: URL(string: "https://github.com/RegramDev/Regram-ios/releases/download/v13.0-b34600/Regram-13.0-b34600.ipa")!, sha256: digest, size: release.size, notes: "next release")
        try restarted.select(replacement)
        state = try restarted.load(installedVersion: "13.0", installedBuild: "34598", signer: signer)!
        assert(state.release.build == 34600 && state.downloaded == nil && state.prepared == nil)
        try Data("broken metadata".utf8).write(to: directory.appendingPathComponent("update.json"))
        try require(try restarted.load(installedVersion: "13.0", installedBuild: "34598", signer: signer) == nil)
        try require(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
        print("Update cache checks passed: restart reuse, independent raw/signed persistence, notes-only edits, signing changes, checksums, incomplete files, obsolete builds and scoped cleanup.")
    }
}
