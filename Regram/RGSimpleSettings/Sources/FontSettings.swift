import Foundation

public enum RGFontFamily: String, CaseIterable {
    case system, jetBrainsMono, jetBrainsMonoNL, inter, poppins, lora, ibmPlexSans, ibmPlexSerif, ibmPlexMono, ibmPlexSansSC, sourceSans3, sourceSerif4, rounded, serif

    public var bundledPrefix: String? {
        switch self {
        case .jetBrainsMono: return "JetBrainsMono"
        case .jetBrainsMonoNL: return "JetBrainsMonoNL"
        case .inter: return "Inter"
        case .poppins: return "Poppins"
        case .lora: return "Lora"
        case .ibmPlexSans: return "IBMPlexSans"
        case .ibmPlexSerif: return "IBMPlexSerif"
        case .ibmPlexMono: return "IBMPlexMono"
        case .ibmPlexSansSC: return "IBMPlexSansSC"
        case .sourceSans3: return "SourceSans3"
        case .sourceSerif4: return "SourceSerif4"
        case .system, .rounded, .serif: return nil
        }
    }

    public var title: String {
        switch self {
        case .system: return "Fonts.System"
        case .jetBrainsMono: return "JetBrains Mono"
        case .jetBrainsMonoNL: return "JetBrains Mono NL"
        case .inter: return "Inter"
        case .poppins: return "Poppins"
        case .lora: return "Lora"
        case .ibmPlexSans: return "IBM Plex Sans"
        case .ibmPlexSerif: return "IBM Plex Serif"
        case .ibmPlexMono: return "IBM Plex Mono"
        case .ibmPlexSansSC: return "IBM Plex Sans SC"
        case .sourceSans3: return "Source Sans 3"
        case .sourceSerif4: return "Source Serif 4"
        case .rounded: return "Fonts.Rounded"
        case .serif: return "Fonts.Serif"
        }
    }
}

public enum RGFontArea { case interface, messages, system }

public struct RGFontConfiguration: Equatable {
    public static let settingsChanged = Notification.Name("Regram.FontSettingsChanged")
    public let family: RGFontFamily
    public let messages: Bool
    public let interface: Bool

    public init(family: String, messages: Bool, interface: Bool) {
        self.family = RGFontFamily(rawValue: family) ?? .system
        self.messages = messages
        self.interface = interface
    }

    public func family(for area: RGFontArea) -> RGFontFamily {
        switch area {
        case .messages: return messages ? family : .system
        case .interface: return interface ? family : .system
        case .system: return .system
        }
    }
}
