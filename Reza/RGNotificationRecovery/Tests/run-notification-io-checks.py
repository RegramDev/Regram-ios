#!/usr/bin/env python3
"""Exercise real credential locking and the Objective-C notification key reader in isolated files."""
from pathlib import Path
import fcntl
import os
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[3]

def block(source, marker):
    start = source.index(marker)
    position = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[position] == '{') - (source[position] == '}')
        position += 1
    return source[start:position]

with tempfile.TemporaryDirectory(prefix='regram-notification-io-') as directory:
    work = Path(directory)
    sources = sorted((root/'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'))
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-emit-library', '-emit-module', '-module-name', 'SwiftSignalKit'] + [str(p) for p in sources] + ['-emit-module-path', str(work/'SwiftSignalKit.swiftmodule'), '-o', str(work/'libSwiftSignalKit.dylib')], check=True, capture_output=True)
    tests = work/'CredentialTests.swift'
    tests.write_text('''import Foundation
import LocalAuthentication
final class MemoryStorage: PasscodeStorage {
    var values: [String: Data] = [:]
    var reads = 0
    func read(_ account: String, context: LAContext?) throws -> Data? { reads += 1; return values[account] }
    func write(_ data: Data, account: String, biometric: Bool) throws { values[account] = data }
    func remove(_ account: String) throws { values.removeValue(forKey: account) }
}
@main enum Tests {
    static func main() throws {
        let storage = MemoryStorage()
        let store = PasscodeCredentialStore(storage: storage)
        store.configureLock(directory: CommandLine.arguments[1])
        if CommandLine.arguments[2] == "contended" {
            let start = ProcessInfo.processInfo.systemUptime
            do { _ = try store.managedReferenceForNotification(timeout: 0.08); fatalError("Lock contention must fail closed") }
            catch PasscodeError.unavailable { }
            precondition(ProcessInfo.processInfo.systemUptime - start < 0.7 && storage.reads == 0)
        } else {
            let unknown = try store.managedReferenceForNotification(timeout: 0.2)
            precondition(unknown == nil)
            try store.resetCredential(removingProtectedData: {})
            let cleared = try store.managedReferenceForNotification(timeout: 0.2)
            precondition(cleared != nil && cleared! == nil)
            _ = try store.managedReference() // The normal app path keeps its original API.
            let absent = PasscodeCredentialStore(storage: MemoryStorage())
            absent.configureLock(directory: CommandLine.arguments[1])
            do { _ = try absent.managedReferenceForNotification(expectsExistingCredential: true, timeout: 0.2); fatalError("Missing authority must not unlock a secured account") }
            catch PasscodeError.unavailable { }
        }
    }
}
''')
    production = [str(p) for p in (root/'submodules/PasscodeCore/Sources').glob('*.swift') if p.name != 'AccountManagerIntegration.swift']
    credential = work/'credentials'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-I', str(work), '-L', str(work), '-lSwiftSignalKit', '-Xlinker', '-rpath', '-Xlinker', str(work)] + production + [str(tests), '-o', str(credential)], check=True)
    with (work/'passcode-v1.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        subprocess.run([str(credential), str(work), 'contended'], check=True, timeout=3)
    subprocess.run([str(credential), str(work), 'ready'], check=True, timeout=3)
    key_method = block((root/'submodules/BuildConfig/Sources/BuildConfig.m').read_text(), '+ (DeviceSpecificEncryptionParameters * _Nullable)notificationEncryptionParameters:')
    objc = work/'KeyReader.m'
    objc.write_text('''#import <Foundation/Foundation.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
@interface DeviceSpecificEncryptionParameters : NSObject
@property(nonatomic,strong) NSData *key;
@property(nonatomic,strong) NSData *salt;
@end
@implementation DeviceSpecificEncryptionParameters
@end
@interface BuildConfig : NSObject
@end
@implementation BuildConfig
''' + key_method + '''
@end
int main(int argc, char **argv) { @autoreleasepool {
    NSString *path = [NSString stringWithUTF8String:argv[1]];
    DeviceSpecificEncryptionParameters *value = [BuildConfig notificationEncryptionParameters:path];
    if (value) {
        NSCAssert(value.key.length == 32 && value.salt.length == 16, @"Key reader preserves the format");
        printf("valid\\n");
    } else { printf("unavailable\\n"); }
} return 0; }
''')
    reader = work/'reader'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(objc), '-o', str(reader)], check=True)
    def read():
        return subprocess.check_output([str(reader), str(work)], text=True, timeout=2).strip()
    key = work/'.tempkey'
    assert read() == 'unavailable' and not key.exists()
    for data, expected in [(b'x'*32, 'unavailable'), (b'x'*7, 'unavailable'), (bytes(range(48)), 'valid')]:
        key.write_bytes(data)
        assert read() == expected and key.read_bytes() == data
    with (work/'.tempkey.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        start = time.monotonic()
        assert read() == 'unavailable' and time.monotonic() - start < 1
        assert key.read_bytes() == bytes(range(48))
    assert read() == 'valid'
    print('Notification I/O passed: real credential lock timeout, unknown/removal/privacy authority, read-only key recovery, preserved invalid/missing keys and cross-process contention.')
