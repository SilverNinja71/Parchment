import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Draws BelloBook's Ship's Logbook app icon. Usage: swift Tools/make_icon.swift <output.png>

let size = 1024
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png")
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Top-left coordinates.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

// Warm cream-to-terracotta Ship's Log gradient background.
let background = CGGradient(colorsSpace: space, colors: [rgb(247, 239, 228), rgb(223, 184, 153), rgb(184, 107, 67)] as CFArray, locations: [0, 0.52, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 1024), options: [])

// Tilted warm off-white logbook sheet (#FBF9F5) with soft elevation shadow.
ctx.saveGState()
ctx.translateBy(x: 512, y: 520)
ctx.rotate(by: -0.07)
let sheet = CGRect(x: -290, y: -360, width: 580, height: 720)
ctx.setShadow(offset: CGSize(width: 0, height: 26), blur: 44, color: rgb(60, 25, 10, 0.35))
ctx.addPath(CGPath(roundedRect: sheet, cornerWidth: 42, cornerHeight: 42, transform: nil))
ctx.setFillColor(rgb(251, 249, 245))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// Subtle terracotta spine border.
ctx.setStrokeColor(rgb(139, 74, 46, 0.75))
ctx.setLineWidth(14)
ctx.addPath(CGPath(roundedRect: sheet, cornerWidth: 42, cornerHeight: 42, transform: nil))
ctx.strokePath()

// Soft slate-blue ruled lines (Style.paperLine).
ctx.setStrokeColor(rgb(90, 115, 150, 0.28))
ctx.setLineWidth(6)
for i in 0..<7 {
    let y = -180 + CGFloat(i) * 82
    ctx.move(to: CGPoint(x: -225, y: y))
    ctx.addLine(to: CGPoint(x: 225, y: y))
}
ctx.strokePath()

// MyScript Blue (#0A60FF) Ship's Compass / Helm Emblem.
ctx.setStrokeColor(rgb(10, 96, 255))
ctx.setLineWidth(20)
ctx.setLineCap(.round)
let helmCenter = CGPoint(x: 0, y: -95)
ctx.addEllipse(in: CGRect(x: helmCenter.x - 108, y: helmCenter.y - 108, width: 216, height: 216))
ctx.strokePath()

// Compass crosshairs & spokes.
ctx.setLineWidth(14)
for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 4) {
    let dx = CGFloat(cos(angle)) * 136
    let dy = CGFloat(sin(angle)) * 136
    ctx.move(to: CGPoint(x: helmCenter.x - dx * 0.32, y: helmCenter.y - dy * 0.32))
    ctx.addLine(to: CGPoint(x: helmCenter.x + dx, y: helmCenter.y + dy))
}
ctx.strokePath()

// Center hub dot.
ctx.setFillColor(rgb(10, 96, 255))
ctx.fillEllipse(in: CGRect(x: helmCenter.x - 24, y: helmCenter.y - 24, width: 48, height: 48))

// Verified Emerald Checkmark (#2E9452) at bottom of logbook page.
ctx.setStrokeColor(rgb(46, 148, 82))
ctx.setLineWidth(30)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: -135, y: 155))
ctx.addLine(to: CGPoint(x: -35, y: 245))
ctx.addLine(to: CGPoint(x: 155, y: 80))
ctx.strokePath()

ctx.restoreGState()

let image = ctx.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("Wrote \(output.path)")
