import Foundation
import UIKit
import AccountContext
import RGSimpleSettings
import RGStrings
import RGSwiftUI
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TranslateUI

@MainActor public func rgPresentMessageFilterKeywordSelection(
    from presenter: UIViewController,
    context: AccountContext,
    text: String,
    allowsTranslation: Bool,
    completion: @escaping (Int) -> Void
) {
    let controller = RGMessageFilterKeywordSelectionController(context: context, text: text, allowsTranslation: allowsTranslation, completion: completion)
    let navigation = UINavigationController(rootViewController: controller)
    navigation.modalPresentationStyle = .pageSheet
    navigation.overrideUserInterfaceStyle = controller.theme.overallDarkAppearance ? .dark : .light
    navigation.view.tintColor = controller.theme.list.itemAccentColor
    navigation.sheetPresentationController?.detents = [.medium(), .large()]
    navigation.sheetPresentationController?.prefersGrabberVisible = true
    presenter.present(navigation, animated: true)
}

private final class RGMessageFilterKeywordSelectionController: UIViewController, UITextViewDelegate {
    private static let keywordLimit = 5
    private let context: AccountContext
    private let strings: PresentationStrings
    let theme: PresentationTheme
    private let text: String
    private let allowsTranslation: Bool
    private let completion: (Int) -> Void
    private var keywords: [String] = []
    private let translation = MetaDisposable()
    private let messageView = KeywordTextView()
    private let addButton = UIButton(type: .system)
    private let translateButton = UIButton(type: .system)
    private let keywordsLabel = UILabel()
    private let keywordsView = UIStackView()
    private lazy var addKeywordTitle = "MessageFilter.Selection.Add".i18n(self.strings.rgLanguageCode)

