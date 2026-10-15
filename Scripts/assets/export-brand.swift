// Reproducible asset exports from the existing Rasc symbol, never a new shape.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let masterURL = root.appendingPathComponent("Rasc/Resources/Brand/rasc-symbol-master.png")
guard let source = CGImageSourceCreateWithURL(masterURL as CFURL, nil),
      let master = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Missing canonical symbol") }
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func context(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
let scan = context(master.width)
scan.draw(master, in: CGRect(x: 0, y: 0, width: master.width, height: master.height))
let bytes = scan.data!.assumingMemoryBound(to: UInt8.self)
// The legacy raster contains faint, detached export debris. Keep the two actual
// connected symbol forms, retaining their original anti-aliased edge pixels.
let width = master.width, height = master.height
var visited = [Bool](repeating: false, count: width * height)
var components: [[Int]] = []
for pixel in 0..<(width * height) where !visited[pixel] && bytes[pixel * 4 + 3] >= 32 {
    var component = [pixel], cursor = 0
    visited[pixel] = true
    while cursor < component.count {
        let current = component[cursor]; cursor += 1
        let x = current % width, y = current / width
        for dy in -1...1 {
            for dx in -1...1 {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let next = ny * width + nx
                if !visited[next] && bytes[next * 4 + 3] >= 32 {
                    visited[next] = true; component.append(next)
                }
            }
        }
    }
    components.append(component)
}
let forms = components.sorted { $0.count > $1.count }.prefix(2)
precondition(forms.count == 2 && forms.allSatisfy { $0.count > 10_000 }, "Canonical symbol must have two substantial forms")
var retained = [Bool](repeating: false, count: width * height)
for form in forms {
    for pixel in form {
        let x = pixel % width, y = pixel / width
        for dy in -1...1 {
            for dx in -1...1 {
                let nx = x + dx, ny = y + dy
                if nx >= 0, nx < width, ny >= 0, ny < height { retained[ny * width + nx] = true }
            }
        }
    }
}
var minX = width, minY = height, maxX = 0, maxY = 0
for pixel in 0..<(width * height) {
    if !retained[pixel] {
        for channel in 0..<4 { bytes[pixel * 4 + channel] = 0 }
    } else if bytes[pixel * 4 + 3] > 0 {
        let x = pixel % width, y = pixel / width
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
let bounds = CGRect(x: minX, y: height - maxY - 1, width: maxX - minX + 1, height: maxY - minY + 1)
let symbol = scan.makeImage()!.cropping(to: bounds)!
let graphite = CGColor(srgbRed: 0.16, green: 0.15, blue: 0.18, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
func drawSymbol(in output: CGContext, rect: CGRect, color: CGColor) {
    output.saveGState()
    output.beginTransparencyLayer(auxiliaryInfo: nil)
    output.interpolationQuality = .high
    output.draw(symbol, in: rect)
    output.setBlendMode(.sourceIn)
    output.setFillColor(color)
    output.fill(rect)
    output.endTransparencyLayer()
    output.restoreGState()
}
func export(_ image: CGImage, to path: String) {
    let url = root.appendingPathComponent(path)
    guard let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Cannot export \(path)") }
    CGImageDestinationAddImage(output, image, nil)
    precondition(CGImageDestinationFinalize(output))
}
let assets = "Rasc/Resources/Assets.xcassets"
for (name, color) in [("rasc-dark", graphite), ("rasc-light", white)] {
    let output = context(512)
    drawSymbol(in: output, rect: CGRect(x: 16, y: 16, width: 480, height: 480), color: color)
    export(output.makeImage()!, to: "\(assets)/RascLogo.imageset/\(name).png")
    // Home renders the identity at 24 pt. Export its exact backing sizes directly
    // from the retained source alpha, avoiding a second runtime reduction of 512 px.
    for scale in [1, 2] {
        let edge = 24 * scale
        let compact = context(edge)
        let inset = CGFloat(edge) / 32
        drawSymbol(in: compact,
                   rect: CGRect(x: inset, y: inset,
                                width: CGFloat(edge) - inset * 2,
                                height: CGFloat(edge) - inset * 2),
                   color: color)
        let suffix = scale == 2 ? "@2x" : ""
        export(compact.makeImage()!, to: "\(assets)/RascLogoCompact.imageset/\(name)\(suffix).png")
    }
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let output = context(size)
        let edge = CGFloat(size)
        // A quiet native icon plate keeps the unchanged symbol legible in Finder.
        let plate = CGRect(x: edge * 0.06, y: edge * 0.06, width: edge * 0.88, height: edge * 0.88)
        output.setFillColor(CGColor(srgbRed: 0.976, green: 0.965, blue: 0.980, alpha: 1))
        output.addPath(CGPath(roundedRect: plate, cornerWidth: edge * 0.19, cornerHeight: edge * 0.19, transform: nil))
        output.fillPath()
        output.setStrokeColor(CGColor(srgbRed: 0.83, green: 0.80, blue: 0.85, alpha: 0.7))
        output.setLineWidth(max(0.5, edge / 1024))
        output.addPath(CGPath(roundedRect: plate, cornerWidth: edge * 0.19, cornerHeight: edge * 0.19, transform: nil))
        output.strokePath()
        drawSymbol(in: output, rect: CGRect(x: edge * 0.23, y: edge * 0.23, width: edge * 0.54, height: edge * 0.54), color: graphite)
        let suffix = scale == 2 ? "@2x" : ""
        export(output.makeImage()!, to: "\(assets)/AppIcon.appiconset/icon_\(points)x\(points)\(suffix).png")
    }
}
print("Exported logo appearances, compact 1x/2x logos and 10 AppIcon sizes from the canonical symbol alpha.")
