import SwiftUI
import UIKit
import RGSimpleSettings
import RGTypography

/// A local editor surface that also follows Telegram themes on iOS 15, where
/// SwiftUI's TextEditor cannot hide its system background. Keep the UIKit view
/// alive during theme updates so selection, the keyboard and IME composition
/// are not reset.
public struct RGSettingsTextEditor: UIViewRepresentable {
    @Binding private var text: String
    @Environment(\.rgSettingsColors) private var colors
    @Environment(\.isEnabled) private var isEnabled

    public init(text: Binding<String>) {
        self._text = text
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    public func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.adjustsFontForContentSizeCategory = true
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    public func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = $text
        // A binding notification during marked-text composition must never
        // replace the editor's text storage (Chinese/Japanese input).
        if view.text != text && view.markedTextRange == nil {
            view.text = text
        }
        view.backgroundColor = .clear
        view.textColor = UIColor(colors.primary)
        view.tintColor = UIColor(colors.accent)
        view.isEditable = isEnabled
        view.isUserInteractionEnabled = isEnabled
        let systemFont = UIFont.preferredFont(forTextStyle: .body, compatibleWith: view.traitCollection)
        let font: UIFont
        if let customFont = RGTypography.font(configuration: RGSimpleSettings.shared.fontConfiguration, area: .interface, size: 17.0) {
            font = UIFontMetrics(forTextStyle: .body).scaledFont(for: customFont, compatibleWith: view.traitCollection)
        } else {
            font = systemFont
        }
        if view.font != font {
            view.font = font
        }
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        fileprivate var text: Binding<String>

        fileprivate init(text: Binding<String>) {
            self.text = text
        }

        public func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}
