import Foundation
import UIKit
import UniformTypeIdentifiers
import LegacyUI
import Display
import TelegramPresentationData

/// Document-provider navigation/preview can make a picker disappear before its selection delegate
/// runs. Finish only on an actual selection, cancellation or interactive dismissal, never on
/// viewDidDisappear or a deferred "cancel" fallback racing an iCloud download.
final class RGFontDocumentPickerController: LegacyController, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    private let picker: UIDocumentPickerViewController
    private let completion: (URL?) -> Void
    private var completed = false

    init(theme: PresentationTheme, contentTypes: [UTType] = [.font, .data], completion: @escaping (URL?) -> Void) {
        self.picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        self.completion = completion
        super.init(presentation: .modal(animateIn: true), theme: theme)
        self.picker.delegate = self
        self.picker.allowsMultipleSelection = false
        self.picker.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light
        self.bind(controller: UIViewController())
        self.presentationCompleted = { [weak self] in
            guard let self else { return }
            guard var presenter = self.view.window?.rootViewController else { self.finish(nil); return }
            self.presentationCompleted = nil
            while let next = presenter.presentedViewController { presenter = next }
            self.picker.popoverPresentationController?.sourceView = presenter.view
            self.picker.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            presenter.present(self.picker, animated: true)
            self.picker.presentationController?.delegate = self
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func finish(_ url: URL?) {
        guard !self.completed else { return }
        self.completed = true
        let complete = { [self] in
            self.dismiss()
            self.completion(url)
        }
        if self.picker.presentingViewController != nil { self.picker.dismiss(animated: true, completion: complete) }
        else { complete() }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { self.finish(urls.first) }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { self.finish(nil) }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { self.finish(nil) }
}
