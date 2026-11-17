// Reproducible asset exports from the approved Rasc Twin Fish master.
// The master is a faithful raster of candidate 02; this script only trims
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

func context(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// Trim transparent padding only; the silhouette pixels are retained unchanged.
let scan = context(master.width)
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
let bounds = CGRect(x: minX, y: master.height - maxY - 1,
                    width: maxX - minX + 1, height: maxY - minY + 1)
let symbol = master.cropping(to: bounds)!

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

// Menu bar stays a monochrome template, now using the approved mark.
for scale in [1, 2] {
    let edge = 32 * scale
    let output = context(edge)
    let inset = CGFloat(edge) / 16
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
    // Slightly larger and optically high compared with the old standalone mark.
    drawSymbol(in: output,
               rect: CGRect(x: edge * 0.20, y: edge * 0.18,
                            width: edge * 0.60, height: edge * 0.60),
               color: graphite)
    return output.makeImage()!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        var icon = renderAppIcon(size)
        // The 16 px 1x tile needs a 2x render downsampled once; drawing the
        // silhouette directly at 16 px leaves it too faint to read.
        if points == 16 && scale == 1 {
            let downsampled = context(size)
            downsampled.interpolationQuality = .high
            downsampled.draw(renderAppIcon(size * 2), in: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
            icon = downsampled.makeImage()!
        }
        let suffix = scale == 2 ? "@2x" : ""
        export(icon, to: "\(assets)/AppIcon.appiconset/icon_\(points)x\(points)\(suffix).png")
    }
}
print("Exported Twin Fish logo appearances, 24 pt compact logos, menu-bar template and 10 AppIcon sizes from the approved master.")
