// MARK: Regram
import Foundation
import UIKit
import SwiftUI
import RGSwiftUI
import RGStrings
import RGAppUpdate
import AccountContext
import Display
import PresentationDataUtils

@MainActor private struct RGAppUpdateView: View {
    @ObservedObject private var updater = RGAppUpdater.shared
    @StateObject private var filePicker = RGUpdateCredentialFilePicker()
    @Environment(\.lang) private var lang
    @State private var credentialBusy = false
    let owner: () -> ViewController?
    let presentMessage: (String) -> Void

    var body: some View {
        Form {
            Section {
                LabeledContentCompat(title: "AppUpdate.CurrentVersion".i18n(lang), value: "\(updater.installedVersion) (\(updater.installedBuild))")
                Button("AppUpdate.Check".i18n(lang)) { updater.check() }.disabled(updater.stage.isBusy || credentialBusy)
                if let release = updater.release {
                    Text("\(release.version) (\(release.build))").font(.headline)
                    if !release.notes.isEmpty {
                        DisclosureGroup("AppUpdate.ReleaseNotes".i18n(lang)) { Text(release.notes).font(.footnote).textSelection(.enabled) }
                    }
                    updateStatus
                    if updater.hasPreparedUpdate {
                        Button("AppUpdate.Install".i18n(lang)) { updater.install() }.disabled(updater.stage.isBusy)
                    } else {
                        Button((updater.installationMethod == .trollStore ? "AppUpdate.DownloadTrollStore" : (updater.hasDownloadedUpdate ? "AppUpdate.SignCached" : "AppUpdate.Prepare")).i18n(lang)) { updater.prepare() }.disabled(updater.stage.isBusy || !updater.isConfigured || credentialBusy)
                    }
                } else { updateStatus }
                if updater.stage.isBusy { Button("AppUpdate.Cancel".i18n(lang), role: .cancel) { updater.cancel() } }
            }
            Section(footer: Text((updater.installationMethod == .trollStore ? "AppUpdate.TrollStoreNotice" : "AppUpdate.AutomaticNotice").i18n(lang))) {
                Picker("AppUpdate.InstallationMethod".i18n(lang), selection: $updater.installationMethod) {
                    ForEach(RGUpdateInstallationMethod.allCases, id: \.rawValue) { method in Text(method.localizationKey.i18n(lang)).tag(method) }
                }.disabled(updater.stage.isBusy || credentialBusy || filePicker.isPresented)
                Toggle("AppUpdate.AutomaticCheck".i18n(lang), isOn: $updater.automaticallyCheck)
                Toggle((updater.installationMethod == .trollStore ? "AppUpdate.AutomaticDownload" : "AppUpdate.AutomaticPrepare").i18n(lang), isOn: $updater.automaticallyPrepare).disabled(!updater.isConfigured)
            }
            if updater.installationMethod == .certificate {
                Section(footer: Text("AppUpdate.CertificateNotice".i18n(lang))) {
                    if !updater.certificateName.isEmpty { Text(updater.certificateName).font(.footnote) }
                    Text("AppUpdate.SavedProfiles".i18n(lang, args: String(updater.savedProfileCount))).font(.footnote).foregroundColor(.secondary)
                    Button("AppUpdate.ImportSigningMaterials".i18n(lang)) { selectFiles(kind: .signingMaterials) }
                    Button("AppUpdate.ImportProfiles".i18n(lang)) { selectFiles(kind: .profiles) }
                    if credentialBusy { ProgressView("AppUpdate.Importing".i18n(lang)) }
                    if !updater.certificateName.isEmpty {
                        Button("AppUpdate.RemoveCertificate".i18n(lang), role: .destructive) {
                            do { try updater.clearCertificate() } catch { show(error) }
                        }
                    }
                }.disabled(updater.stage.isBusy || credentialBusy || filePicker.isPresented)
                Section(footer: Text("AppUpdate.ServiceNotice".i18n(lang))) {
                    Picker("AppUpdate.InstallationNode".i18n(lang), selection: $updater.preferredNode) {
                        Text("AppUpdate.AutomaticNode".i18n(lang)).tag("")
                        ForEach(updater.availableNodes) { node in Text(node.name).tag(node.code) }
                    }
                    if !updater.activeNode.isEmpty { Text(updater.activeNode).foregroundColor(.secondary) }
                }.disabled(updater.stage.isBusy)
            }
        }
    }

