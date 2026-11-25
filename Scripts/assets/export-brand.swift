// Reproducible asset exports from the accepted corrected Rasc Twin Fish master.
// The master contains the approved Twin Fish with an inferred upper-left tail
// completion accepted on 2026-11-23; this script only trims
// transparent padding, recolors the silhouette, and places it at asset sizes.
// It never redraws, simplifies, forces an R, or adds texture.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let masterURL = root.appendingPathComponent("Rasc/Resources/Brand/rasc-twin-fish-master.png")
guard let source = CGImageSourceCreateWithURL(masterURL as CFURL, nil),
      let master = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Missing approved Rasc Twin Fish master")
}
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func context(width: Int, height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func context(_ size: Int) -> CGContext {
    context(width: size, height: size)
}

// Trim transparent padding only; the silhouette pixels are retained unchanged.
let scan = context(width: master.width, height: master.height)
scan.draw(master, in: CGRect(x: 0, y: 0, width: master.width, height: master.height))
let bytes = scan.data!.assumingMemoryBound(to: UInt8.self)
var minX = master.width, minY = master.height, maxX = 0, maxY = 0
for y in 0..<master.height {
    for x in 0..<master.width {
        let i = (y * master.width + x) * 4
        if bytes[i + 3] > 8 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
precondition(maxX > minX && maxY > minY, "Master must contain a silhouette")
let bounds = CGRect(x: minX, y: minY,
                    width: maxX - minX + 1, height: maxY - minY + 1)
let symbol = master.cropping(to: bounds)!

/// Darkness-weighted center of mass in top-left bitmap coordinates (x right, y down).
func symbolCenterOfMass() -> CGPoint {
    let scan = context(width: symbol.width, height: symbol.height)
    scan.draw(symbol, in: CGRect(x: 0, y: 0, width: symbol.width, height: symbol.height))
    let bytes = scan.data!.assumingMemoryBound(to: UInt8.self)
    var sumX = 0.0, sumY = 0.0, sumW = 0.0
    for y in 0..<symbol.height {
        for x in 0..<symbol.width {
            let i = (y * symbol.width + x) * 4
            let alpha = Double(bytes[i + 3])
            guard alpha > 8 else { continue }
            let luminance = 0.299 * Double(bytes[i]) + 0.587 * Double(bytes[i + 1]) + 0.114 * Double(bytes[i + 2])
            let weight = (255 - luminance) * (alpha / 255)
            sumX += Double(x) * weight
            sumY += Double(y) * weight
            sumW += weight
        }
    }
    precondition(sumW > 0)
    return CGPoint(x: sumX / sumW, y: sumY / sumW)
}

let symbolCOM = symbolCenterOfMass()

let graphite = CGColor(srgbRed: 0.141, green: 0.141, blue: 0.137, alpha: 1) // #242423
let warmPaper = CGColor(srgbRed: 0.969, green: 0.961, blue: 0.941, alpha: 1) // #F7F5F0
let templateWhite = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

/// Aspect-fits the unchanged silhouette inside `rect` and recolors its alpha.
func drawSymbol(in output: CGContext, rect: CGRect, color: CGColor) {
    let scale = min(rect.width / CGFloat(symbol.width), rect.height / CGFloat(symbol.height))
    let w = CGFloat(symbol.width) * scale
    let h = CGFloat(symbol.height) * scale
    let dest = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    output.saveGState()
    output.beginTransparencyLayer(auxiliaryInfo: nil)
    output.interpolationQuality = .high
    output.draw(symbol, in: dest)
    output.setBlendMode(.sourceIn)
    output.setFillColor(color)
    output.fill(dest)
    output.endTransparencyLayer()
    output.restoreGState()
}

/// Scales the mark to fit `plate` and places it with a balanced 50/50 blend of geometric
/// bounding-box center and optical center of mass so margins and visual weight both feel centered.
func drawSymbolOpticallyCentered(in output: CGContext, plate: CGRect, color: CGColor) {
    let scale = min(plate.width / CGFloat(symbol.width), plate.height / CGFloat(symbol.height))
    let w = CGFloat(symbol.width) * scale
    let h = CGFloat(symbol.height) * scale
    let comX = symbolCOM.x / CGFloat(symbol.width)
    let comYFromTop = symbolCOM.y / CGFloat(symbol.height)
    let anchorX = 0.5 + 0.5 * (comX - 0.5)
    let anchorYFromTop = 0.5 + 0.5 * (comYFromTop - 0.5)
    let destX = plate.midX - anchorX * w
    let destY = plate.midY - (1 - anchorYFromTop) * h
    let dest = CGRect(x: destX, y: destY, width: w, height: h)
    output.saveGState()
    output.beginTransparencyLayer(auxiliaryInfo: nil)
    output.interpolationQuality = .high
    output.draw(symbol, in: dest)
    output.setBlendMode(.sourceIn)
    output.setFillColor(color)
    output.fill(dest)
    output.endTransparencyLayer()
    output.restoreGState()
}

func export(_ image: CGImage, to path: String) {
    let url = root.appendingPathComponent(path)
    guard let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot export \(path)")
    }
    CGImageDestinationAddImage(output, image, nil)
    precondition(CGImageDestinationFinalize(output))
}

let assets = "Rasc/Resources/Assets.xcassets"

// Large identity: graphite on light surfaces, warm paper on dark surfaces.
for (name, color) in [("rasc-dark", graphite), ("rasc-light", warmPaper)] {
    let output = context(512)
    drawSymbol(in: output, rect: CGRect(x: 16, y: 16, width: 480, height: 480), color: color)
    export(output.makeImage()!, to: "\(assets)/RascLogo.imageset/\(name).png")

    // Home renders the identity at 24 pt; export its exact backing sizes directly.
    for scale in [1, 2] {
        let edge = 24 * scale
        let compact = context(edge)
        // 1.5 px of physical headroom at both scales keeps the thin upper tail
        // clear of the 24 px asset bounds.
        let inset: CGFloat = scale == 1 ? 1.5 : 3
        drawSymbol(in: compact,
                   rect: CGRect(x: inset, y: inset,
                                width: CGFloat(edge) - inset * 2,
                                height: CGFloat(edge) - inset * 2),
                   color: color)
        let suffix = scale == 2 ? "@2x" : ""
        export(compact.makeImage()!, to: "\(assets)/RascLogoCompact.imageset/\(name)\(suffix).png")
    }
}

// Menu bar stays a monochrome template at native 22 pt status-bar height (1:1 pixels,
// ~17 pt mark height) so NSStatusBarButton does not downscale a 32 pt asset.
for scale in [1, 2] {
    let edge = 22 * scale
    let output = context(edge)
    let inset = 2.5 * CGFloat(scale)
    drawSymbol(in: output,
               rect: CGRect(x: inset, y: inset,
                            width: CGFloat(edge) - inset * 2,
                            height: CGFloat(edge) - inset * 2),
               color: templateWhite)
    let suffix = scale == 2 ? "@2x" : ""
    export(output.makeImage()!, to: "\(assets)/MenuBarIcon.imageset/menubar\(suffix).png")
}

// App icon keeps the existing native plate. The fish gets its own composed
// scale/optical centering; standalone Home and the Dock are different uses.
func renderAppIcon(_ size: Int) -> CGImage {
    let output = context(size)
    let edge = CGFloat(size)
    let plate = CGRect(x: edge * 0.06, y: edge * 0.06, width: edge * 0.88, height: edge * 0.88)
    output.setFillColor(CGColor(srgbRed: 0.976, green: 0.965, blue: 0.980, alpha: 1))
    output.addPath(CGPath(roundedRect: plate, cornerWidth: edge * 0.19, cornerHeight: edge * 0.19, transform: nil))
    output.fillPath()
    output.setStrokeColor(CGColor(srgbRed: 0.83, green: 0.80, blue: 0.85, alpha: 0.7))
    output.setLineWidth(max(0.5, edge / 1024))
    output.addPath(CGPath(roundedRect: plate, cornerWidth: edge * 0.19, cornerHeight: edge * 0.19, transform: nil))
    output.strokePath()
    // Inset symmetrically inside the plate; optical centering corrects mark asymmetry.
    let inset = edge * 0.14
    let symbolPlate = plate.insetBy(dx: inset, dy: inset)
    drawSymbolOpticallyCentered(in: output, plate: symbolPlate, color: graphite)
    return output.makeImage()!
}

let appIconMaster = renderAppIcon(1024)
export(appIconMaster, to: "\(assets)/AppIcon.appiconset/icon_512x512@2x.png")
print("Exported Twin Fish logo appearances, 24 pt compact logos, menu-bar template, and the 1024 px AppIcon master.")
print("Downsample the remaining AppIcon slots from icon_512x512@2x.png with Lanczos.")
