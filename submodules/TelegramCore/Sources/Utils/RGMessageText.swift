// MARK: Regram — one text projection for message tools; sending keeps the original rich payload.
import Postbox

public extension InstantPage {
    func rgTextContent(hideSpoilers: Bool = false) -> String {
        func text(_ value: RichText) -> String {
            guard hideSpoilers else { return value.plainText }
            switch value {
            case .textSpoiler: return "•••"
            case let .bold(t), let .italic(t), let .underline(t), let .strikethrough(t), let .fixed(t),
                 let .subscript(t), let .superscript(t), let .marked(t), let .textAutoEmail(t),
                 let .textAutoPhone(t), let .textAutoUrl(t), let .textBankCard(t), let .textTonAddress(t),
                 let .textBotCommand(t), let .textCashtag(t), let .textHashtag(t), let .textMention(t): return text(t)
            case let .url(t, _, _), let .textDate(t, _, _): return text(t)
            case let .email(t, _), let .phone(t, _), let .anchor(t, _), let .textMentionName(t, _): return text(t)
            case let .concat(items): return items.map(text).joined()
            case let .textButton(button): return text(button.text)
            default: return value.plainText
            }
        }
        func joined(_ parts: [String], separator: String = "\n") -> String {
            parts.filter { !$0.isEmpty }.joined(separator: separator)
        }
        func caption(_ value: InstantPageCaption) -> String { joined([text(value.text), text(value.credit)]) }
        func blocks(_ values: [InstantPageBlock]) -> String {
            joined(values.map { block in
                switch block {
                case let .title(t), let .subtitle(t), let .header(t), let .subheader(t), let .paragraph(t),
                     let .footer(t), let .kicker(t), let .thinking(t): return text(t)
                case let .heading(t, _), let .authorDate(t, _), let .preformatted(t, _): return text(t)
                case let .formula(latex): return latex
                case let .list(items, _):
                    return joined(items.map { item in
                        switch item {
                        case let .text(t, _, _): return text(t)
                        case let .blocks(items, _, _): return blocks(items)
                        case .unknown: return ""
                        }
                    })
                case let .blockQuote(items, c, _): return joined([blocks(items), text(c)])
                case let .pullQuote(t, c): return joined([text(t), text(c)])
                case let .image(_, c, _, _, spoiler), let .video(_, c, _, _, spoiler):
                    return hideSpoilers && spoiler ? "•••" : caption(c)
                case let .audio(_, c), let .document(_, c), let .webEmbed(_, _, _, c, _, _, _), let .map(_, _, _, _, c): return caption(c)
                case let .postEmbed(_, _, _, author, _, items, c): return joined([author, blocks(items), caption(c)])
                case let .collage(items, c), let .slideshow(items, c): return joined([blocks(items), caption(c)])
                case let .cover(item): return blocks([item])
                case let .buttonRow(_, buttons): return joined(buttons.map { text($0.text) }, separator: "\t")
                case let .table(title, rows, _, _, _):
                    return joined([text(title)] + rows.map { row in row.cells.map { $0.text.map(text) ?? "" }.joined(separator: "\t") })
                case let .details(title, items, _): return joined([text(title), blocks(items)])
                case let .relatedArticles(title, _): return text(title)
                case .unsupported, .divider, .anchor, .channelBanner: return ""
                }
            })
        }
        return blocks(self.blocks)
    }
}

public func rgMessageText(text: String, attributes: [MessageAttribute], hideSpoilers: Bool = false) -> String {
    guard let rich = attributes.first(where: { $0 is RichTextMessageAttribute }) as? RichTextMessageAttribute else { return text }
    return (rich.fullInstantPage ?? rich.instantPage).rgTextContent(hideSpoilers: hideSpoilers)
}

public extension Message {
    var rgTextContent: String { rgMessageText(text: self.text, attributes: self.attributes) }
    var rgPreviewText: String { rgMessageText(text: self.text, attributes: self.attributes, hideSpoilers: true) }
}

public extension EngineMessage {
    var rgTextContent: String { rgMessageText(text: self.text, attributes: self.attributes) }
    var rgPreviewText: String { rgMessageText(text: self.text, attributes: self.attributes, hideSpoilers: true) }
}
