import Foundation

@main struct CredentialFileTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = Data([0x30, 0x82, 0x01, 0x00])
        for name in ["certificate.p12", "certificate.P12", "证书.pfx", "profile.mobileprovision"] {
            let url = directory.appendingPathComponent(name)
            try contents.write(to: url)
            let kind: RGUpdateCredentialFileKind = name.hasSuffix("mobileprovision") ? .profiles : .certificate
            let read = try RGUpdateCredentialFile.read(url: url, kind: kind)
            assert(read == contents)
        }
        let wrong = directory.appendingPathComponent("certificate.txt")
        try contents.write(to: wrong)
        do { _ = try RGUpdateCredentialFile.read(url: wrong, kind: .certificate); fatalError("Wrong type accepted") } catch RGUpdateCredentialFileError.invalidType {}
        let empty = directory.appendingPathComponent("empty.p12")
        try Data().write(to: empty)
        do { _ = try RGUpdateCredentialFile.read(url: empty, kind: .certificate); fatalError("Empty file accepted") } catch RGUpdateCredentialFileError.empty {}
        let large = directory.appendingPathComponent("large.p12")
        try Data(repeating: 1, count: RGUpdateCredentialFile.maximumBytes + 1).write(to: large)
        do { _ = try RGUpdateCredentialFile.read(url: large, kind: .certificate); fatalError("Oversize file accepted") } catch RGUpdateCredentialFileError.tooLarge {}
        let missing = directory.appendingPathComponent("missing.p12")
        do { _ = try RGUpdateCredentialFile.read(url: missing, kind: .certificate); fatalError("Missing file accepted") } catch RGUpdateCredentialFileError.unreadable {}
        print("Credential file checks passed: P12/PFX, profiles, mixed-case extensions, Unicode, bounded reads and explicit failures.")
    }
}
