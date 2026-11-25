// Draws the Findy app icon and writes the PNG sizes the asset catalog needs.
//
// Usage: swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset

import AppKit

/// Draws the icon on a 1024-point canvas: a blue rounded square holding a window split in two
/// panes, the left one with a selected row.
func drawIcon(in context: CGContext) {
    let canvas: CGFloat = 1024
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [red / 255, green / 255, blue / 255, alpha])
            ?? CGColor(gray: 0, alpha: 1)
    }

    // macOS icon grid: the shape is inset 100 points and has a continuous corner.
    let body = CGRect(x: 100, y: 100, width: canvas - 200, height: canvas - 200)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow under the shape.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.30))
    context.addPath(bodyPath)
    context.setFillColor(color(30, 110, 235))
    context.fillPath()
    context.restoreGState()

    // Background gradient, lighter at the top.
    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(92, 178, 255), color(24, 98, 228)] as CFArray,
        locations: [0, 1])
    if let gradient {
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    }
    context.restoreGState()

    // The window.
    let window = CGRect(x: 222, y: 282, width: 580, height: 460)
    let windowPath = CGPath(roundedRect: window, cornerWidth: 52, cornerHeight: 52, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0, 30, 90, 0.35))
    context.addPath(windowPath)
    context.setFillColor(color(255, 255, 255))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(windowPath)
    context.clip()

    // Title bar.
    let titleBarHeight: CGFloat = 78
    context.setFillColor(color(232, 238, 248))
    context.fill(CGRect(x: window.minX, y: window.maxY - titleBarHeight, width: window.width, height: titleBarHeight))
    for (index, dot) in [color(255, 95, 87), color(254, 188, 46), color(40, 200, 64)].enumerated() {
        context.setFillColor(dot)
        context.fillEllipse(
            in: CGRect(
                x: window.minX + 34 + CGFloat(index) * 42, y: window.maxY - titleBarHeight / 2 - 13,
                width: 26, height: 26))
    }

    // Divider between the two panes.
    let contentTop = window.maxY - titleBarHeight
    context.setFillColor(color(206, 216, 232))
    context.fill(CGRect(x: window.midX - 3, y: window.minY, width: 6, height: contentTop - window.minY))

    // Rows: a small folder tab and a bar, three per pane. The second row on the left is selected.
    func row(x: CGFloat, y: CGFloat, width: CGFloat, selected: Bool) {
        if selected {
            let highlight = CGRect(x: x - 16, y: y - 16, width: width + 32, height: 72)
            context.addPath(CGPath(roundedRect: highlight, cornerWidth: 18, cornerHeight: 18, transform: nil))
            context.setFillColor(color(36, 122, 245))
            context.fillPath()
        }
        let ink = selected ? color(255, 255, 255) : color(96, 165, 250)
        let text = selected ? color(255, 255, 255, 0.92) : color(186, 200, 222)
        context.setFillColor(ink)
        context.addPath(
            CGPath(
                roundedRect: CGRect(x: x, y: y, width: 52, height: 40), cornerWidth: 8, cornerHeight: 8,
                transform: nil))
        context.addPath(
            CGPath(
                roundedRect: CGRect(x: x, y: y + 30, width: 26, height: 16), cornerWidth: 6, cornerHeight: 6,
                transform: nil))
        context.fillPath()
        context.setFillColor(text)
        context.addPath(
            CGPath(
                roundedRect: CGRect(x: x + 70, y: y + 10, width: width - 70, height: 20), cornerWidth: 10,
                cornerHeight: 10, transform: nil))
        context.fillPath()
    }

    let paneWidth = window.width / 2
    let rowWidth = paneWidth - 76
    for index in 0..<3 {
        let y = contentTop - 98 - CGFloat(index) * 100
        row(x: window.minX + 38, y: y, width: rowWidth, selected: index == 1)
        row(x: window.midX + 38, y: y, width: rowWidth - (index == 2 ? 60 : 0), selected: false)
    }
    context.restoreGState()
}

func png(pixels: Int) -> Data? {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)
    else { return nil }
    let context = graphics.cgContext
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: context)
    return bitmap.representation(using: .png, properties: [:])
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <AppIcon.appiconset>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        guard let data = png(pixels: points * scale) else {
            FileHandle.standardError.write(Data("cannot render \(name)\n".utf8))
            exit(1)
        }
        try data.write(to: output.appendingPathComponent(name))
        images.append([
            "idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name,
        ])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) images to \(output.path)")
