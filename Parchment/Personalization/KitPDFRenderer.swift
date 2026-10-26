import Foundation
import CoreGraphics
import CoreText

// Shared with the Mac tool in Tools/KitGen: Foundation, CoreGraphics and CoreText only.

/// What Parchment looks like before it's personalized, supplied by the platform
/// (UIKit in the app, AppKit in the Mac tool). The kit draws it faintly in every box
/// so you can see what you're replacing, or trace over it.
struct KitGhosts {
    /// The standard icon artwork (an SF Symbol), drawn black on transparent.
    var symbol: (_ name: String) -> CGImage?
    /// The serif font Parchment uses for its name and notebook titles.
    var serifFont: (_ size: CGFloat, _ bold: Bool) -> CTFont
}

/// Draws the blank Parchment Personalization Kit as a PDF.
enum KitPDFRenderer {
    private static let ink = CGColor(red: 0.20, green: 0.16, blue: 0.12, alpha: 1)
    private static let muted = CGColor(red: 0.45, green: 0.40, blue: 0.34, alpha: 1)
    private static let accent = CGColor(red: 0.545, green: 0.290, blue: 0.180, alpha: 1)
    private static let boxStroke = CGColor(red: 0.74, green: 0.62, blue: 0.46, alpha: 1)
    private static let boxFill = CGColor(red: 0.995, green: 0.982, blue: 0.955, alpha: 1)
    private static let guide = CGColor(red: 0.80, green: 0.72, blue: 0.60, alpha: 1)
    /// How strongly the standard look shows through: visible, but clearly not your ink.
    private static let ghostAlpha: CGFloat = 0.17