    private var updateStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(updater.stage.localizationKey.i18n(lang)).foregroundColor(.secondary)
            if let failure = updater.failure {
                if let bundle = failure.profileBundle { Text("AppUpdate.ProfileBundle".i18n(lang, args: bundle)).font(.footnote) }
                if let entitlement = failure.profileEntitlement { Text("AppUpdate.ProfileEntitlement".i18n(lang, args: entitlement)).font(.footnote).textSelection(.enabled) }
            }
            if updater.stage == .downloading {
                HStack {
                    Text("\(Int(updater.progress * 100))%").monospacedDigit()
                    Spacer()
                    Text("\(ByteCountFormatter.string(fromByteCount: updater.downloadedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: updater.release?.size ?? 0, countStyle: .file))").font(.footnote).foregroundColor(.secondary)
                }
                ProgressView(value: updater.progress, total: 1).progressViewStyle(.linear).frame(maxWidth: .infinity)
            } else if updater.stage.isBusy { ProgressView().progressViewStyle(.circular) }
        }
    }

    private func selectFiles(kind: RGUpdateCredentialFileKind) {
        filePicker.owner = owner()
        filePicker.present(kind: kind) { urls in
            guard let urls else { return }
            guard !urls.isEmpty, urls.count <= 16 else { show(RGUpdateCredentialFileError.unreadable); return }
            if kind == .signingMaterials, urls.filter({ RGUpdateCredentialFileKind.certificate.acceptsExtension($0.pathExtension) }).count != 1 {
                show(RGUpdateCredentialFileError.certificateSelection); return
            }
            credentialBusy = true
            Task { @MainActor in
                defer { credentialBusy = false }
                do {
                    let data = try await Task.detached(priority: .userInitiated) {
                        try urls.map { try RGUpdateCredentialFile.read(url: $0, kind: kind) }
                    }.value
                    switch kind {
                    case .profiles:
                        try await updater.importProfiles(data)
                        credentialBusy = false
                        presentMessage("AppUpdate.ProfilesImported".i18n(lang, args: String(data.count)))
                    case .certificate, .signingMaterials:
                        guard let certificateIndex = urls.firstIndex(where: { RGUpdateCredentialFileKind.certificate.acceptsExtension($0.pathExtension) }) else { throw RGUpdateCredentialFileError.certificateSelection }
                        guard let p12Password = await filePicker.requestPassword(fileName: urls[certificateIndex].lastPathComponent, title: "AppUpdate.ImportSigningMaterials".i18n(lang), placeholder: "AppUpdate.CertificatePassword".i18n(lang), confirm: "AppUpdate.ImportConfirm".i18n(lang), cancel: "AppUpdate.Cancel".i18n(lang)) else { return }
                        let profiles = data.enumerated().filter { $0.offset != certificateIndex }.map(\.element)
                        try await updater.importCertificate(data[certificateIndex], password: p12Password, profiles: profiles)
                        credentialBusy = false
                        presentMessage("AppUpdate.CertificateImported".i18n(lang))
                    }
                } catch {
                    credentialBusy = false
                    show(error)
                }
            }
        }
    }

    private func show(_ error: Error) {
        let key = (error as? RGUpdateCredentialFileError)?.localizationKey ?? (error as? RGUpdateError ?? .network).localizationKey
        var message = key.i18n(lang)
        if let failure = error as? RGUpdateError {
            if let bundle = failure.profileBundle { message += "\n\n" + "AppUpdate.ProfileBundle".i18n(lang, args: bundle) }
            if let entitlement = failure.profileEntitlement { message += "\n" + "AppUpdate.ProfileEntitlement".i18n(lang, args: entitlement) }
        }
        presentMessage(message)
    }
}

private struct LabeledContentCompat: View {
    let title: String
    let value: String
    var body: some View { HStack { Text(title); Spacer(); Text(value).foregroundColor(.secondary) } }
}

public func rgAppUpdateController(context: AccountContext) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let controller = LegacySwiftUIController(presentation: .navigation, theme: data.theme, strings: data.strings)
    controller.bindAppearance(context.sharedContext.presentationData)
    controller.title = "AppUpdate.Title".i18n(data.strings.baseLanguageCode)
    // MARK: Regram — present through Telegram's window stack. SwiftUI alerts on
    // a legacy hosted controller can receive touches behind the modal overlay.
    let content = RGSwiftUIView(legacyController: controller, manageSafeArea: true, content: {
        RGAppUpdateView(owner: { [weak controller] in controller }, presentMessage: { [weak controller] message in
            guard let controller else { return }
            let data = context.sharedContext.currentPresentationData.with { $0 }
            controller.present(textAlertController(context: context, title: "AppUpdate.Title".i18n(data.strings.baseLanguageCode), text: message, actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))
        })
    })
    controller.bind(controller: UIHostingController(rootView: content, ignoreSafeArea: true))
    return controller
}
