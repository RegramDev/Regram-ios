// MARK: Regram — display formatting only; never changes the account's phone number.
import PhoneNumberFormat

func rgFormatLocalPhoneNumber(_ number: String, standardFormat: (String) -> String) -> String {
    // Telegram's PhoneCountries.txt defines Fragment as +888 XXXX XXXX. Use that
    // grouping for local numbers even when cached country patterns differ.
    if number.hasPrefix("888") {
        return "+" + formatPhoneNumberToMask(number, mask: "XXX XXXX XXXX")
    }
    return standardFormat(number)
}
