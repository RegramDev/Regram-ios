import Foundation

public enum RGFontFamily: String, CaseIterable {
    case system, jetBrainsMono, jetBrainsMonoNL, inter, poppins, lora, ibmPlexSans, ibmPlexSerif, ibmPlexMono, ibmPlexSansSC, sourceSans3, sourceSerif4, rounded, serif

    public static var latinChoices: [RGFontFamily] { return self.allCases.filter { $0 != .ibmPlexSansSC } }

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

public enum RGChineseFontFamily: String, CaseIterable {
    case system, ibmPlexSansSC, notoSerifSC

    public var title: String {
        switch self {
        case .system: return "Fonts.Chinese.System"
        case .ibmPlexSansSC: return "IBM Plex Sans SC"
        case .notoSerifSC: return "Noto Serif SC"
        }
    }
}

public enum RGFontArea { case interface, messages, system }

public struct RGFontConfiguration: Equatable {
    public static let settingsChanged = Notification.Name("Regram.FontSettingsChanged")
    public let family: RGFontFamily
    public let chineseFamily: RGChineseFontFamily
    public let importedLatin: String
    public let importedChinese: String
    public let assetsRevision: Int
    public let messages: Bool
    public let interface: Bool

    public init(family: String, messages: Bool, interface: Bool, chineseFamily: String = RGChineseFontFamily.system.rawValue, importedLatin: String = "", importedChinese: String = "", assetsRevision: Int = 0) {
        self.family = RGFontFamily(rawValue: family) ?? .system
        self.chineseFamily = RGChineseFontFamily(rawValue: chineseFamily) ?? .system
        self.importedLatin = importedLatin
        self.importedChinese = importedChinese
        self.assetsRevision = assetsRevision
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
    public func chineseFamily(for area: RGFontArea) -> RGChineseFontFamily {
        switch area {
        case .messages: return messages ? chineseFamily : .system
        case .interface: return interface ? chineseFamily : .system
        case .system: return .system
        }
    }

    public func importedFont(for area: RGFontArea, chinese: Bool) -> String {
        switch area {
        case .messages: return messages ? (chinese ? importedChinese : importedLatin) : ""
        case .interface: return interface ? (chinese ? importedChinese : importedLatin) : ""
        case .system: return ""
        }
    }

    public func usesCustomFonts(for area: RGFontArea) -> Bool {
        return !self.importedFont(for: area, chinese: false).isEmpty || !self.importedFont(for: area, chinese: true).isEmpty || self.family(for: area) != .system || self.chineseFamily(for: area) != .system
    }

    public func cacheKey(for area: RGFontArea) -> String {
        return self.family(for: area).rawValue + ":" + self.chineseFamily(for: area).rawValue + ":" + self.importedFont(for: area, chinese: false) + ":" + self.importedFont(for: area, chinese: true) + ":" + (self.usesCustomFonts(for: area) ? String(self.assetsRevision) : "0")
    }

    public static func migratedChoices(legacyFamily: String) -> (latin: RGFontFamily, chinese: RGChineseFontFamily) {
        if legacyFamily == RGFontFamily.ibmPlexSansSC.rawValue { return (.system, .ibmPlexSansSC) }
        return (RGFontFamily(rawValue: legacyFamily) ?? .system, .system)
    }

}
