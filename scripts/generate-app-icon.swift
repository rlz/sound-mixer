import AppKit
import CoreGraphics

let size = 1024
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmap = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
bitmap.setAllowsAntialiasing(true)
bitmap.setShouldAntialias(true)

// Leave the same optical margin as neighboring macOS Dock icons.
bitmap.translateBy(x: 512, y: 512)
bitmap.scaleBy(x: 0.86, y: 0.86)
bitmap.translateBy(x: -512, y: -512)

let iconBounds = CGRect(x: 24, y: 24, width: 976, height: 976)
let tile = CGPath(roundedRect: iconBounds, cornerWidth: 218, cornerHeight: 218, transform: nil)
bitmap.addPath(tile)
bitmap.clip()
bitmap.setFillColor(CGColor(red: 0.22, green: 0.76, blue: 0.96, alpha: 1))
bitmap.fill(iconBounds)

let ink = CGColor(red: 0.035, green: 0.12, blue: 0.22, alpha: 1)
let centers: [CGFloat] = [300, 512, 724]
let knobYs: [CGFloat] = [650, 390, 590]
bitmap.setStrokeColor(ink)
bitmap.setFillColor(ink)
bitmap.setLineWidth(42)
bitmap.setLineCap(.round)
for (x, knobY) in zip(centers, knobYs) {
    bitmap.move(to: CGPoint(x: x, y: 250))
    bitmap.addLine(to: CGPoint(x: x, y: 774))
    bitmap.strokePath()
    bitmap.fillEllipse(in: CGRect(x: x - 84, y: knobY - 48, width: 168, height: 96))
}

let image = bitmap.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: output)
