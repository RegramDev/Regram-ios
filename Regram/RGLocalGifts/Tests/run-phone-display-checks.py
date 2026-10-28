#!/usr/bin/env python3
"""Exercise local phone grouping and account gates without a Telegram account."""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
module = ROOT / 'Regram/RGLocalGifts/Sources'
projection = (module / 'LocalGifts.swift').read_text()
account_key = projection.split('public func rgLocalGiftsAccount(', 1)[1].split('\n}\n', 1)[0]
display = projection.split('public func rgFormattedDisplayedPhone(', 1)[1].split('\n}\n', 1)[0]
local_format = (module / 'LocalPhoneNumber.swift').read_text().replace('import PhoneNumberFormat\n', '').replace('import AccountContext\n', '')
native = (ROOT / 'submodules/PhoneNumberFormat/Sources/PhoneNumbers.swift').read_text()
mask = native.split('public func formatPhoneNumberToMask(', 1)[1].split('\n}\n', 1)[0]
countries = (ROOT / 'submodules/TelegramUI/Resources/PhoneCountries.txt').read_text()
assert re.search(r'^888;FT;XXXX XXXX;', countries, re.MULTILINE), 'Use Telegram\'s Fragment pattern'

fixture = '''
import Foundation
struct EnginePeer { typealias Id = Int64 }
extension Int64 { func toInt64() -> Int64 { self } }
struct Account { let peerId: EnginePeer.Id; let testingEnvironment: Bool }
struct FixtureCountries {
    func with<T>(_ f: (Int) -> T) -> T { f(0) }
}
struct AccountContext {
    let account: Account
    var currentCountriesConfiguration: FixtureCountries { FixtureCountries() }
}
struct CountryCode { let code: String }
// Country lookup is an unchanged Telegram dependency; fixtures exercise how the
// production editor splits its result, including Fragment and an unknown prefix.
func lookupCountryIdByNumber(_ number: String, configuration: Int) -> (String, CountryCode)? {
    for code in ["1", "44", "86"] where number.hasPrefix(code) { return ("fixture", CountryCode(code: code)) }
    return nil
}
let suite = "Regram.PhoneDisplay.Tests." + UUID().uuidString
let testDefaults = UserDefaults(suiteName: suite)!
let testStore = RGLocalGiftsStore(defaults: testDefaults, notifications: NotificationCenter())
// The adapter records delegation to the unchanged Telegram context formatter.
var nativeCalls: [String] = []
func formatPhoneNumber(context: AccountContext, number: String) -> String {
    nativeCalls.append(number)
    return "native:" + number
}
ACCOUNT_KEY
MASK
LOCAL_FORMAT
DISPLAY
@main enum Tests {
    static func main() throws {
        let live = AccountContext(account: Account(peerId: 101, testingEnvironment: false))
        let other = AccountContext(account: Account(peerId: 202, testingEnvironment: false))
        let test = AccountContext(account: Account(peerId: 101, testingEnvironment: true))
        let real = "12025550123"
        defer { testDefaults.removePersistentDomain(forName: suite) }
        let store = testStore
        for (number, code, national) in [("88812345678", "888", "12345678"), ("12025550123", "1", "2025550123"), ("442079460123", "44", "2079460123"), ("8613812345678", "86", "13812345678"), ("99912345", "", "99912345"), ("", "", "")] {
            let parts = rgLocalPhoneParts(context: live, number: number)
            precondition(parts.code == code && parts.number == national)
            precondition(parts.code + parts.number == number, "Editing an old number must preserve every digit")
        }
        precondition(rgFormattedDisplayedPhone(context: live, peerId: 101, phone: real) == "native:" + real)
        precondition(rgFormattedDisplayedPhone(context: live, peerId: 101, phone: nil) == nil)
        // Production normalization, persistence and mask insertion, including partial
        // and oversized simulated numbers: separators must never drop digits.
        for (input, expected) in [
            ("+888 1234 5678", "+888 1234 5678"),
            ("+888 1234 567", "+888 1234 567"),
            ("88812", "+888 12"),
            ("88812345678901234567", "+888 1234 5678901234567")
        ] {
            _ = try store.setPhone(account: rgLocalGiftsAccount(live), enabled: true, number: input).get()
            nativeCalls.removeAll()
            let output = rgFormattedDisplayedPhone(context: live, peerId: 101, phone: real)
            precondition(output == expected, "Incorrect Fragment grouping: " + (output ?? "nil"))
            precondition(nativeCalls.isEmpty, "Do not reformat Fragment using an unrelated or stale mask")
            precondition(output!.filter(\\.isNumber) == store.state(account: rgLocalGiftsAccount(live)).phoneNumber)
        }
        precondition(rgFormattedDisplayedPhone(context: live, peerId: 202, phone: real) == "native:" + real)
        precondition(rgFormattedDisplayedPhone(context: other, peerId: 202, phone: real) == "native:" + real)
        precondition(rgFormattedDisplayedPhone(context: test, peerId: 101, phone: real) == "native:" + real)
        // Other country codes continue through Telegram's native formatter intact.
        for number in ["12025550123", "442079460123", "8613812345678"] {
            _ = try store.setPhone(account: rgLocalGiftsAccount(live), enabled: true, number: number).get()
            precondition(rgFormattedDisplayedPhone(context: live, peerId: 101, phone: real) == "native:" + number)
            precondition(nativeCalls.last == number)
        }
        _ = try store.setPhone(account: rgLocalGiftsAccount(live), enabled: false, number: "88812345678").get()
        precondition(rgFormattedDisplayedPhone(context: live, peerId: 101, phone: real) == "native:" + real)
        print("Local phone grouping: Telegram Fragment mask, digit preservation, native country delegation, account/environment isolation and disabling passed")
    }
}
'''
for placeholder, value in {
    'ACCOUNT_KEY': 'public func rgLocalGiftsAccount(' + account_key + '\n}',
    'MASK': 'public func formatPhoneNumberToMask(' + mask + '\n}',
    'LOCAL_FORMAT': local_format,
    'DISPLAY': 'public func rgFormattedDisplayedPhone(' + display + '\n}',
}.items():
    fixture = fixture.replace(placeholder, value)
fixture = fixture.replace('public func rgLocalGiftsAccount', 'func rgLocalGiftsAccount')
fixture = fixture.replace('public func rgFormattedDisplayedPhone', 'func rgFormattedDisplayedPhone')
fixture = fixture.replace('RGLocalGiftsStore.shared', 'testStore')
with tempfile.TemporaryDirectory(prefix='regram-local-phone-') as temporary:
    work = Path(temporary)
    source = work / 'PhoneDisplayTests.swift'
    source.write_text(fixture)
    binary = work / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors',
                    str(ROOT / 'Regram/RGSimpleSettings/Sources/LocalGifts.swift'),
                    str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

peer_info = ROOT / 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources'
for name in ['PeerInfoHeaderNode.swift', 'PeerInfoProfileItems.swift', 'PeerInfoSettingsItems.swift']:
    source = (peer_info / name).read_text()
    assert 'rgFormattedDisplayedPhone(' in source, name
    assert 'rgLocalDisplayedPhone(' not in source, name
assert 'self.hidePhoneInSettings' in (peer_info / 'PeerInfoHeaderNode.swift').read_text()
assert 'interaction.openPhone(phone, node,' in (peer_info / 'PeerInfoProfileItems.swift').read_text()
print('Header, edit and profile use the same display formatter; native phone actions remain attached to the real number (source guards)')
