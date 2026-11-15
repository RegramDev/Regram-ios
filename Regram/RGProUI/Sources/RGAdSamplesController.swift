import Foundation
import UIKit
import AsyncDisplayKit
import Display
import AccountContext
import TelegramCore
import Postbox
import TelegramPresentationData
import PresentationDataUtils
import SwiftSignalKit
import RGStrings
import RGAdFilter

public func rgAdSamplesController(context: AccountContext) -> ViewController { RGAdLibraryController(context: context) }

public func rgAdSampleController(context: AccountContext, message: Message) -> ViewController? {
    let original = rgAdOriginalMessage(message)
    guard rgCanCorrectAds(original) else { return nil }
    return RGAdEditorController(context: context, message: original)
}

private class RGAdTableController: ViewController, UITableViewDataSource, UITableViewDelegate {
    let context: AccountContext
    let session: RGAdFilterSession
    let table = UITableView(frame: .zero, style: .insetGrouped)
    var data: PresentationData
    var lang: String { data.strings.rgLanguageCode }
    private let appearance = MetaDisposable()
    init(context: AccountContext) {
        self.context = context; session = RGAdFilterSession.get(context)
        data = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: data, glassStyle: .default))
        _hasGlassStyle = true
        navigationItem.backBarButtonItem = UIBarButtonItem(title: data.strings.Common_Back, style: .plain, target: nil, action: nil)
        appearance.set((context.sharedContext.presentationData |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let self else { return }; self.data = value
            self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: value, glassStyle: .default), transition: .immediate)
            if self.isNodeLoaded { self.applyTheme(); self.table.reloadData() }
        }))
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { appearance.dispose() }
    override func loadDisplayNode() {
        displayNode = ASDisplayNode(); displayNodeDidLoad()
        table.dataSource = self; table.delegate = self; table.contentInsetAdjustmentBehavior = .never
        table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 70
        displayNode.view.addSubview(table); applyTheme()
    }
    func applyTheme() {
        table.overrideUserInterfaceStyle = data.theme.overallDarkAppearance ? .dark : .light
        table.backgroundColor = data.theme.list.blocksBackgroundColor; table.separatorColor = data.theme.list.itemBlocksSeparatorColor
        table.tintColor = data.theme.list.itemAccentColor
        displayNode.backgroundColor = data.theme.list.blocksBackgroundColor
        statusBar.statusBarStyle = data.theme.rootController.statusBarStyle.style
    }
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = navigationLayout(layout: layout).navigationFrame.maxY
        transition.updateFrame(view: table, frame: CGRect(x: 0, y: top, width: layout.size.width, height: max(0, layout.size.height - top)))
        table.contentInset.bottom = layout.insets(options: []).bottom
    }
    func numberOfSections(in tableView: UITableView) -> Int { 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 0 }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { nil }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { cell("") }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { tableView.deselectRow(at: indexPath, animated: true) }
    func cell(_ title: String, detail: String? = nil, action: Bool = false) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = data.theme.list.itemBlocksBackgroundColor
        cell.textLabel?.text = title; cell.detailTextLabel?.text = detail
        cell.textLabel?.numberOfLines = 0; cell.detailTextLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .body); cell.detailTextLabel?.font = .preferredFont(forTextStyle: .footnote)
        cell.textLabel?.adjustsFontForContentSizeCategory = true; cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.textColor = action ? data.theme.list.itemAccentColor : data.theme.list.itemPrimaryTextColor
        cell.detailTextLabel?.textColor = data.theme.list.itemSecondaryTextColor
        cell.selectionStyle = action ? .default : .none
        let selected = UIView(); selected.backgroundColor = data.theme.list.itemHighlightedBackgroundColor; cell.selectedBackgroundView = selected
        return cell
    }
    func stackCell(_ views: [UIView]) -> UITableViewCell {
        let result = cell("")
        let stack = UIStackView(arrangedSubviews: views); stack.axis = .vertical; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false
        result.contentView.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: result.contentView.topAnchor, constant: 12), stack.bottomAnchor.constraint(equalTo: result.contentView.bottomAnchor, constant: -12), stack.leadingAnchor.constraint(equalTo: result.contentView.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: result.contentView.trailingAnchor, constant: -16)])
        return result
    }
    func label(_ text: String) -> UILabel {
        let label = UILabel(); label.text = text; label.numberOfLines = 0; label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true; label.textColor = data.theme.list.itemPrimaryTextColor
        return label
    }
    func showError(_ error: Error) {
        let text = (error as? RGAdSampleError) == .capacity ? "AdSamples.Capacity" : "AdSamples.Error"
        let alert = UIAlertController(title: text.i18n(lang), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: data.strings.Common_OK, style: .default))
        show(alert)
    }
    func show(_ controller: UIViewController) {
        guard var presenter = view.window?.rootViewController else { return }
        while let next = presenter.presentedViewController { presenter = next }
        if let popover = controller.popoverPresentationController { popover.sourceView = presenter.view; popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1) }
        presenter.present(controller, animated: true)
    }
    func push(_ controller: ViewController) { (navigationController as? NavigationController)?.pushViewController(controller) }
}

