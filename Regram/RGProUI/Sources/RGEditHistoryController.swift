import Foundation
import SwiftUI
import UIKit
import Combine
import SwiftSignalKit
import RGSwiftUI
import RGStrings
import RGSimpleSettings
import AccountContext
import Display
import TelegramCore
import Postbox

// MARK: Regram — local text/caption and photo versions, newest first.
private struct RGEditHistoryVersion: Identifiable {
    let id: Int
    let text: String
    let date: Int32
    let isCurrent: Bool
    let isOriginal: Bool
    let image: TelegramMediaImage?
    let imageData: Data?
    let imageHasSpoiler: Bool
}

private final class RGHistoryPhotoModel: ObservableObject {
    @Published var image: UIImage?
    @Published var loading = false
    @Published var failed = false
    private let context: AccountContext
    private let messageId: MessageId
    private let version: RGEditHistoryVersion
    private let dataDisposable = MetaDisposable()
    private let fetchDisposable = MetaDisposable()
    private let saveDisposable = MetaDisposable()
    private var generation = UUID()

    init(context: AccountContext, messageId: MessageId, version: RGEditHistoryVersion) {
        self.context = context; self.messageId = messageId; self.version = version
        if let data = version.imageData { self.image = UIImage(data: data) }
    }
    deinit { dataDisposable.dispose(); fetchDisposable.dispose(); saveDisposable.dispose() }

    var needsOriginal: Bool {
        guard let image, let pixels = image.cgImage, let photo = version.image else { return false }
        return photo.representations.contains { Int($0.dimensions.width) > pixels.width || Int($0.dimensions.height) > pixels.height }
    }
    func load(original: Bool = false) {
        guard !loading, image == nil || original, let photo = version.image else { return }
        guard let representation = photo.representations.max(by: { Int64($0.dimensions.width) * Int64($0.dimensions.height) < Int64($1.dimensions.width) * Int64($1.dimensions.height) }) else { failed = true; return }
        generation = UUID(); let id = generation
        loading = true; failed = false
        let mediaBox = context.account.postbox.mediaBox
        dataDisposable.set((mediaBox.resourceData(representation.resource)
        |> filter { $0.complete }
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] resource in
            guard let self, self.generation == id else { return }
            self.loading = false
            guard resource.size <= Int64(RGEditHistoryEntry.maximumImageBytes),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: resource.path)),
                  let image = UIImage(data: data) else { self.failed = true; return }
            self.image = image
            self.fetchDisposable.set(nil)
            if !self.version.isCurrent {
                self.saveDisposable.set(rgSaveEditHistoryImageData(postbox: self.context.account.postbox, messageId: self.messageId, versionIndex: self.version.id, expectedImageId: photo.imageId, data: data).start())
            }
        }))
        fetchDisposable.set(fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(messageId.peerId), userContentType: .image, reference: .media(media: .standalone(media: photo), resource: representation.resource)).start(error: { [weak self] _ in
            Queue.mainQueue().async {
                guard let self, self.generation == id else { return }
                self.loading = false; self.failed = true; self.dataDisposable.set(nil)
            }
        }))
    }
    func cancel() { generation = UUID(); loading = false; dataDisposable.set(nil); fetchDisposable.set(nil) }
}

private struct RGHistoryPhotoView: View {
    @StateObject private var model: RGHistoryPhotoModel
    @State private var revealed = false
    @Environment(\.lang) private var lang
    @Environment(\.rgSettingsColors) private var colors
    let version: RGEditHistoryVersion
    let showImage: (UIImage) -> Void
    init(context: AccountContext, messageId: MessageId, version: RGEditHistoryVersion, showImage: @escaping (UIImage) -> Void) {
        self.version = version; self.showImage = showImage
        _model = StateObject(wrappedValue: RGHistoryPhotoModel(context: context, messageId: messageId, version: version))
    }
    var body: some View {
        let hidden = version.imageHasSpoiler && !revealed && !RGSimpleSettings.shared.automaticallyRevealSpoilers
        VStack(alignment: .leading, spacing: 6) {
            if let image = model.image {
                Button {
                    if hidden { revealed = true } else { showImage(image) }
                } label: {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 280)
                        .blur(radius: hidden ? 15 : 0)
                        .overlay { if hidden { Text("EditHistory.RevealPhoto".i18n(lang)).padding(10).background(.regularMaterial).cornerRadius(8) } }
                }.buttonStyle(.plain)
                .accessibilityLabel((hidden ? "EditHistory.RevealPhoto" : "EditHistory.ViewPhoto").i18n(lang))
                if model.loading { ProgressView("EditHistory.LoadingPhoto".i18n(lang)) }
                else if model.needsOriginal { Button("EditHistory.LoadOriginal".i18n(lang)) { model.load(original: true) } }
                if model.failed { Text("EditHistory.PhotoUnavailable".i18n(lang)).font(.footnote).foregroundColor(colors.secondary) }
            } else if model.loading { ProgressView("EditHistory.LoadingPhoto".i18n(lang)) }
            else {
                if model.failed { Text("EditHistory.PhotoUnavailable".i18n(lang)).font(.footnote).foregroundColor(colors.secondary) }
                Button("EditHistory.LoadPhoto".i18n(lang)) { model.load() }
            }
        }
        .onAppear { if version.isCurrent { model.load() } }
        .onDisappear { model.cancel() }
    }
}

