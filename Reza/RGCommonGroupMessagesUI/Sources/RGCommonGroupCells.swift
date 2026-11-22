// MARK: Regram — readable, reusable rows for common-group search and its group picker.
import Foundation
import UIKit
import Display
import AvatarNode
import AccountContext
import TelegramCore
import TelegramPresentationData
import LocalizedPeerData

// Keep each image subscription attached to its peer across progress and return transitions.
private final class RGCommonGroupAvatarView: UIView {
    private let avatar: AvatarNode
    private let size: CGFloat
    private var peer: EnginePeer?
    private var theme: PresentationTheme?
    private var hasPeer = false

    init(size: CGFloat) {
        self.size = size
        self.avatar = AvatarNode(font: avatarPlaceholderFont(size: floor(size * 0.4)))
        super.init(frame: .zero)
        addSubview(avatar.view)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size)])
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); avatar.frame = bounds }
    func update(context: AccountContext, peer: EnginePeer?, data: PresentationData) {
        guard !hasPeer || self.peer != peer || theme !== data.theme else { return }
        hasPeer = true; self.peer = peer; theme = data.theme
        avatar.setPeer(context: context, theme: data.theme, peer: peer, synchronousLoad: true, displayDimensions: CGSize(width: size, height: size))
    }
}

final class RGCommonGroupHeaderView: UIView {
    private let avatar = RGCommonGroupAvatarView(size: 48.0)
    private let nameLabel = UILabel()
    private let summaryLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let status = UIStackView(arrangedSubviews: [spinner, summaryLabel])
        status.spacing = 6.0; status.alignment = .center
        let personText = UIStackView(arrangedSubviews: [nameLabel, status])
        personText.axis = .vertical; personText.spacing = 5.0
        let person = UIStackView(arrangedSubviews: [avatar, personText])
        person.spacing = 12.0; person.alignment = .center
        person.translatesAutoresizingMaskIntoConstraints = false
        addSubview(person)
        NSLayoutConstraint.activate([
            person.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20.0),
            person.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20.0),
            person.topAnchor.constraint(equalTo: topAnchor, constant: 16.0),
            person.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8.0)
        ])
        nameLabel.numberOfLines = 2; summaryLabel.numberOfLines = 2
        spinner.hidesWhenStopped = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(context: AccountContext, author: EnginePeer, summary: String, loading: Bool, data: PresentationData) {
        avatar.update(context: context, peer: author, data: data)
        nameLabel.text = author.displayTitle(strings: data.strings, displayOrder: data.nameDisplayOrder)
        nameLabel.font = Font.semibold(max(18.0, data.listsFontSize.baseDisplaySize))
        nameLabel.textColor = data.theme.list.itemPrimaryTextColor
        summaryLabel.text = summary
        summaryLabel.font = Font.regular(max(13.0, data.listsFontSize.baseDisplaySize - 3.0))
        summaryLabel.textColor = data.theme.list.itemSecondaryTextColor
        spinner.color = data.theme.list.itemAccentColor
        if loading { spinner.startAnimating() } else { spinner.stopAnimating() }
    }
}

final class RGCommonGroupPeerCell: UITableViewCell {
    private let avatarContainer = RGCommonGroupAvatarView(size: 44.0)
    private let nameLabel = UILabel()
    private let summaryLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        let text = UIStackView(arrangedSubviews: [nameLabel, summaryLabel])
        text.axis = .vertical; text.spacing = 4.0
        text.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarContainer); contentView.addSubview(text)
        nameLabel.numberOfLines = 2; summaryLabel.numberOfLines = 0
        NSLayoutConstraint.activate([
            avatarContainer.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: avatarContainer.trailingAnchor, constant: 12.0),
            text.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            text.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14.0),
            text.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14.0),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72.0)
        ])
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(context: AccountContext, peer: EnginePeer?, title: String, summary: String?, data: PresentationData, selected: Bool = false, selectable: Bool = true) {
        avatarContainer.update(context: context, peer: peer, data: data)
        nameLabel.text = title; summaryLabel.text = summary; summaryLabel.isHidden = summary?.isEmpty != false
        nameLabel.font = Font.semibold(data.listsFontSize.baseDisplaySize)
        summaryLabel.font = Font.regular(max(13.0, data.listsFontSize.baseDisplaySize - 3.0))
        nameLabel.textColor = data.theme.list.itemPrimaryTextColor
        summaryLabel.textColor = data.theme.list.itemSecondaryTextColor
        backgroundColor = data.theme.list.itemBlocksBackgroundColor
        let selection = selectedBackgroundView ?? UIView()
        selection.backgroundColor = data.theme.list.itemHighlightedBackgroundColor
        selectedBackgroundView = selection
        tintColor = data.theme.list.itemAccentColor
        accessoryType = selected ? .checkmark : .none
        selectionStyle = selectable ? .default : .none
        accessibilityLabel = [title, summary].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = selectable ? (selected ? [.button, .selected] : .button) : .staticText
        separatorInset = UIEdgeInsets(top: 0, left: 72.0, bottom: 0, right: 0)
    }
}

