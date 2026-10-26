import Foundation
import AppKit

/// Parchment's standard look, drawn faintly in each box: SF Symbols and the system serif.
let ghosts = KitGhosts(
    symbol: { name in
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 96, weight: .regular)) else { return nil }
        let scale: CGFloat = 2
        let size = symbol.size
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        symbol.draw(in: CGRect(origin: .zero, size: size)) // template symbols draw in black
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    },
    serifFont: { size, bold in
        let system = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .semibold)
        if let descriptor = system.fontDescriptor.withDesign(.serif), let font = NSFont(descriptor: descriptor, size: size) {
            return font as CTFont
        }
        return CTFontCreateWithName((bold ? "Georgia-Bold" : "Georgia") as CFString, size, nil)
    })
