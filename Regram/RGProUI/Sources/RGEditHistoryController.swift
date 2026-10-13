import Foundation
import SwiftUI
import UIKit
import RGSwiftUI
import RGStrings
import AccountContext
import Display
import TelegramCore
import Postbox

// MARK: Regram — earlier versions of an edited message (RGEditHistoryMessageAttribute), newest first,
// under the current text. Read-only: the history lives on this device and is never sent anywhere.

private struct RGEditHistoryVersion: Identifiable {
    let id: Int
    let text: String
    let date: Int32
    let isCurrent: Bool
    let isOriginal: Bool
}

private struct RGEditHistoryView: View {
    @Environment(\.lang) private var lang
    let versions: [RGEditHistoryVersion]
    let copy: (String) -> Void

    var body: some View {
        List {
            Section(footer: Text("EditHistory.Notice".i18n(lang))) {
                ForEach(versions) { version in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(version.text.isEmpty ? "EditHistory.EmptyText".i18n(lang) : version.text)
                            .foregroundColor(version.text.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                        HStack(spacing: 6) {
                            if version.isCurrent {
                                Text("EditHistory.Current".i18n(lang)).font(.caption.weight(.semibold)).foregroundColor(.accentColor)
                            } else if version.isOriginal {
                                Text("EditHistory.Original".i18n(lang)).font(.caption.weight(.semibold)).foregroundColor(.secondary)
                            }
                            Text(Date(timeIntervalSince1970: Double(version.date)), style: .date).font(.caption).foregroundColor(.secondary)
                            Text(Date(timeIntervalSince1970: Double(version.date)), style: .time).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                    .contextMenu {
                        Button("EditHistory.Copy".i18n(lang)) { copy(version.text) }
                    }
                }
            }
        }
    }
}

public func rgEditHistoryController(context: AccountContext, message: Message) -> ViewController? {
    guard let history = message.rgEditHistory else {
        return nil
    }
    var currentDate = message.timestamp
    if let edited = message.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute {
        currentDate = edited.date
    }
    var versions: [RGEditHistoryVersion] = [RGEditHistoryVersion(id: history.entries.count, text: message.text, date: currentDate, isCurrent: true, isOriginal: false)]
    for (index, entry) in history.entries.enumerated().reversed() {
        versions.append(RGEditHistoryVersion(id: index, text: entry.text, date: entry.date, isCurrent: false, isOriginal: index == 0 && entry.date == message.timestamp))
    }

    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "EditHistory.Title".i18n(data.strings.baseLanguageCode)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: {
        RGEditHistoryView(versions: versions, copy: { text in
            UIPasteboard.general.string = text
        })
    })
    controller.bind(controller: UIHostingController(rootView: content, ignoreSafeArea: true))
    return controller
}
