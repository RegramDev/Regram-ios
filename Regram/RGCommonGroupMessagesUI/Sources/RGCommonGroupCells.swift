// MARK: Regram — readable, reusable rows for common-group search and its group picker.
import Foundation
import UIKit
import Display
import AvatarNode
import AccountContext
import TelegramCore
import TelegramPresentationData
import LocalizedPeerData

final class RGCommonGroupHeaderView: UIView {
    var filterAction: (() -> Void)?
    var primaryAction: (() -> Void)?
    private let avatar = AvatarNode(font: avatarPlaceholderFont(size: 20.0))
    private let avatarContainer = UIView()
    private let nameLabel = UILabel()
    private let summaryLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let filterButton = UIButton(type: .system)
    private let actionButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatarContainer.addSubview(avatar.view)
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false
        let status = UIStackView(arrangedSubviews: [spinner, summaryLabel])
        status.spacing = 6.0; status.alignment = .center
        let personText = UIStackView(arrangedSubviews: [nameLabel, status])
        personText.axis = .vertical; personText.spacing = 5.0
        let person = UIStackView(arrangedSubviews: [avatarContainer, personText])
        person.spacing = 12.0; person.alignment = .center
        let controls = UIStackView(arrangedSubviews: [filterButton, actionButton])
        controls.spacing = 10.0
        let stack = UIStackView(arrangedSubviews: [person, controls])
        stack.axis = .vertical; stack.spacing = 16.0; stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            avatarContainer.widthAnchor.constraint(equalToConstant: 48.0),
            avatarContainer.heightAnchor.constraint(equalToConstant: 48.0),
            controls.heightAnchor.constraint(equalToConstant: 44.0),
            actionButton.widthAnchor.constraint(equalToConstant: 44.0),
            stack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20.0),
            stack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20.0),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16.0),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12.0)
        ])
        nameLabel.numberOfLines = 2; summaryLabel.numberOfLines = 2
        spinner.hidesWhenStopped = true
        actionButton.layer.cornerRadius = 22.0
        filterButton.addTarget(self, action: #selector(filterPressed), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); avatar.frame = avatarContainer.bounds }
    @objc private func filterPressed() { filterAction?() }
    @objc private func actionPressed() { primaryAction?() }

    func update(context: AccountContext, author: EnginePeer, summary: String, filterTitle: String, filterHint: String, filterEnabled: Bool, actionTitle: String, actionSymbol: String, loading: Bool, data: PresentationData) {
        avatar.setPeer(context: context, theme: data.theme, peer: author, displayDimensions: CGSize(width: 48.0, height: 48.0))
        nameLabel.text = author.displayTitle(strings: data.strings, displayOrder: data.nameDisplayOrder)
        nameLabel.font = Font.semibold(max(18.0, data.listsFontSize.baseDisplaySize))
        nameLabel.textColor = data.theme.list.itemPrimaryTextColor
        summaryLabel.text = summary
        summaryLabel.font = Font.regular(max(13.0, data.listsFontSize.baseDisplaySize - 3.0))
        summaryLabel.textColor = data.theme.list.itemSecondaryTextColor
        spinner.color = data.theme.list.itemAccentColor
        if loading { spinner.startAnimating() } else { spinner.stopAnimating() }

        var configuration = UIButton.Configuration.plain()
        configuration.title = filterTitle
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11.0, weight: .semibold))
        configuration.imagePlacement = .trailing; configuration.imagePadding = 8.0
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10.0, leading: 16.0, bottom: 10.0, trailing: 16.0)
        configuration.baseForegroundColor = data.theme.list.itemAccentColor
        configuration.background.backgroundColor = data.theme.list.itemBlocksBackgroundColor
        configuration.background.cornerRadius = 22.0
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes; result.font = Font.medium(max(14.0, data.listsFontSize.baseDisplaySize - 3.0)); return result
        }
        filterButton.configuration = configuration
        filterButton.contentHorizontalAlignment = .leading
        filterButton.isEnabled = filterEnabled; filterButton.alpha = filterEnabled ? 1.0 : 0.5
        filterButton.accessibilityLabel = filterHint; filterButton.accessibilityValue = filterTitle
        actionButton.setImage(UIImage(systemName: actionSymbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17.0, weight: .medium)), for: .normal)
        actionButton.backgroundColor = data.theme.list.itemBlocksBackgroundColor
        actionButton.tintColor = data.theme.list.itemAccentColor
        actionButton.accessibilityLabel = actionTitle
    }
}

final class RGCommonGroupPeerCell: UITableViewCell {
    private let avatar = AvatarNode(font: avatarPlaceholderFont(size: 18.0))
    private let avatarContainer = UIView()
    private let nameLabel = UILabel()
    private let summaryLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        avatarContainer.addSubview(avatar.view)
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false
        let text = UIStackView(arrangedSubviews: [nameLabel, summaryLabel])
        text.axis = .vertical; text.spacing = 4.0
        text.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarContainer); contentView.addSubview(text)
        nameLabel.numberOfLines = 2; summaryLabel.numberOfLines = 0
        NSLayoutConstraint.activate([
            avatarContainer.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarContainer.widthAnchor.constraint(equalToConstant: 44.0),
            avatarContainer.heightAnchor.constraint(equalToConstant: 44.0),
            text.leadingAnchor.constraint(equalTo: avatarContainer.trailingAnchor, constant: 12.0),
            text.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            text.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14.0),
            text.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14.0),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72.0)
        ])
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        avatar.frame = avatarContainer.bounds
    }
    func update(context: AccountContext, peer: EnginePeer?, title: String, summary: String?, data: PresentationData, selected: Bool = false, selectable: Bool = true) {
        avatar.setPeer(context: context, theme: data.theme, peer: peer, displayDimensions: CGSize(width: 44.0, height: 44.0))
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
    private let avatar = AvatarNode(font: avatarPlaceholderFont(size: 16.0))
    private let avatarContainer = UIView()
    private let groupLabel = UILabel()
    private let dateLabel = UILabel()
    private let bodyLabel = UILabel()
    private let heading = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        avatarContainer.addSubview(avatar.view)
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false
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
            avatarContainer.widthAnchor.constraint(equalToConstant: 36.0),
            avatarContainer.heightAnchor.constraint(equalToConstant: 36.0),
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
    override func layoutSubviews() {
        super.layoutSubviews()
        avatar.frame = avatarContainer.bounds
    }
    func update(context: AccountContext, group: EnginePeer?, title: String, date: String, fullDate: String, body: String, openHint: String, availableWidth: CGFloat, data: PresentationData) {
        avatar.setPeer(context: context, theme: data.theme, peer: group, displayDimensions: CGSize(width: 36.0, height: 36.0))
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
        accessoryType = .none
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
