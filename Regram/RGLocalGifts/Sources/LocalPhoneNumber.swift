// MARK: Regram — display formatting only; never changes the account's phone number.
import PhoneNumberFormat
import AccountContext

func rgLocalPhoneParts(context: AccountContext, number: String) -> (code: String, number: String) {
    let code: String
    if number.hasPrefix("888") {
        code = "888"
    } else {
        code = lookupCountryIdByNumber(number, configuration: context.currentCountriesConfiguration.with { $0 })?.1.code ?? ""
    }
    return (code, String(number.dropFirst(code.count)))
}

func rgFormatLocalPhoneNumber(_ number: String, standardFormat: (String) -> String) -> String {
    // Telegram's PhoneCountries.txt defines Fragment as +888 XXXX XXXX. Use that
    // grouping for local numbers even when cached country patterns differ.
    if number.hasPrefix("888") {
        return "+" + formatPhoneNumberToMask(number, mask: "XXX XXXX XXXX")
    }
    return standardFormat(number)
}
