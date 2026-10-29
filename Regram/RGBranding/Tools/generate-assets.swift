// Rebuild the approved B1/B2 artwork from one editable vector geometry per design.
// Run from the repository root: swift Regram/RGBranding/Tools/generate-assets.swift
import Foundation
import CoreGraphics
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let branding = root.appendingPathComponent("Regram/RGBranding")
let manager = FileManager.default
let geometry = try JSONSerialization.jsonObject(with: Data(contentsOf: branding.appendingPathComponent("Artwork/Geometry.json"))) as! [String: Any]

enum Design: String, CaseIterable {
    case conversation = "RGConversation"
    case azure = "RGAzure"
    case iris = "RGIris"
    case mint = "RGMint"
    case gathering = "RGGathering"
    case amber = "RGAmber"
    case nebula = "RGNebula"
    case jade = "RGJade"

    var isGathering: Bool {
        switch self {
        case .gathering, .amber, .nebula, .jade: return true
        default: return false
        }
    }
}

enum Appearance: String, CaseIterable {
    case light, dark
    func background(_ design: Design) -> String {
        self == .light ? "F3EADC" : "242426"
    }
    func foreground(_ design: Design) -> String {
        if self == .dark { return "F8F1E5" }
        switch design {
        case .conversation: return "14243E"
        case .azure: return "15385B"
        case .iris: return "38304C"
        case .mint: return "183D36"
        case .gathering: return "1B1B19"
        case .amber: return "A96A24"
        case .nebula: return "6A5ACD"
        case .jade: return "1C8874"
        }
    }
    func badge(_ design: Design) -> String { background(design) }
    func accent(_ design: Design) -> String {
        switch design {
        case .conversation: return "FE683B"
        case .azure: return "268BEB"
        case .iris: return "8D6ADE"
        case .mint: return "29A58A"
        case .amber: return "A96A24"
        case .nebula: return "6A5ACD"
        case .jade: return "1C8874"
        default: return foreground(design)
        }
    }
    func overlap(_ design: Design) -> String {
        switch design {
        case .azure: return "BBDCFB"
        case .iris: return "D9CBF8"
        case .mint: return "C4EADF"
        default: return "FEC5A7"
        }
    }
    var catalogAppearances: [[String: String]] {
        self == .light ? [] : [["appearance": "luminosity", "value": self.rawValue]]
    }
}

func color(_ hex: String) -> CGColor {
    let value = UInt32(hex, radix: 16)!
    return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [
        CGFloat((value >> 16) & 255) / 255, CGFloat((value >> 8) & 255) / 255,
        CGFloat(value & 255) / 255, 1
    ])!
}

struct Layer {
    let path: CGPath
    let fill: String
    var stroke: String? = nil
    var width: CGFloat = 0
}

// These are the actual contours of the two approved original designs, not replacement shapes.
func traced(_ name: String, contourIndex: Int? = nil) -> CGPath {
    let path = CGMutablePath()
    for (index, points) in (geometry[name] as! [[[Double]]]).enumerated() {
        if let contourIndex, index != contourIndex { continue }
        guard let first = points.first else { continue }
        path.move(to: CGPoint(x: first[0], y: first[1]))
        if name.contains("wordmark") {
            for point in points.dropFirst() { path.addLine(to: CGPoint(x: point[0], y: point[1])) }
        } else {
            // Restore smooth vector curves from raster contours while preserving deliberate corners.
            let p = points.map { CGPoint(x: $0[0], y: $0[1]) }
            let count = p.count
            let tangents: [CGPoint] = p.indices.map { i in
                let before = p[(i + count - 1) % count], after = p[(i + 1) % count]
                let ax = p[i].x - before.x, ay = p[i].y - before.y
                let bx = after.x - p[i].x, by = after.y - p[i].y
                let a = hypot(ax, ay), b = hypot(bx, by)
                guard a > 0, b > 0, (ax * bx + ay * by) / (a * b) > 0.55 else { return .zero }
                let x = ax / a + bx / b, y = ay / a + by / b, length = hypot(x, y)
                return CGPoint(x: x / length, y: y / length)
            }
            for i in p.indices {
                let j = (i + 1) % count
                let length = hypot(p[j].x - p[i].x, p[j].y - p[i].y) / 3
                path.addCurve(to: p[j], control1: CGPoint(x: p[i].x + tangents[i].x * length, y: p[i].y + tangents[i].y * length), control2: CGPoint(x: p[j].x - tangents[j].x * length, y: p[j].y - tangents[j].y * length))
            }
        }
        path.closeSubpath()
    }
    return path
}

func layers(_ design: Design, _ appearance: Appearance, background: String) -> [Layer] {
    switch design {
    case .conversation, .azure, .iris, .mint:
        return [
            Layer(path: traced("conversation-rear"), fill: appearance.foreground(design)),
            Layer(path: traced("conversation-front"), fill: appearance.accent(design)),
            Layer(path: traced("conversation-overlap"), fill: appearance.overlap(design))
        ]
    case .gathering, .amber, .nebula, .jade:
        if appearance == .dark && design != .gathering {
            // Keep the approved bottom contour as a color accent; the other shapes and lettering stay cream.
            return (geometry["gathering-mark"] as! [[[Double]]]).indices.map { index in
                Layer(path: traced("gathering-mark", contourIndex: index), fill: index == 3 ? appearance.accent(design) : appearance.foreground(design))
            }
        }
        return [Layer(path: traced("gathering-mark"), fill: appearance.foreground(design))]
    }
}

