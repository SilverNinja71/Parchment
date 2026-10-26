import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Draws Parchment's default app icon.  Usage: swift Tools/make_icon.swift <output.png>

let size = 1024
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png")
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a) }

// Top-left coordinates.
ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)

// Warm leather background.
let background = CGGradient(colorsSpace: space, colors: [rgb(176, 98, 58), rgb(110, 52, 30)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [])

// A tilted sheet of parchment with a soft shadow.
ctx.saveGState()
ctx.translateBy(x: 512, y: 530); ctx.rotate(by: -0.10)
let sheet = CGRect(x: -300, y: -370, width: 600, height: 740)
ctx.setShadow(offset: CGSize(width: 0, height: 24), blur: 40, color: rgb(40, 15, 5, 0.45))
ctx.addPath(CGPath(roundedRect: sheet, cornerWidth: 36, cornerHeight: 36, transform: nil))
ctx.setFillColor(rgb(250, 240, 220)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
let paper = CGGradient(colorsSpace: space, colors: [rgb(253, 246, 230), rgb(240, 222, 190)] as CFArray, locations: [0, 1])!
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: sheet, cornerWidth: 36, cornerHeight: 36, transform: nil)); ctx.clip()
ctx.drawLinearGradient(paper, start: CGPoint(x: 0, y: -370), end: CGPoint(x: 0, y: 370), options: [])
ctx.restoreGState()

// Ruled lines.
ctx.setStrokeColor(rgb(196, 170, 130, 0.7)); ctx.setLineWidth(5)
for i in 0..<8 {
    let y = -230 + CGFloat(i) * 78
    ctx.move(to: CGPoint(x: -240, y: y)); ctx.addLine(to: CGPoint(x: 240, y: y))
}
ctx.strokePath()

// A handwritten flourish in ink.
ctx.setStrokeColor(rgb(58, 34, 22)); ctx.setLineWidth(22); ctx.setLineCap(.round); ctx.setLineJoin(.round)
let ink = CGMutablePath()
ink.move(to: CGPoint(x: -215, y: -40))
ink.addCurve(to: CGPoint(x: -120, y: -150), control1: CGPoint(x: -230, y: -120), control2: CGPoint(x: -170, y: -170))
ink.addCurve(to: CGPoint(x: -110, y: 10), control1: CGPoint(x: -70, y: -130), control2: CGPoint(x: -60, y: -20))
ink.addCurve(to: CGPoint(x: 10, y: -80), control1: CGPoint(x: -160, y: 40), control2: CGPoint(x: -40, y: -90))
ink.addCurve(to: CGPoint(x: 80, y: 10), control1: CGPoint(x: 60, y: -70), control2: CGPoint(x: 40, y: 10))
ink.addCurve(to: CGPoint(x: 215, y: -70), control1: CGPoint(x: 120, y: 10), control2: CGPoint(x: 170, y: -40))
ctx.addPath(ink); ctx.strokePath()
ctx.setLineWidth(14)
ctx.move(to: CGPoint(x: -200, y: 160)); ctx.addCurve(to: CGPoint(x: 160, y: 150), control1: CGPoint(x: -80, y: 120), control2: CGPoint(x: 40, y: 190))
ctx.strokePath()
ctx.restoreGState()

let image = ctx.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("Wrote \(output.path)")