final class RGCommonGroupMessageCell: UITableViewCell {
    private let avatarContainer = RGCommonGroupAvatarView(size: 36.0)
    private let groupLabel = UILabel()
    private let dateLabel = UILabel()
    private let bodyLabel = UILabel()
    private let heading = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        heading.addArrangedSubview(groupLabel); heading.addArrangedSubview(dateLabel)
        heading.spacing = 8.0; heading.alignment = .firstBaseline
        groupLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        groupLabel.lineBreakMode = .byTruncatingTail
        let text = UIStackView(arrangedSubviews: [heading, bodyLabel])
        text.axis = .vertical; text.spacing = 7.0
        text.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.numberOfLines = 4; bodyLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(avatarContainer); contentView.addSubview(text)
        NSLayoutConstraint.activate([
            avatarContainer.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16.0),
            text.leadingAnchor.constraint(equalTo: avatarContainer.trailingAnchor, constant: 10.0),
            text.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            text.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16.0),
            text.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16.0),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 78.0)
        ])
        isAccessibilityElement = true; accessibilityTraits = .button
        separatorInset = UIEdgeInsets(top: 0, left: 62.0, bottom: 0, right: 0)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(context: AccountContext, group: EnginePeer?, title: String, date: String, fullDate: String, body: String, openHint: String, availableWidth: CGFloat, data: PresentationData) {
        avatarContainer.update(context: context, peer: group, data: data)
        groupLabel.text = title; dateLabel.text = date; bodyLabel.text = body
        groupLabel.font = Font.semibold(max(14.0, data.listsFontSize.baseDisplaySize - 2.0))
        dateLabel.font = Font.regular(max(12.0, data.listsFontSize.baseDisplaySize - 5.0))
        bodyLabel.font = Font.regular(data.listsFontSize.baseDisplaySize)
        // Stack metadata before self-sizing, so long dates never squeeze out the group name.
        let stacked = availableWidth < 390.0 || data.listsFontSize.baseDisplaySize > 19.0
        heading.axis = stacked ? .vertical : .horizontal
        heading.alignment = stacked ? .leading : .firstBaseline
        heading.spacing = stacked ? 3.0 : 8.0
        groupLabel.numberOfLines = stacked ? 2 : 1
        groupLabel.textColor = data.theme.list.itemPrimaryTextColor
        dateLabel.textColor = data.theme.list.itemSecondaryTextColor
        bodyLabel.textColor = data.theme.list.itemPrimaryTextColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3.0; paragraph.lineBreakMode = .byTruncatingTail
        bodyLabel.attributedText = NSAttributedString(string: body, attributes: [.font: Font.regular(data.listsFontSize.baseDisplaySize), .foregroundColor: data.theme.list.itemPrimaryTextColor, .paragraphStyle: paragraph])
        backgroundColor = data.theme.list.itemBlocksBackgroundColor
        let selection = selectedBackgroundView ?? UIView()
        selection.backgroundColor = data.theme.list.itemHighlightedBackgroundColor
        selectedBackgroundView = selection
        accessoryType = .disclosureIndicator
        accessibilityLabel = [title, fullDate, body].joined(separator: ", ")
        accessibilityHint = openHint
    }
}

final class RGCommonGroupStateCell: UITableViewCell {
    private let symbolView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private var topSpacing: NSLayoutConstraint?
    private var bottomSpacing: NSLayoutConstraint?
    private var symbolHeight: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        let symbolContainer = UIView()
        symbolContainer.addSubview(symbolView); symbolContainer.addSubview(spinner)
        symbolView.translatesAutoresizingMaskIntoConstraints = false; spinner.translatesAutoresizingMaskIntoConstraints = false
        let symbolHeight = symbolContainer.heightAnchor.constraint(equalToConstant: 36.0)
        self.symbolHeight = symbolHeight
        NSLayoutConstraint.activate([
            symbolHeight,
            symbolView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor)
        ])
        let stack = UIStackView(arrangedSubviews: [symbolContainer, titleLabel, detailLabel])
        stack.axis = .vertical; stack.spacing = 8.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textAlignment = .center; detailLabel.textAlignment = .center
        titleLabel.numberOfLines = 0; detailLabel.numberOfLines = 0
        contentView.addSubview(stack)
        let topSpacing = stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24.0)
        let bottomSpacing = stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24.0)
        self.topSpacing = topSpacing; self.bottomSpacing = bottomSpacing
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: 8.0),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor, constant: -8.0),
            topSpacing, bottomSpacing
        ])
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(title: String, detail: String?, symbol: String, loading: Bool, actionable: Bool, compact: Bool, data: PresentationData) {
        titleLabel.text = title; detailLabel.text = detail; detailLabel.isHidden = detail?.isEmpty != false
        titleLabel.font = compact ? Font.regular(max(13.0, data.listsFontSize.baseDisplaySize - 3.0)) : Font.semibold(data.listsFontSize.baseDisplaySize)
        detailLabel.font = Font.regular(max(13.0, data.listsFontSize.baseDisplaySize - 3.0))
        titleLabel.textColor = actionable ? data.theme.list.itemAccentColor : compact ? data.theme.list.itemSecondaryTextColor : data.theme.list.itemPrimaryTextColor
        detailLabel.textColor = data.theme.list.itemSecondaryTextColor
        symbolView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: compact ? 18.0 : 26.0, weight: .regular))
        symbolView.tintColor = actionable ? data.theme.list.itemAccentColor : data.theme.list.itemSecondaryTextColor
        symbolView.isHidden = loading
        spinner.color = data.theme.list.itemAccentColor
        if loading { spinner.startAnimating() } else { spinner.stopAnimating() }
        backgroundColor = data.theme.list.itemBlocksBackgroundColor
        let selection = selectedBackgroundView ?? UIView()
        selection.backgroundColor = data.theme.list.itemHighlightedBackgroundColor
        selectedBackgroundView = selection
        topSpacing?.constant = compact ? 14.0 : 24.0
        bottomSpacing?.constant = compact ? -14.0 : -24.0
        symbolHeight?.constant = compact ? 24.0 : 36.0
        selectionStyle = actionable ? .default : .none
        accessibilityLabel = [title, detail].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = actionable ? .button : .staticText
    }
}
