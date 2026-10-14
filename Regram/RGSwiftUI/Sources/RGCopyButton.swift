// MARK: Regram — copying gives immediate visible feedback, including when haptics are disabled.
import SwiftUI
import UIKit
import RGStrings

public struct RGCopyButton: View {
    @Environment(\.lang) private var language
    @State private var copied = false
    @State private var feedbackGeneration = UUID()
    private let titleKey: String
    private let value: () -> String
    public init(_ titleKey: String, value: @escaping () -> String) { self.titleKey = titleKey; self.value = value }
    public var body: some View {
        Button {
            UIPasteboard.general.string = value()
            copied = true
            let generation = UUID(); feedbackGeneration = generation
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIAccessibility.post(notification: .announcement, argument: "Common.Copied".i18n(language))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard feedbackGeneration == generation else { return }; copied = false
            }
        } label: {
            if copied { Label("Common.Copied".i18n(language), systemImage: "checkmark") }
            else { Text(titleKey.i18n(language)) }
        }.onDisappear { feedbackGeneration = UUID(); copied = false }
    }
}
