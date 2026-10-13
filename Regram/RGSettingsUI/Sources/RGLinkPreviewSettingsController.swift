// MARK: Regram — UIKit grouped settings with the shared Regram navigation bar.
import AccountContext
import Combine
import Display
import Foundation
import RGSimpleSettings
import RGStrings
import RGSwiftUI
import TelegramPresentationData
import UIKit

private final class RGLinkPreviewTableController: UITableViewController {
    private let settings = RGSimpleSettings.shared
    private let focusSetting: String?
    private let language: String
    private let enabledSwitch = UISwitch()
    private let xField = UITextField()
    private let instagramField = UITextField()
    private var rows: [[UITableViewCell]] = []
    private var appliedInitialInsets = false
    var layoutSubscriptions = Set<AnyCancellable>()

    func applyTheme(_ theme: PresentationTheme) {
        loadViewIfNeeded()
        overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light
        view.tintColor = theme.list.itemAccentColor
        enabledSwitch.onTintColor = theme.list.itemAccentColor
        tableView.backgroundColor = theme.list.blocksBackgroundColor
        rows[1][2].textLabel?.textColor = theme.list.itemAccentColor
    }

    init(language: String, focusSetting: String?) {
        self.focusSetting = focusSetting
        self.language = language
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.automaticallyAdjustsScrollIndicatorInsets = false
        tableView.keyboardDismissMode = .interactive
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        let enabled = UITableViewCell(style: .default, reuseIdentifier: nil)
        enabled.textLabel?.text = "LinkPreview.Repair".i18n(language)
        enabled.selectionStyle = .none
        enabledSwitch.isOn = settings.fixLinkPreviews
        enabledSwitch.addTarget(self, action: #selector(enabledChanged), for: .valueChanged)
        enabled.accessoryView = enabledSwitch
        let x = domainCell(title: "LinkPreview.XService".i18n(language), field: xField, value: settings.linkPreviewXHost, placeholder: RGLinkPreviewRules.defaultXHost)
        let instagram = domainCell(title: "LinkPreview.InstagramService".i18n(language), field: instagramField, value: settings.linkPreviewInstagramHost, placeholder: RGLinkPreviewRules.defaultInstagramHost)
        let reset = UITableViewCell(style: .default, reuseIdentifier: nil)
        reset.textLabel?.text = "Common.Reset".i18n(language)
        reset.textLabel?.textColor = view.tintColor
        rows = [[enabled], [x, instagram, reset]]
        tableView.reloadData()
    }

    private func domainCell(title: String, field: UITextField, value: String, placeholder: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .caption1)
        field.text = value; field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .body)
        field.keyboardType = .URL; field.autocapitalizationType = .none; field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        field.addTarget(self, action: #selector(hostChanged), for: .editingChanged)
        let stack = UIStackView(arrangedSubviews: [label, field])
        stack.axis = .vertical; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)
        ])
        return cell
    }

    func updateInsets(layout: ContainerViewLayout, navigationHeight: CGFloat) {
        loadViewIfNeeded()
        let insets = UIEdgeInsets(top: max(navigationHeight, layout.safeInsets.top + layout.intrinsicInsets.top), left: layout.safeInsets.left, bottom: max(layout.inputHeight ?? 0, layout.safeInsets.bottom + layout.intrinsicInsets.bottom), right: layout.safeInsets.right)
        tableView.contentInset = insets
        tableView.scrollIndicatorInsets = insets
        if !appliedInitialInsets, insets.top > 0 {
            appliedInitialInsets = true
            tableView.setContentOffset(CGPoint(x: 0, y: -insets.top), animated: false)
        }
    }

    private func setting(at path: IndexPath) -> String? {
        if path.section == 0 && path.row == 0 { return "enabled" }
        if path.section == 1 { return ["xHost", "instagramHost", "reset"][path.row] }
        return nil
    }
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = setting(at: indexPath), let destination = RGSettingsDestination(page: "linkPreview", item: item) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
            UIMenu(children: [UIAction(title: "Settings.Link.Copy".i18n(self.language), image: UIImage(systemName: "link"), handler: { _ in UIPasteboard.general.string = destination.url.absoluteString })])
        })
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let focusSetting else { return }
        for section in rows.indices { for row in rows[section].indices {
            let index = IndexPath(row: row, section: section)
            if setting(at: index) == focusSetting { tableView.scrollToRow(at: index, at: .middle, animated: false); return }
        } }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows[section].count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { rows[indexPath.section][indexPath.row] }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? "LinkPreview.Services".i18n(language) : nil
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        (section == 0 ? "LinkPreview.Repair.Notice" : "LinkPreview.InvalidHost").i18n(language)
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1, indexPath.row == 2 else { return }
        xField.text = RGLinkPreviewRules.defaultXHost
        instagramField.text = RGLinkPreviewRules.defaultInstagramHost
        hostChanged()
    }
    @objc private func enabledChanged() {
        settings.fixLinkPreviews = enabledSwitch.isOn
        NotificationCenter.default.post(name: RGLinkPreviewRules.didChangeNotification, object: nil)
    }
    @objc private func hostChanged() {
        let x = xField.text ?? "", instagram = instagramField.text ?? ""
        var changed = false
        if RGLinkPreviewRules.isValidHost(x) {
            let value = x.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            changed = value != settings.linkPreviewXHost
            settings.linkPreviewXHost = value
        }
        if RGLinkPreviewRules.isValidHost(instagram) {
            let value = instagram.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            changed = changed || value != settings.linkPreviewInstagramHost
            settings.linkPreviewInstagramHost = value
        }
        tableView.footerView(forSection: 1)?.textLabel?.textColor = RGLinkPreviewRules.isValidHost(x) && RGLinkPreviewRules.isValidHost(instagram) ? .secondaryLabel : .systemRed
        if changed { NotificationCenter.default.post(name: RGLinkPreviewRules.didChangeNotification, object: nil) }
    }
}

public func rgLinkPreviewSettingsController(context: AccountContext, focusSetting: String? = nil) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "LinkPreview.Repair".i18n(data.strings.rgLanguageCode)
    let table = RGLinkPreviewTableController(language: data.strings.rgLanguageCode, focusSetting: focusSetting)
    controller.bind(controller: table)
    controller.themeModel.$value.sink { [weak table] theme in
        if let theme { table?.applyTheme(theme) }
    }.store(in: &table.layoutSubscriptions)
    controller.navigationBarHeightModel.$value.combineLatest(controller.containerViewLayoutModel.$value).sink { [weak table] height, layout in
        guard let layout else { return }
        table?.updateInsets(layout: layout, navigationHeight: height)
    }.store(in: &table.layoutSubscriptions)
    return controller
}