private final class RGAdLibraryController: RGAdTableController {
    private var samples: [RGAdSample] = []
    private var enabled = false
    private var loading = true
    private var failed = false
    override init(context: AccountContext) { super.init(context: context); title = "AdSamples.Title".i18n(lang) }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); reload() }
    private func reload() {
        loading = true; table.reloadData()
        session.perform({ store in (try store.load(), try store.isEnabled()) }) { [weak self] result in
            guard let self else { return }; self.loading = false
            switch result {
            case let .success(value): self.samples = value.0; self.enabled = value.1; self.failed = false
            case let .failure(error): self.failed = true; self.showError(error)
            }
            self.table.reloadData()
        }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 1 : section == 1 ? max(1, samples.count) : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 1 ? "AdSamples.Records".i18n(lang) + " (\(samples.count))" : nil }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { (section == 0 ? "AdSamples.AutomaticNotice" : section == 2 ? "AdSamples.LocalNotice" : "AdSamples.LibraryNotice").i18n(lang) }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let row = cell("AdSamples.Enabled".i18n(lang)); let toggle = UISwitch(); toggle.isOn = enabled; toggle.isEnabled = !loading && !failed
            toggle.onTintColor = data.theme.list.itemAccentColor; toggle.addTarget(self, action: #selector(toggleEnabled(_:)), for: .valueChanged); toggle.accessibilityLabel = "AdSamples.Enabled".i18n(lang); row.accessoryView = toggle; return row
        }
        if indexPath.section == 2 { let row = cell("AdSamples.Export".i18n(lang), action: true); row.isUserInteractionEnabled = !loading && !failed && !samples.isEmpty; return row }
        if failed { return cell("AdSamples.Retry".i18n(lang), action: true) }
        guard !samples.isEmpty else { return cell((loading ? "AdSamples.Loading" : "AdSamples.Empty").i18n(lang)) }
        let sample = samples[indexPath.row]
        let status = (sample.hasUncertainty ? "AdSamples.Uncertain" : sample.hasAds ? "AdSamples.Ad" : "AdSamples.Normal").i18n(lang)
        let row = cell(String(sample.input.text.prefix(100)).isEmpty ? "AdSamples.Media".i18n(lang) : String(sample.input.text.prefix(100)), detail: status + " · " + DateFormatter.localizedString(from: Date(timeIntervalSince1970: sample.reviewedAt ?? 0), dateStyle: .short, timeStyle: .short), action: true)
        row.textLabel?.numberOfLines = 3; row.textLabel?.textColor = data.theme.list.itemPrimaryTextColor; row.accessoryType = .disclosureIndicator
        return row
    }
    @objc private func toggleEnabled(_ sender: UISwitch) {
        let value = sender.isOn; sender.isEnabled = false
        session.perform(changes: true, { try $0.setEnabled(value) }) { [weak self] result in
            if case let .failure(error) = result { self?.showError(error) }; self?.reload()
        }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        super.tableView(tableView, didSelectRowAt: indexPath)
        guard !loading else { return }
        if indexPath.section == 1 {
            if failed { reload() } else if samples.indices.contains(indexPath.row) { push(RGAdEditorController(context: context, sample: samples[indexPath.row])) }
        } else if indexPath.section == 2, !samples.isEmpty, !failed { confirmExport() }
    }
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1, !loading, !failed, samples.indices.contains(indexPath.row) else { return nil }
        let sample = samples[indexPath.row]
        let remove = UIContextualAction(style: .destructive, title: data.strings.Common_Delete) { [weak self] _, _, done in
            guard let self else { done(false); return }
            self.session.perform(changes: true, { try $0.remove(sample) }) { [weak self] result in
                switch result { case .success: done(true); case let .failure(error): done(false); self?.showError(error) }; self?.reload()
            }
        }
        let config = UISwipeActionsConfiguration(actions: [remove]); config.performsFirstActionWithFullSwipe = false; return config
    }
    private func confirmExport() {
        let alert = UIAlertController(title: "AdSamples.Export".i18n(lang), message: "AdSamples.ExportNotice".i18n(lang), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: data.strings.Common_Cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: "AdSamples.Export".i18n(lang), style: .default) { [weak self] _ in self?.export() }); show(alert)
    }
    private func export() {
        session.perform({ try $0.export() }) { [weak self] result in
            guard let self else { return }
            do {
                let bytes = try result.get()
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ad-samples-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent("Regram-ad-corrections.jsonl")
                do { try bytes.write(to: file, options: .atomic) } catch { try? FileManager.default.removeItem(at: directory); throw error }
                let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
                share.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: directory) }
                self.show(share)
            } catch { self.showError(error) }
        }
    }
}

