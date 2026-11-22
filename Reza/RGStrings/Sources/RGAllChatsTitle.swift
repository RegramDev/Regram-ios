import Foundation

/// Language packs sometimes give the short and full folder labels the same text.
/// Keep the picker preview and both tab layouts in sync when that happens.
public func rgAllChatsTitle(shortTitle: String, longTitle: String, useShortTitle: Bool, languageCode: String) -> String {
    let short = shortTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let long = longTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let selected = useShortTitle ? short : long
    if !selected.isEmpty && short != long {
        return selected
    }
    return (useShortTitle ? "Settings.Folders.AllChatsTitle.shortText" : "Settings.Folders.AllChatsTitle.longText").i18n(languageCode)
}
