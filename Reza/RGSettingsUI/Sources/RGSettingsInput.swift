import SwiftUI
import RGSwiftUI

// Keep field names visible after a value is entered, as on Telegram's connection screens.
struct RGSettingsTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""

    init(_ title: String, text: Binding<String>, placeholder: String = "") {
        self.title = title
        self._text = text
        self.placeholder = placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote).rgSecondaryText()
            TextField(placeholder, text: $text).accessibilityLabel(title)
        }
        .padding(.vertical, 3)
    }
}

struct RGSettingsSecureField: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote).rgSecondaryText()
            SecureField(title, text: $text).accessibilityLabel(title)
        }
        .padding(.vertical, 3)
    }
}
