import Foundation
import UIKit
import CoreText
import AppBundle
import RGSimpleSettings

/// Registers unmodified OFL fonts per family/process, without changing the device's installed fonts.
public enum RGTypography {
    private static let registrationLock = NSLock()
    private static var registered: [RGFontFamily: [String: String]] = [:]

    private static func register(_ family: RGFontFamily, prefix: String) -> [String: String] {
        self.registrationLock.lock()
        defer { self.registrationLock.unlock() }
        if let faces = self.registered[family] { return faces }
        var faces: [String: String] = [:]
        for style in ["Regular", "Medium", "SemiBold", "Semibold", "Bold", "Italic", "MediumItalic", "SemiBoldItalic", "BoldItalic", "It", "MediumIt", "SemiboldIt", "BoldIt"] {
            if let path = getAppBundle().path(forResource: "\(prefix)-\(style)", ofType: "ttf") {
                let url = URL(fileURLWithPath: path) as CFURL
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