private final class RGAdTextView: UITextView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // Do not offer Translate/Look Up services from the local annotation surface.
        [#selector(copy(_:)), #selector(select(_:)), #selector(selectAll(_:))].contains(action) && super.canPerformAction(action, withSender: sender)
    }
}

private final class RGAdEditorController: RGAdTableController, UITextViewDelegate {
    private var sample: RGAdSample?
    private var initial: RGAdSample?
    private var busy = false
    private var allowClose = false
    private let textView = RGAdTextView()
    private let labels = RGAdLabel.allCases
    private var buttons: [RGAdButton] { sample?.input.buttons.flatMap { $0 } ?? [] }
    init(context: AccountContext, sample: RGAdSample) {
        self.sample = sample; initial = sample; super.init(context: context); setup()
    }
    init(context: AccountContext, message: Message) {
        super.init(context: context); setup()
        let input = rgAdInput(message)
        let kinds = message.media.filter { !($0 is TelegramMediaWebpage) }.map { media -> String in
            if media is TelegramMediaImage { return "image" }
            if let file = media as? TelegramMediaFile { return file.isVideo ? "video" : file.isVoice ? "voice" : "file" }
            return "other"
        }
        let key = "\(message.id.peerId.toInt64()):\(message.id.namespace):\(message.id.id)"
        let mediaIdentity = message.media.map { String(describing: $0.id) }.joined(separator: ":")
        session.perform({ store -> RGAdSample in
            var draft = try store.draft(input: input, messageKey: key, mediaKinds: kinds, mediaIdentity: mediaIdentity)
            if draft.reviewedAt == nil, let suggestion = try? RGAdPolicy.project(input, samples: store.load(), sourceGroup: draft.sourceGroup) {
                draft.spans = suggestion.removedRanges.map { RGAdSpan($0, .ad) }
                for id in suggestion.removedButtonIds { draft.buttonLabels[id] = .ad }
            }
            return draft
        }) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(sample): self.sample = sample; self.initial = sample; self.refresh()
            case let .failure(error): self.showError(error)
            }
        }
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func setup() {
        title = "AdSamples.Editor".i18n(lang)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "AdSamples.Save".i18n(lang), style: .done, target: self, action: #selector(save))
        textView.isEditable = false; textView.isSelectable = true; textView.delegate = self; textView.dataDetectorTypes = []
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.heightAnchor.constraint(equalToConstant: 320).isActive = true
        textView.accessibilityLabel = "AdSamples.Original".i18n(lang)
        attemptNavigation = { [weak self] navigate in
            guard let self else { return true }
            if self.busy { return false }
            if self.allowClose || self.sample == self.initial { return true }
            let alert = UIAlertController(title: "AdSamples.Discard".i18n(self.lang), message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: self.data.strings.Common_Cancel, style: .cancel))
            alert.addAction(UIAlertAction(title: "AdSamples.DiscardAction".i18n(self.lang), style: .destructive) { _ in self.allowClose = true; navigate() })
            self.show(alert); return false
        }
        refresh()
    }
    override func applyTheme() { super.applyTheme(); updateText() }
    private func updateText() {
        let selected = textView.selectedRange, offset = textView.contentOffset
        let text = NSMutableAttributedString(string: sample?.input.text ?? "", attributes: [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: data.theme.list.itemPrimaryTextColor])
        for span in sample?.spans ?? [] { text.addAttribute(.backgroundColor, value: (span.label == .ad ? UIColor.systemRed : UIColor.systemOrange).withAlphaComponent(0.22), range: span.range.nsRange) }
        textView.attributedText = text; textView.backgroundColor = data.theme.list.itemBlocksBackgroundColor; textView.tintColor = data.theme.list.itemAccentColor
        if NSMaxRange(selected) <= text.length { textView.selectedRange = selected }
        textView.setContentOffset(offset, animated: false)
    }
    private func refresh() {
        navigationItem.rightBarButtonItem?.isEnabled = sample != nil && !busy
        updateText(); table.reloadData()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { sample == nil ? 1 : 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard sample != nil else { return 1 }
        return section == 0 ? 3 : section == 1 ? buttons.count : section == 2 ? (sample?.mediaKinds.isEmpty == false ? 1 : 0) : 1
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard sample != nil else { return nil }
        return (section == 0 ? "AdSamples.Original" : section == 1 ? "AdSamples.Buttons" : section == 2 ? "AdSamples.Media" : "AdSamples.Preview").i18n(lang)
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard sample != nil else { return nil }
        return (section == 0 ? "AdSamples.MarkNotice" : section == 2 ? "AdSamples.MediaNotice" : section == 3 ? "AdSamples.SaveNotice" : "AdSamples.ButtonNotice").i18n(lang)
    }
    private func labelTitle(_ label: RGAdLabel) -> String { (label == .normal ? "AdSamples.Normal" : label == .ad ? "AdSamples.Ad" : "AdSamples.Uncertain").i18n(lang) }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sample else { return cell("AdSamples.Loading".i18n(lang)) }
        if indexPath.section == 0 {
            if indexPath.row == 0 {
                let actions = UIStackView(); actions.distribution = .fillEqually
                for (index, item) in labels.enumerated() {
                    let button = UIButton(type: .system); button.tag = index; button.setTitle(labelTitle(item), for: .normal)
                    button.addTarget(self, action: #selector(markSelection(_:)), for: .touchUpInside); button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; actions.addArrangedSubview(button)
                }
                textView.removeFromSuperview(); return stackCell([textView, actions])
            }
            return cell((indexPath.row == 1 ? "AdSamples.AllNormal" : "AdSamples.AllAd").i18n(lang), action: true)
        }
        if indexPath.section == 1 {
            let button = buttons[indexPath.row]
            let segment = UISegmentedControl(items: labels.map(labelTitle)); segment.tag = indexPath.row
            segment.selectedSegmentIndex = labels.firstIndex(of: sample.buttonLabels[button.id] ?? .uncertain) ?? 2
            segment.addTarget(self, action: #selector(changeButton(_:)), for: .valueChanged)
            segment.accessibilityLabel = button.title
            return stackCell([label(button.title + (button.target.map { "\n" + $0 } ?? "")), segment])
        }
        if indexPath.section == 2 {
            let segment = UISegmentedControl(items: labels.map(labelTitle)); segment.selectedSegmentIndex = labels.firstIndex(of: sample.mediaLabel) ?? 2
            segment.addTarget(self, action: #selector(changeMedia(_:)), for: .valueChanged)
            return stackCell([label("AdSamples.MediaCount".i18n(lang) + " \(sample.mediaKinds.count)"), segment])
        }
        return cell("AdSamples.Preview".i18n(lang), action: true)
    }
    @objc private func markSelection(_ sender: UIButton) { mark(textView.selectedRange, as: labels[sender.tag]) }
    private func mark(_ range: NSRange, as value: RGAdLabel) {
        guard !busy else { return }
        guard range.length > 0 else {
            let alert = UIAlertController(title: "AdSamples.SelectFirst".i18n(lang), message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: data.strings.Common_OK, style: .default)); show(alert); return
        }
        do { try sample?.mark(range, as: value); refresh() } catch { showError(error) }
    }
    @available(iOS 16.0, *)
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        UIMenu(children: labels.map { value in UIAction(title: labelTitle(value)) { [weak self] _ in self?.mark(range, as: value) } })
    }
    @objc private func changeButton(_ sender: UISegmentedControl) {
        guard !busy, buttons.indices.contains(sender.tag), labels.indices.contains(sender.selectedSegmentIndex) else { return }
        // Read the button id before opening the mutable access to sample's label dictionary.
        let id = buttons[sender.tag].id, value = labels[sender.selectedSegmentIndex]
        sample?.buttonLabels[id] = value
    }
    @objc private func changeMedia(_ sender: UISegmentedControl) {
        guard !busy, labels.indices.contains(sender.selectedSegmentIndex) else { return }
        sample?.mediaLabel = labels[sender.selectedSegmentIndex]
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        super.tableView(tableView, didSelectRowAt: indexPath)
        guard !busy, var sample else { return }
        if indexPath.section == 0, indexPath.row > 0 {
            let value: RGAdLabel = indexPath.row == 1 ? .normal : .ad
            sample.spans = []
            if value == .ad, !sample.input.text.isEmpty { try? sample.mark(NSRange(location: 0, length: sample.input.text.utf16.count), as: .ad) }
            sample.buttonLabels = sample.buttonLabels.mapValues { _ in value }; sample.mediaLabel = value
            self.sample = sample; refresh()
        } else if indexPath.section == 3 { push(RGAdPreviewController(context: context, sample: sample)) }
    }
    @objc private func save() {
        guard let sample, !busy else { return }; busy = true; refresh(); table.isUserInteractionEnabled = false
        session.perform(changes: true, { try $0.save(sample) }) { [weak self] result in
            guard let self else { return }; self.busy = false; self.table.isUserInteractionEnabled = true
            switch result {
            case .success: self.allowClose = true; _ = (self.navigationController as? NavigationController)?.popViewController(animated: true)
            case let .failure(error): self.refresh(); self.showError(error)
            }
        }
    }
}

private final class RGAdPreviewController: RGAdTableController {
    private let sample: RGAdSample
    init(context: AccountContext, sample: RGAdSample) { self.sample = sample; super.init(context: context); title = "AdSamples.Preview".i18n(lang) }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 3 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 { return cell(sample.previewText.isEmpty ? "AdSamples.EmptyText".i18n(lang) : sample.previewText) }
        if indexPath.row == 1 {
            let rows = sample.input.buttons.map { $0.filter { sample.buttonLabels[$0.id] != .ad }.map(\.title).joined(separator: "  ·  ") }.filter { !$0.isEmpty }
            return cell("AdSamples.Buttons".i18n(lang), detail: rows.isEmpty ? "AdSamples.None".i18n(lang) : rows.joined(separator: "\n"))
        }
        return cell("AdSamples.MediaNotice".i18n(lang))
    }
}