    static func makePDF(ghosts: KitGhosts? = nil) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: KitLayout.pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: "Parchment Personalization Kit",
            kCGPDFContextCreator: "Parchment",
            kCGPDFContextSubject: "Draw in each box, then tap Apply in Parchment.",
            kCGPDFContextKeywords: KitLayout.keyword,
        ]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else { return Data() }

        for (pageIndex, page) in KitLayout.pages.enumerated() {
            context.beginPDFPage(nil)
            // Work in top-left coordinates like the layout.
            context.translateBy(x: 0, y: KitLayout.pageSize.height)
            context.scaleBy(x: 1, y: -1)
            drawPage(pageIndex, title: page.title, subtitle: page.subtitle, ghosts: ghosts, in: context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private static func drawPage(_ index: Int, title: String, subtitle: String, ghosts: KitGhosts?, in context: CGContext) {
        let width = KitLayout.pageSize.width
        let margin = KitLayout.margin

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: KitLayout.pageSize))

        // Header.
        text("PARCHMENT · PERSONALIZATION KIT", at: CGPoint(x: margin, y: 52), font: "AvenirNext-DemiBold", size: 9, color: accent, in: context)
        text("\(index + 1) / \(KitLayout.pages.count)", at: CGPoint(x: width - margin, y: 52), font: "AvenirNext-Regular", size: 9, color: muted, alignRight: true, in: context)
        text(title, at: CGPoint(x: margin, y: 88), font: "Georgia-Bold", size: 26, color: ink, in: context)
        text(subtitle, at: CGPoint(x: margin, y: 110), font: "AvenirNext-Regular", size: 11, color: muted, in: context)

        // Boxes.
        for slot in KitLayout.slots where slot.page == index {
            drawBox(slot, ghosts: ghosts, in: context)
        }

        // Footer.
        context.setStrokeColor(guide)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: 758))
        context.addLine(to: CGPoint(x: width - margin, y: 758))
        context.strokePath()
        let footer = ghosts == nil
            ? "Draw inside the dashed boxes with your Apple Pencil. Ink outside a box is ignored. Tap Apply when you're done."
            : "The faint drawings show Parchment's standard look — draw over them or ignore them. Ink outside a box is ignored."
        text(footer, at: CGPoint(x: margin, y: 774), font: "AvenirNext-Regular", size: 8.5, color: muted, in: context)
    }

    private static func drawBox(_ slot: KitSlot, ghosts: KitGhosts?, in context: CGContext) {
        let rect = slot.rect
        let path = CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        context.addPath(path)
        context.setFillColor(boxFill)
        context.fillPath()

        if let ghosts { drawGhost(slot, ghosts: ghosts, clippedTo: path, in: context) }

        if slot.kind == .glyph {
            for (fraction, dashed) in [(KitLayout.glyphCapLine, true), (KitLayout.glyphXHeightLine, true), (KitLayout.glyphBaseline, false)] {
                let y = rect.minY + rect.height * fraction
                context.setStrokeColor(guide)
                context.setLineWidth(dashed ? 0.6 : 1.1)
                context.setLineDash(phase: 0, lengths: dashed ? [3, 3] : [])
                context.move(to: CGPoint(x: rect.minX + 6, y: y))
                context.addLine(to: CGPoint(x: rect.maxX - 6, y: y))
                context.strokePath()
            }
        }

        context.addPath(path)
        context.setStrokeColor(boxStroke)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [5, 4])
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        let labelSize: CGFloat = slot.kind == .glyph ? 11 : 9.5
        let font = slot.kind == .glyph ? "Georgia" : "AvenirNext-Medium"
        text(slot.label, at: CGPoint(x: rect.minX + 2, y: rect.minY - 6), font: font, size: labelSize, color: muted, in: context)
    }

    // MARK: - Faint standard look

    private static func drawGhost(_ slot: KitSlot, ghosts: KitGhosts, clippedTo path: CGPath, in context: CGContext) {
        let rect = slot.rect
        context.saveGState()
        context.addPath(path)
        context.clip()
        // Draw at full strength inside a transparency layer, then fade the whole layer,
        // so overlapping parts don't get darker.
        context.setAlpha(ghostAlpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        switch slot.kind {
        case .wordmark:
            // The library title: "Parchment" in bold serif.
            let probe = ghosts.serifFont(100, true)
            let size = min(rect.height * 0.5, rect.width * 0.8 / max(lineWidth("Parchment", font: probe) / 100, 0.01))
            centered("Parchment", font: ghosts.serifFont(size, true), in: rect, baseline: rect.midY + size * 0.32, context: context)

        case .logo:
            drawStandardLogo(in: rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12), context: context)

        case .icon:
            if let symbol = KitLayout.allIcons.first(where: { "icon.\($0.id)" == slot.id })?.symbol,
               let image = ghosts.symbol(symbol) {
                draw(image, fittingIn: rect.insetBy(dx: rect.width * 0.25, dy: rect.height * 0.25), context: context)
            }

        case .cover:
            // The standard covers are solid colors with a darker spine.
            let index = Int(slot.id.split(separator: ".").last ?? "0") ?? 0
            context.setFillColor(color(hex: Notebook.coverPalette[index % Notebook.coverPalette.count]))
            context.fill(rect)
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.25))
            context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.065, height: rect.height))

        case .illustration:
            // The standard look: an empty library, or a finished study session.
            let finished = slot.id == "illustration.caughtUp"
            if let image = ghosts.symbol(finished ? "checkmark.seal" : "book.closed") {
                draw(image, fittingIn: CGRect(x: rect.midX - 24, y: rect.minY + 14, width: 48, height: 44), context: context)
            }
            centered(finished ? "All caught up!" : "No notebooks yet", font: ghosts.serifFont(finished ? 20 : 15, true),
                     in: rect, baseline: rect.minY + (finished ? 96 : 76), context: context)

        case .rating:
            // The rating buttons show their number.
            let number = String(slot.id.split(separator: ".").last ?? "")
            let size = rect.height * 0.55
            centered(number, font: ghosts.serifFont(size, true), in: rect, baseline: rect.midY + size * 0.35, context: context)

        case .glyph:
            // Notebook titles fall back to semibold serif; size it so capitals fill the guides.
            let probe = ghosts.serifFont(100, false)
            let capHeight = rect.height * (KitLayout.glyphBaseline - KitLayout.glyphCapLine)
            let size = capHeight / max(CTFontGetCapHeight(probe) / 100, 0.01)
            centered(slot.label, font: ghosts.serifFont(size, false), in: rect,
                     baseline: rect.minY + rect.height * KitLayout.glyphBaseline, context: context)
        }

        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// The default app icon (a tilted page with handwriting), in a top-left-origin context.
    static func drawStandardLogo(in rect: CGRect, context: CGContext) {
        let side = min(rect.width, rect.height)
        let scale = side / 1024
        context.saveGState()
        context.translateBy(x: rect.midX - side / 2, y: rect.midY - side / 2)
        context.scaleBy(x: scale, y: scale)

        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024), cornerWidth: 230, cornerHeight: 230, transform: nil))
        context.setFillColor(CGColor(red: 0.55, green: 0.29, blue: 0.18, alpha: 1))
        context.fillPath()

        context.translateBy(x: 512, y: 530)
        context.rotate(by: -0.10)
        context.addPath(CGPath(roundedRect: CGRect(x: -300, y: -370, width: 600, height: 740), cornerWidth: 36, cornerHeight: 36, transform: nil))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fillPath()

        context.setStrokeColor(CGColor(red: 0.77, green: 0.67, blue: 0.51, alpha: 1))
        context.setLineWidth(6)
        for line in 0..<8 {
            let y = -230 + CGFloat(line) * 78
            context.move(to: CGPoint(x: -240, y: y))
            context.addLine(to: CGPoint(x: 240, y: y))
        }
        context.strokePath()

        context.setStrokeColor(CGColor(red: 0.23, green: 0.13, blue: 0.09, alpha: 1))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(24)
        context.move(to: CGPoint(x: -215, y: -40))
        context.addCurve(to: CGPoint(x: -120, y: -150), control1: CGPoint(x: -230, y: -120), control2: CGPoint(x: -170, y: -170))
        context.addCurve(to: CGPoint(x: -110, y: 10), control1: CGPoint(x: -70, y: -130), control2: CGPoint(x: -60, y: -20))
        context.addCurve(to: CGPoint(x: 10, y: -80), control1: CGPoint(x: -160, y: 40), control2: CGPoint(x: -40, y: -90))
        context.addCurve(to: CGPoint(x: 80, y: 10), control1: CGPoint(x: 60, y: -70), control2: CGPoint(x: 40, y: 10))
        context.addCurve(to: CGPoint(x: 215, y: -70), control1: CGPoint(x: 120, y: 10), control2: CGPoint(x: 170, y: -40))
        context.strokePath()
        context.setLineWidth(16)
        context.move(to: CGPoint(x: -200, y: 160))
        context.addCurve(to: CGPoint(x: 160, y: 150), control1: CGPoint(x: -80, y: 120), control2: CGPoint(x: 40, y: 190))
        context.strokePath()
        context.restoreGState()
    }

    /// Draws an image aspect-fit inside `rect` (the context is flipped, so images are flipped back).
    private static func draw(_ image: CGImage, fittingIn rect: CGRect, context: CGContext) {
        let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
        var size = CGSize(width: rect.width, height: rect.width / aspect)
        if size.height > rect.height { size = CGSize(width: rect.height * aspect, height: rect.height) }
        let target = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        context.saveGState()
        context.translateBy(x: target.minX, y: target.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: target.size))
        context.restoreGState()
    }

    private static func color(hex: String) -> CGColor {
        let value = UInt64(hex, radix: 16) ?? 0x8B4A2E
        return CGColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    // MARK: - Text

    private static func line(_ string: String, font: CTFont, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    private static func lineWidth(_ string: String, font: CTFont) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(string, font: font, color: ink), nil, nil, nil))
    }

    private static func centered(_ string: String, font: CTFont, in rect: CGRect, baseline: CGFloat, context: CGContext) {
        draw(line(string, font: font, color: ink), at: CGPoint(x: rect.midX - lineWidth(string, font: font) / 2, y: baseline), in: context)
    }

    /// Draws a single line of text with its baseline at `point` (top-left coordinates).
    private static func text(_ string: String, at point: CGPoint, font name: String, size: CGFloat,
                             color: CGColor, alignRight: Bool = false, in context: CGContext) {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let width = lineWidth(string, font: font)
        draw(line(string, font: font, color: color), at: CGPoint(x: alignRight ? point.x - width : point.x, y: point.y), in: context)
    }

    private static func draw(_ line: CTLine, at point: CGPoint, in context: CGContext) {
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = point
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
