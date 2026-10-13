// MARK: Regram — retain the native picker delegate until selection has finished.
import Foundation
import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Display
import RGAppUpdate

@MainActor final class RGUpdateCredentialFilePicker: NSObject, ObservableObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    @Published private(set) var isPresented = false
    weak var owner: ViewController?
    private var picker: UIDocumentPickerViewController?
    private var completion: (([URL]?) -> Void)?

    func present(kind: RGUpdateCredentialFileKind, completion: @escaping ([URL]?) -> Void) {
        guard !isPresented else { return }
        guard var presenter = owner?.view.window?.rootViewController else { completion([]); return }
        while let next = presenter.presentedViewController { presenter = next }
        presenter.view.endEditing(true)
        // .item also covers certificates whose file provider reports an unknown UTI.
        // Read/type/size validation happens after a real selection, in copy mode.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = kind == .profiles
        picker.popoverPresentationController?.sourceView = presenter.view
        picker.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1.0, height: 1.0)
        self.picker = picker
        self.completion = completion
        isPresented = true
        presenter.present(picker, animated: true)
        picker.presentationController?.delegate = self
    }

    private func finish(_ urls: [URL]?) {
        guard let picker = self.picker, let completion = self.completion else { return }
        self.picker = nil
        self.completion = nil
        picker.delegate = nil
        picker.presentationController?.delegate = nil
        let finished = { [self] in
            guard self.isPresented else { return }
            self.isPresented = false
            completion(urls)
        }
        // A SwiftUI alert cannot be shown while the document picker is still dismissing.
        if picker.isBeingDismissed, let transition = picker.transitionCoordinator {
            if !transition.animate(alongsideTransition: nil, completion: { _ in finished() }) {
                DispatchQueue.main.async { finished() }
            }
        } else if picker.presentingViewController != nil { picker.dismiss(animated: true, completion: finished) }
        else { DispatchQueue.main.async { finished() } }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(urls) }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish(nil) }
}