func drawMark(_ design: Design, _ appearance: Appearance, background: String, context: CGContext) {
    for layer in layers(design, appearance, background: background) {
        if let stroke = layer.stroke {
            context.addPath(layer.path)
            context.setStrokeColor(color(stroke))
            context.setLineWidth(layer.width)
            context.setLineJoin(.round)
            context.strokePath()
        }
        context.addPath(layer.path)
        context.setFillColor(color(layer.fill))
        context.fillPath()
    }
}

func writeJSON(_ data: [String: Any], to path: URL) throws {
    try manager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoded = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
    try encoded.write(to: path)
}

func raster(to path: URL, size: CGSize, scale: Int = 1, opaque: Bool = true, draw: (CGContext) -> Void) throws {
    let width = Int(size.width) * scale, height = Int(size.height) * scale
    let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue)!
    context.setAllowsAntialiasing(true)
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    draw(context)
    try manager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(path as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
}

// Maintain one geometry and derive both explicit appearances; do not rely on OS recoloring.
func icon(_ design: Design, _ appearance: Appearance = .light, path: URL, size: Int = 1024) throws {
    try raster(to: path, size: CGSize(width: size, height: size)) { context in
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        context.setFillColor(color(appearance.background(design)))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        drawMark(design, appearance, background: appearance.background(design), context: context)
    }
}

func badge(_ design: Design, _ appearance: Appearance, path: URL, scale: Int) throws {
    try raster(to: path, size: CGSize(width: 112, height: 28), scale: scale, opaque: false) { context in
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 112, height: 28), cornerWidth: 14, cornerHeight: 14, transform: nil))
        context.setFillColor(color(appearance.badge(design)))
        context.fillPath()
        context.saveGState()
        context.translateBy(x: 4, y: 0)
        context.scaleBy(x: 28 / 1024, y: 28 / 1024)
        drawMark(design, appearance, background: appearance.badge(design), context: context)
        context.restoreGState()
        // Preserve the approved original lettering too; no substituted font or casing.
        let wordmark = traced(design.isGathering ? "gathering-wordmark" : "conversation-wordmark")
        let bounds = wordmark.boundingBoxOfPath
        let ratio = 68 / bounds.width
        context.translateBy(x: 35, y: (28 - bounds.height * ratio) / 2)
        context.scaleBy(x: ratio, y: ratio)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.addPath(wordmark)
        context.setFillColor(color(appearance.foreground(design)))
        context.fillPath()
    }
}

func svgPath(_ path: CGPath) -> String {
    var pieces: [String] = []
    func point(_ p: CGPoint) -> String { String(format: "%.2f %.2f", Double(p.x), Double(p.y)) }
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: pieces.append("M " + point(e.points[0]))
        case .addLineToPoint: pieces.append("L " + point(e.points[0]))
        case .addQuadCurveToPoint: pieces.append("Q " + point(e.points[0]) + " " + point(e.points[1]))
        case .addCurveToPoint: pieces.append("C " + point(e.points[0]) + " " + point(e.points[1]) + " " + point(e.points[2]))
        case .closeSubpath: pieces.append("Z")
        @unknown default: preconditionFailure("Unknown path element")
        }
    }
    return pieces.joined(separator: " ")
}

let info: [String: Any] = ["author": "regram", "version": 1]
try writeJSON(["info": info], to: branding.appendingPathComponent("AppIcons.xcassets/Contents.json"))
try writeJSON(["info": info], to: branding.appendingPathComponent("Images.xcassets/Contents.json"))

