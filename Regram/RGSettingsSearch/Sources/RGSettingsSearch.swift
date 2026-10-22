// Compiled into SettingsUI to share its native result rows without importing RGProUI.
import AccountContext
import RGStrings
import TelegramPresentationData

func rgSettingsSearchableItems(context: AccountContext) -> [SettingsSearchableItem] {
    let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
    let language = RGLocalizationManager.shared.preferredLocale(primary: strings.primaryComponent.languageCode, secondary: strings.secondaryComponent?.languageCode)
    let title = "Settings.Pro.Title".i18n(language)
    var items = [SettingsSearchableItem(id: "regram", title: title, alternate: ["Regram Pro"], icon: .regram, present: { context, _, present in
        present(.push, context.sharedContext.makeRGProController(context: context))
    })]
    items.append(contentsOf: RGSettingsCatalog.entries.map { entry in
        let text = RGSettingsCatalog.searchableText(for: entry, language: language)
        return SettingsSearchableItem(id: "regram/" + entry.id, title: entry.titleKey.i18n(language), icon: .regram, breadcrumbs: [title, entry.pageTitleKey.i18n(language)], matchesQuery: { query in
            RGSettingsSearchQuery(query, language: language).matches(text)
        }, present: { context, _, present in
            if let controller = context.sharedContext.makeRGSettingsController(context: context, page: entry.destination.page, item: entry.destination.item) {
                present(.push, controller)
            }
        })
    })
    return items
}