private struct RGHistoryImageDetailView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: geometry.size.width * min(5, max(1, scale * pinch)), height: geometry.size.height * min(5, max(1, scale * pinch)))
                    .onTapGesture(count: 2) { scale = scale > 1 ? 1 : 2 }
            }
            .simultaneousGesture(MagnificationGesture().updating($pinch) { value, state, _ in state = value }.onEnded { scale = min(5, max(1, scale * $0)) })
        }
    }
}

private struct RGEditHistoryView: View {
    @Environment(\.lang) private var lang
    @Environment(\.rgSettingsColors) private var colors
    let context: AccountContext
    let messageId: MessageId
    let versions: [RGEditHistoryVersion]
    let copy: (String) -> Void
    let showImage: (UIImage) -> Void
    var body: some View {
        RGSettingsList {
            RGSettingsSection(footer: Text("EditHistory.Notice".i18n(lang))) {
                ForEach(versions) { version in
                    VStack(alignment: .leading, spacing: 6) {
                        if version.image != nil { RGHistoryPhotoView(context: context, messageId: messageId, version: version, showImage: showImage) }
                        if !version.text.isEmpty || version.image == nil {
                            Text(version.text.isEmpty ? "EditHistory.EmptyText".i18n(lang) : version.text)
                                .foregroundColor(version.text.isEmpty ? colors.secondary : colors.primary).textSelection(.enabled)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            if version.isCurrent { Text("EditHistory.Current".i18n(lang)).font(.caption.weight(.semibold)).foregroundColor(colors.accent) }
                            else if version.isOriginal { Text("EditHistory.Original".i18n(lang)).font(.caption.weight(.semibold)).foregroundColor(colors.secondary) }
                            Text("\(Text(Date(timeIntervalSince1970: Double(version.date)), style: .date)) · \(Text(Date(timeIntervalSince1970: Double(version.date)), style: .time))")
                                .font(.caption).foregroundColor(colors.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.vertical, 5)
                    .contextMenu { if !version.text.isEmpty { Button("EditHistory.Copy".i18n(lang)) { copy(version.text) } } }
                }
            }
        }
    }
}

public func rgEditHistoryController(context: AccountContext, message: Message) -> ViewController? {
    guard let history = message.rgEditHistory else { return nil }
    let currentDate = (message.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute)?.date ?? message.timestamp
    let currentImage = message.media.compactMap { $0 as? TelegramMediaImage }.first
    var versions = [RGEditHistoryVersion(id: history.entries.count, text: message.text, date: currentDate, isCurrent: true, isOriginal: false, image: currentImage, imageData: currentImage.flatMap { rgEditHistoryCachedImageData(image: $0, mediaBox: context.account.postbox.mediaBox) }, imageHasSpoiler: message.attributes.contains { $0 is MediaSpoilerMessageAttribute })]
    for (index, entry) in history.entries.enumerated().reversed() {
        versions.append(RGEditHistoryVersion(id: index, text: entry.text, date: entry.date, isCurrent: false, isOriginal: index == 0 && entry.date == message.timestamp, image: entry.image, imageData: entry.imageData, imageHasSpoiler: entry.imageHasSpoiler))
    }
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "EditHistory.Title".i18n(data.strings.rgLanguageCode)
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: {
        RGEditHistoryView(context: context, messageId: message.id, versions: versions, copy: { UIPasteboard.general.string = $0 }, showImage: { [weak controller] image in
            guard let controller else { return }
            let detail = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
            detail.bindAppearance(context.sharedContext.presentationData)
            detail.title = "EditHistory.ViewPhoto".i18n(data.strings.rgLanguageCode)
            let view = RGSwiftUIView(legacyController: detail, manageSafeArea: true, content: { RGHistoryImageDetailView(image: image) })
            detail.bind(controller: UIHostingController(rootView: view, ignoreSafeArea: true))
            (controller.navigationController as? NavigationController)?.pushViewController(detail)
        })
    })
    controller.bind(controller: UIHostingController(rootView: content, ignoreSafeArea: true))
    return controller
}
