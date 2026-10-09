import Foundation
import UIKit
import CoreText
import AppBundle
import RGSimpleSettings

/// Registers downloaded or imported fonts per process. No network requests occur while rendering.
public enum RGTypography {
    private static let registrationLock = NSLock()
    private static var registered: [RGFontFamily: [String: String]] = [:]

    private static func register(_ family: RGFontFamily, prefix: String) -> [String: String] {
        self.registrationLock.lock()
        defer { self.registrationLock.unlock() }
        if let faces = self.registered[family], !faces.isEmpty { return faces }
        var faces: [String: String] = [:]
        for style in ["Regular", "Medium", "SemiBold", "Semibold", "Bold", "Italic", "MediumItalic", "SemiBoldItalic", "BoldItalic", "It", "MediumIt", "SemiboldIt", "BoldIt"] {
            if let path = RGFontStore.cachedURL(filename: "\(prefix)-\(style).ttf") {
                let url = path as CFURL
                if let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor])?.first,
                   let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
                    CTFontManagerRegisterFontsForURL(url, .process, nil)
                    faces[style] = name
                }
            }
        }
        self.registered[family] = faces
        return faces
    }

    private static var notoName: String?
    private static var importedDescriptors: [String: CTFontDescriptor] = [:]

    private static func registeredName(url: URL) -> String? {
        guard let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first,
              let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return name
    }

    private static var notoSerifName: String? {
        registrationLock.lock()
        defer { registrationLock.unlock() }
        if let name = notoName { return name }
        guard let url = RGFontStore.cachedURL(filename: "NotoSerifSC-Variable.ttf") else { return nil }
        notoName = registeredName(url: url)
        return notoName
    }

    private static func importedFont(id: String, size: CGFloat, weight: UIFont.Weight, italic: Bool) -> UIFont? {
        guard !id.isEmpty, let url = RGFontStore.importedURL(id: id, italic: italic) else { return nil }
        registrationLock.lock()
        let key = id + (italic ? ":italic" : ":regular")
        let descriptor = importedDescriptors[key] ?? (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
        if let descriptor, importedDescriptors[key] == nil {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            importedDescriptors[key] = descriptor
        }
        registrationLock.unlock()
        guard let descriptor else { return nil }
        let base = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        var result = (base as UIFont).fontDescriptor
        var hasWeightAxis = false
        var hasItalicAxis = false
        var variations: [NSNumber: NSNumber] = [:]
        if let axes = CTFontCopyVariationAxes(base) as? [[String: Any]] {
            for axis in axes {
                guard let id = axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber else { continue }
                let desired: Double
                switch id.uint32Value {
                case 0x77676874: // wght
                    hasWeightAxis = true
                    desired = weight >= .bold ? 700 : weight >= .semibold ? 600 : weight >= .medium ? 500 : weight <= .thin ? 200 : weight <= .light ? 300 : 400
                case 0x6f70737a: desired = Double(size) // opsz
                case 0x736c6e74: // slnt: Google Sans Flex's genuine oblique axis
                    hasItalicAxis = true
                    desired = italic ? -10 : 0
                case 0x6974616c: hasItalicAxis = true; desired = italic ? 1 : 0 // ital
                default: continue
                }
                let minimum = (axis[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber)?.doubleValue ?? desired
                let maximum = (axis[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber)?.doubleValue ?? desired
                variations[id] = NSNumber(value: max(minimum, min(maximum, desired)))
            }
        }
        if !variations.isEmpty { result = result.addingAttributes([UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variations]) }
        if !hasWeightAxis, weight >= .semibold, let bold = result.withSymbolicTraits(result.symbolicTraits.union(.traitBold)) { result = bold }
        if italic && !hasItalicAxis {
            result = result.withSymbolicTraits(result.symbolicTraits.union(.traitItalic)) ?? result.addingAttributes([.matrix: NSValue(cgAffineTransform: CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0))])
        }
        return UIFont(descriptor: result, size: size)
    }

    private static func nativeFont(size: CGFloat, weight: UIFont.Weight, italic: Bool) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        if italic, let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return font
    }

    public static func chineseFont(family: RGChineseFontFamily, size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        switch family {
        case .ibmPlexSansSC:
            if let font = self.font(family: .ibmPlexSansSC, size: size, weight: weight, italic: italic) { return font }
        case .notoSerifSC:
            if let name = self.notoSerifName, let base = UIFont(name: name, size: size) {
                let axisWeight: CGFloat = weight >= .bold ? 700.0 : weight >= .semibold ? 600.0 : weight >= .medium ? 500.0 : weight <= .thin ? 200.0 : weight <= .light ? 300.0 : 400.0
                var descriptor = base.fontDescriptor.addingAttributes([
                    UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [NSNumber(value: 0x77676874): NSNumber(value: Double(axisWeight))]
                ])
                if italic {
                    descriptor = descriptor.addingAttributes([.matrix: NSValue(cgAffineTransform: CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0))])
                }
                return UIFont(descriptor: descriptor, size: size)
            }
        case .system:
            break
        }
        let native = self.nativeFont(size: size, weight: weight, italic: italic)
        return CTFontCreateForString(native as CTFont, "中文漢字" as CFString, CFRange(location: 0, length: 4)) as UIFont
    }

    public static func font(configuration: RGFontConfiguration, area: RGFontArea = .interface, size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont? {
        guard configuration.usesCustomFonts(for: area) else { return nil }
        let latin = self.importedFont(id: configuration.importedFont(for: area, chinese: false), size: size, weight: weight, italic: italic) ?? self.font(family: configuration.family(for: area), size: size, weight: weight, italic: italic) ?? self.nativeFont(size: size, weight: weight, italic: italic)
        let chinese = self.importedFont(id: configuration.importedFont(for: area, chinese: true), size: size, weight: weight, italic: italic) ?? self.chineseFont(family: configuration.chineseFamily(for: area), size: size, weight: weight, italic: italic)
        return RGFontCascade.font(latin: latin as CTFont, chinese: chinese as CTFont) as UIFont
    }

    public static func font(family: RGFontFamily, size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont? {
        switch family {
        case .system: return nil
        case .rounded, .serif:
            var descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
            if italic, let updated = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) { descriptor = updated }
            if let updated = descriptor.withDesign(family == .rounded ? .rounded : .serif) {
                return UIFont(descriptor: updated, size: size)
            }
            return nil
        default:
            guard let prefix = family.bundledPrefix else { return nil }
            let faces = self.register(family, prefix: prefix)
            let adobe = family == .sourceSans3 || family == .sourceSerif4
            let style: String
            if weight >= .bold { style = "Bold" }
            else if weight >= .semibold { style = adobe ? "Semibold" : "SemiBold" }
            else if weight >= .medium { style = "Medium" }
            else { style = "Regular" }
            if italic, family != .ibmPlexSansSC {
                let italicStyle = adobe ? (style == "Regular" ? "It" : style + "It") : (style == "Regular" ? "Italic" : style + "Italic")
                if let name = faces[italicStyle], let font = UIFont(name: name, size: size) { return font }
                // Source Serif has no Medium face: use its regular italic at that weight.
                return faces[adobe ? "It" : "Italic"].flatMap { UIFont(name: $0, size: size) }
            }
            guard let font = faces[style].flatMap({ UIFont(name: $0, size: size) }) ?? faces["Regular"].flatMap({ UIFont(name: $0, size: size) }) else { return nil }
            if italic {
                // Plex SC ships upright faces. Preserve emphasis with an explicit oblique descriptor.
                return UIFont(descriptor: font.fontDescriptor.addingAttributes([.matrix: NSValue(cgAffineTransform: CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0))]), size: size)
            }
            return font
        }
    }
}
