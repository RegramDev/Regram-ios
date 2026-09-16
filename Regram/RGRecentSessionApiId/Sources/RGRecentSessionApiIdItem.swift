import UIKit
import Display
import ComponentFlow
import TelegramPresentationData
import MultilineTextComponent
import ListActionItemComponent
import UndoUI

func rgRecentSessionApiIdItem(
    apiIdString: String,
    theme: PresentationTheme,
    presentationData: PresentationData,
    strings: PresentationStrings,
    controller: RecentSessionScreen?
) -> AnyComponentWithIdentity<Empty> {
    let rgApiIdTextAttribute = NSAttributedString.Key(rawValue: "SGRecentSessionApiIdAttribute")
    let rgApiIdText = NSMutableAttributedString(
        string: apiIdString,
        font: Font.regular(presentationData.listsFontSize.itemListBaseFontSize),
        textColor: theme.list.itemSecondaryTextColor
    )
    rgApiIdText.addAttribute(rgApiIdTextAttribute, value: true, range: NSRange(location: 0, length: rgApiIdText.length))

    return AnyComponentWithIdentity(id: "api_id", component: AnyComponent(
        ListActionItemComponent(
            theme: theme,
            style: .glass,
            title: AnyComponent(MultilineTextComponent(
                text: .plain(NSAttributedString(
                    string: "api_id",
                    font: Font.regular(17.0),
                    textColor: theme.list.itemPrimaryTextColor
                )),
                maximumNumberOfLines: 1
            )),
            accessory: .custom(ListActionItemComponent.CustomAccessory(
                component: AnyComponentWithIdentity(
                    id: "info",
                    component: AnyComponent(MultilineTextComponent(
                        text: .plain(rgApiIdText),
                        maximumNumberOfLines: 1,
                        highlightColor: theme.list.itemAccentColor.withMultipliedAlpha(0.15),
                        highlightAction: { attributes in
                            if let _ = attributes[rgApiIdTextAttribute] {
                                return rgApiIdTextAttribute
                            }
                            return nil
                        },
                        longTapAction: { [weak controller] attributes, _ in
                            guard let _ = attributes[rgApiIdTextAttribute] else {
                                return
                            }
                            UIPasteboard.general.string = apiIdString
                            controller?.present(UndoOverlayController(
                                presentationData: presentationData,
                                content: .copy(text: strings.Conversation_TextCopied),
                                elevatedLayout: false,
                                animateInAsReplacement: false,
                                action: { _ in return false }
                            ), in: .current)
                        }
                    ))
                ),
                insets: UIEdgeInsets(top: 0.0, left: 8.0, bottom: 0.0, right: 14.0),
                isInteractive: true
            )),
            action: nil
        )
    ))
}