    init(context: AccountContext, text: String, allowsTranslation: Bool, completion: @escaping (Int) -> Void) {
        self.context = context
        let presentation = context.sharedContext.currentPresentationData.with { $0 }
        self.strings = presentation.strings
        self.theme = presentation.theme
        self.text = text
        self.allowsTranslation = allowsTranslation
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.translation.dispose()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let language = self.strings.rgLanguageCode
        self.title = "MessageFilter.Selection.Title".i18n(language)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: self.strings.Common_Cancel, style: .plain, target: self, action: #selector(self.close))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "MessageFilter.Selection.Submit".i18n(language), style: .done, target: self, action: #selector(self.submit))

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = self.theme.list.blocksBackgroundColor
        appearance.titleTextAttributes = [.foregroundColor: self.theme.list.itemPrimaryTextColor]
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance
        self.view.backgroundColor = self.theme.list.blocksBackgroundColor

        self.messageView.text = self.text
        self.messageView.font = UIFont.preferredFont(forTextStyle: .body)
        self.messageView.adjustsFontForContentSizeCategory = true
        self.messageView.textColor = self.theme.list.itemPrimaryTextColor
        self.messageView.backgroundColor = self.theme.list.itemBlocksBackgroundColor
        self.messageView.layer.cornerRadius = 12
        self.messageView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        self.messageView.isEditable = false
        self.messageView.isSelectable = true
        self.messageView.allowsTextActions = self.allowsTranslation
        self.messageView.accessibilityLabel = "MessageFilter.Selection.Original".i18n(language)
        self.messageView.delegate = self

        self.addButton.setTitle(self.addKeywordTitle, for: .normal)
        self.addButton.addTarget(self, action: #selector(self.addSelection), for: .touchUpInside)
        self.translateButton.setTitle(self.strings.Conversation_ContextMenuTranslate, for: .normal)
        self.translateButton.addTarget(self, action: #selector(self.translateSelection), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [self.addButton, self.translateButton])
        actions.distribution = .fillEqually
        self.translateButton.isHidden = !self.allowsTranslation
        actions.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        self.keywordsLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        self.keywordsLabel.adjustsFontForContentSizeCategory = true
        self.keywordsLabel.textColor = self.theme.list.itemSecondaryTextColor
        self.keywordsView.axis = .vertical
        let keywordsScrollView = UIScrollView()
        self.keywordsView.translatesAutoresizingMaskIntoConstraints = false
        keywordsScrollView.addSubview(self.keywordsView)

        let stack = UIStackView(arrangedSubviews: [self.messageView, actions, self.keywordsLabel, keywordsScrollView])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)
        let safeArea = self.view.safeAreaLayoutGuide
        let preferredMessageHeight = self.messageView.heightAnchor.constraint(equalTo: stack.heightAnchor, multiplier: 0.60)
        preferredMessageHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -16),
            preferredMessageHeight,
            self.keywordsView.leadingAnchor.constraint(equalTo: keywordsScrollView.contentLayoutGuide.leadingAnchor),
            self.keywordsView.trailingAnchor.constraint(equalTo: keywordsScrollView.contentLayoutGuide.trailingAnchor),
            self.keywordsView.topAnchor.constraint(equalTo: keywordsScrollView.contentLayoutGuide.topAnchor),
            self.keywordsView.bottomAnchor.constraint(equalTo: keywordsScrollView.contentLayoutGuide.bottomAnchor),
            self.keywordsView.widthAnchor.constraint(equalTo: keywordsScrollView.frameLayoutGuide.widthAnchor)
        ])
        self.updateKeywords()
    }

    private var selectedText: String? {
        return self.selectedText(in: self.messageView.selectedRange)
    }

    private func selectedText(in range: NSRange) -> String? {
        guard range.length > 0, let selection = Range(range, in: self.text) else { return nil }
        let value = self.text[selection].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func canAdd(_ text: String) -> Bool {
        return self.keywords.count < Self.keywordLimit && !self.keywords.contains(text)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        self.updateActions()
    }

    @available(iOS 16.0, *)
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let text = self.selectedText(in: range) else { return nil }
        let add = UIAction(title: self.addKeywordTitle, attributes: self.canAdd(text) ? [] : .disabled) { [weak self] _ in
            self?.addKeyword(text)
        }
        guard self.allowsTranslation else { return UIMenu(children: [add]) }
        let translate = UIAction(title: self.strings.Conversation_ContextMenuTranslate) { [weak self] _ in
            self?.translateKeyword(text)
        }
        return UIMenu(children: [add, translate])
    }

    private func updateActions() {
        let selection = self.selectedText
        self.addButton.isEnabled = selection.map(self.canAdd) ?? false
        self.translateButton.isEnabled = selection != nil
        self.navigationItem.rightBarButtonItem?.isEnabled = !self.keywords.isEmpty
    }

    private func updateKeywords() {
        self.keywordsLabel.text = "MessageFilter.Selection.Count".i18n(self.strings.rgLanguageCode, args: self.keywords.count, Self.keywordLimit)
        self.keywordsView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for keyword in self.keywords {
            var configuration = UIButton.Configuration.plain()
            configuration.title = keyword
            configuration.titleLineBreakMode = .byTruncatingTail
            configuration.image = UIImage(systemName: "xmark.circle")
            configuration.imagePlacement = .trailing
            configuration.imagePadding = 8
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.keywords.removeAll(where: { $0 == keyword })
                self?.updateKeywords()
            })
            button.contentHorizontalAlignment = .leading
            button.accessibilityLabel = "MessageFilter.Selection.Remove".i18n(self.strings.rgLanguageCode, args: keyword)
            self.keywordsView.addArrangedSubview(button)
        }
        self.updateActions()
    }

    @objc private func close() {
        self.dismiss(animated: true)
    }

    @objc private func addSelection() {
        if let text = self.selectedText { self.addKeyword(text) }
    }

    private func addKeyword(_ text: String) {
        guard self.canAdd(text) else { return }
        self.keywords.append(text)
        self.updateKeywords()
    }

    @objc private func translateSelection() {
        if let text = self.selectedText { self.translateKeyword(text) }
    }

    private func translateKeyword(_ text: String) {
        guard self.allowsTranslation else { return }
        let configuration = TranslationConfiguration.with(appConfiguration: self.context.currentAppConfiguration.with { $0 })
        if #available(iOS 18.0, *), case .system = configuration.manual {
            presentTranslateScreen(context: self.context, text: text, canCopy: true, fromLanguage: nil, display: { _ in })
            return
        }
        let target = translationInterfaceLanguage(strings: self.strings)
        self.translation.set((self.context.engine.messages.translate(text: text, toLang: target)
        |> deliverOnMainQueue).start(next: { [weak self] result in
            self?.showTranslation(result?.0)
        }, error: { [weak self] _ in
            self?.showTranslation(nil)
        }))
    }

    private func showTranslation(_ text: String?) {
        guard self.viewIfLoaded?.window != nil, self.presentedViewController == nil, self.navigationController?.isBeingDismissed != true else { return }
        let alert = UIAlertController(title: self.strings.Conversation_ContextMenuTranslate, message: text ?? "MessageFilter.Selection.TranslationFailed".i18n(self.strings.rgLanguageCode), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: self.strings.Common_Done, style: .cancel))
        self.present(alert, animated: true)
    }

    @objc private func submit() {
        guard !self.keywords.isEmpty else { return }
        self.navigationItem.rightBarButtonItem?.isEnabled = false
        let settings = RGSimpleSettings.shared
        let result = RGMessageFilter.merging(self.keywords.map { RGMessageFilterRule(pattern: $0) }, into: settings.messageFilterRules)
        if result.addedCount > 0 {
            settings.messageFilterRules = result.rules
        }
        let completion = self.completion
        self.dismiss(animated: true, completion: { completion(result.addedCount) })
    }
}

private final class KeywordTextView: UITextView {
    var allowsTextActions = true

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if !self.allowsTextActions, action != #selector(select(_:)), action != #selector(selectAll(_:)) {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }
}