for design in Design.allCases {
    var appImages: [[String: Any]] = [], previews: [[String: Any]] = [], badges: [[String: Any]] = []
    for appearance in Appearance.allCases {
        let name = design.rawValue + "-" + appearance.rawValue + ".png"
        var appImage: [String: Any] = ["filename": name, "idiom": "universal", "platform": "ios", "size": "1024x1024"]
        var preview: [String: Any] = ["filename": name, "idiom": "universal"]
        if appearance == .dark {
            appImage["appearances"] = appearance.catalogAppearances
            preview["appearances"] = appearance.catalogAppearances
        }
        appImages.append(appImage)
        previews.append(preview)
        try icon(design, appearance, path: branding.appendingPathComponent("AppIcons.xcassets/\(design.rawValue).appiconset/\(name)"))
        try icon(design, appearance, path: branding.appendingPathComponent("Images.xcassets/\(design.rawValue)Preview.imageset/\(name)"), size: 256)
        // Both badge appearances share one asset name and one saved style selection.
        for scale in 1...3 {
            let filename = "\(design.rawValue)Badge-\(appearance.rawValue)@\(scale)x.png"
            var item: [String: Any] = ["filename": filename, "idiom": "universal", "scale": "\(scale)x"]
            if appearance == .dark { item["appearances"] = appearance.catalogAppearances }
            badges.append(item)
            try badge(design, appearance, path: root.appendingPathComponent("Regram/RGAppBadgeAssets/Images.xcassets/\(design.rawValue)Badge.imageset/\(filename)"), scale: scale)
        }
        let paths = layers(design, appearance, background: appearance.background(design)).map { layer -> String in
            let stroke = layer.stroke.map { " stroke=\"#\($0)\" stroke-width=\"\(layer.width)\" stroke-linejoin=\"round\" paint-order=\"stroke fill\"" } ?? ""
            return "<path fill=\"#\(layer.fill)\"\(stroke) d=\"\(svgPath(layer.path))\"/>"
        }.joined(separator: "\n")
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\"><rect width=\"1024\" height=\"1024\" fill=\"#\(appearance.background(design))\"/>\n\(paths)\n</svg>\n"
        let path = branding.appendingPathComponent("Artwork/\(design.rawValue)-\(appearance.rawValue).svg")
        try manager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try svg.write(to: path, atomically: true, encoding: .utf8)
    }
    try writeJSON(["images": appImages, "info": info], to: branding.appendingPathComponent("AppIcons.xcassets/\(design.rawValue).appiconset/Contents.json"))
    try writeJSON(["images": previews, "info": info], to: branding.appendingPathComponent("Images.xcassets/\(design.rawValue)Preview.imageset/Contents.json"))
    try writeJSON(["images": badges, "info": info], to: root.appendingPathComponent("Regram/RGAppBadgeAssets/Images.xcassets/\(design.rawValue)Badge.imageset/Contents.json"))
    // Remove only the previously exported custom tinted appearance.
    for retired in ["tinted"] {
        for relativePath in ["AppIcons.xcassets/\(design.rawValue).appiconset/\(design.rawValue)-\(retired).png",
                             "Images.xcassets/\(design.rawValue)Preview.imageset/\(design.rawValue)-\(retired).png",
                             "Artwork/\(design.rawValue)-\(retired).svg"] {
            let path = branding.appendingPathComponent(relativePath)
            if manager.fileExists(atPath: path.path) { try manager.removeItem(at: path) }
        }
    }
}

// Raster alternatives retain their original artwork. Only Classic derives a gray-paper dark rendition.
for iconName in ["RGClassic", "RGXChat"] {
    let source = branding.appendingPathComponent("Artwork/\(iconName)-original.png")
    let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(source as CFURL, nil)!, 0, nil)!
    for (catalog, size) in [("AppIcons.xcassets/\(iconName).appiconset", 1024), ("Images.xcassets/\(iconName)Preview.imageset", 256)] {
        var images: [[String: Any]] = []
        for appearance in Appearance.allCases {
            let name = "\(iconName)-\(appearance.rawValue).png"
            var entry: [String: Any] = ["filename": name, "idiom": "universal"]
            if size == 1024 { entry["platform"] = "ios"; entry["size"] = "1024x1024" }
            if appearance == .dark { entry["appearances"] = appearance.catalogAppearances }
            images.append(entry)
            try raster(to: branding.appendingPathComponent(catalog + "/" + name), size: CGSize(width: size, height: size)) { context in
                context.translateBy(x: 0, y: CGFloat(size)); context.scaleBy(x: 1, y: -1)
                let rect = CGRect(x: 0, y: 0, width: size, height: size)
                context.setFillColor(color("FFFFFF")); context.fill(rect)
                context.draw(image, in: rect)
                if iconName == "RGClassic" && appearance == .dark {
                    context.setBlendMode(.multiply)
                    context.setFillColor(color("E5E5EA")); context.fill(rect)
                }
            }
        }
        try writeJSON(["images": images, "info": info], to: branding.appendingPathComponent(catalog + "/Contents.json"))
    }
}

// Shared product surfaces use the primary B1 identity too.
for folder in ["Regram/RGSettingsUI/Images.xcassets/RegramSettings.imageset", "Regram/RGSettingsUI/Images.xcassets/RegramPro.imageset", "Telegram/WidgetKitWidget/WidgetImages.xcassets/RegramUpdateIcon.imageset"] {
    var images: [[String: Any]] = []
    for appearance in Appearance.allCases {
        let name = "Regram-\(appearance.rawValue).png"
        var image: [String: Any] = ["filename": name, "idiom": "universal"]
        if appearance == .dark { image["appearances"] = appearance.catalogAppearances }
        images.append(image)
        try icon(.conversation, appearance, path: root.appendingPathComponent(folder + "/" + name))
    }
    try writeJSON(["images": images, "info": info], to: root.appendingPathComponent(folder + "/Contents.json"))
}
for folder in ["Telegram/Watch/App/Assets.xcassets/AppIcon.appiconset", "Telegram/WatchApp/tgwatch Watch App/Assets.xcassets/AppIcon.appiconset"] {
    try icon(.conversation, path: root.appendingPathComponent(folder + "/Regram.png"))
}
print("Exported explicit light/dark app icons, matching previews and 112×28pt badges from the shared geometry.")
