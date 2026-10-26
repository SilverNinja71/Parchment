import UIKit
import PencilKit

/// Renders a notebook page (paper, PDF, typed text and ink) to an image.
/// Used by page thumbnails and by Study, which shows pages to memorize and compare.
@MainActor
enum PageRenderer {
    /// The part of a page worth showing: a whole PDF page, or the written area of other pages.
    static func contentRect(for page: Page, drawing: PKDrawing?) -> CGRect {
        let ink = drawing.map(\.bounds) ?? .null
        let text = page.textBlocks.reduce(CGRect.null) { $0.union($1.frame) }
        let used = ink.union(text)
        switch page.kind {
        case .pdf:
            return CGRect(origin: .zero, size: page.size)
        case .document:
            let bottom = used.isNull ? 0 : used.maxY + 60
            return CGRect(x: 0, y: 0, width: page.width, height: max(page.width * 0.6, bottom))
        case .freeform:
            return used.isNull ? CGRect(x: 0, y: 0, width: Page.documentWidth, height: Page.documentWidth * 0.6)
                               : used.insetBy(dx: -40, dy: -40)
        }
    }

    static func image(of page: Page, in notebookID: UUID, store: NotebookStore, pdf: CGPDFDocument?,
                      region: CGRect? = nil, width: CGFloat, showPaper: Bool = true) -> UIImage {
        let drawing = store.loadDrawing(notebook: notebookID, page: page.id).flatMap { try? PKDrawing(data: $0) }
        let region = region ?? contentRect(for: page, drawing: drawing)
        let scale = width / max(region.width, 1)
        let size = CGSize(width: region.width * scale, height: region.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            (page.kind == .pdf ? UIColor.white : UIColor.paper).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            cg.scaleBy(x: scale, y: scale)
            cg.translateBy(x: -region.minX, y: -region.minY)

            if page.kind == .pdf, let index = page.pdfPageIndex, let pdfPage = pdf?.page(at: index + 1) {
                PDFDrawing.draw(pdfPage, in: cg, targetSize: page.size)
            } else if showPaper {
                drawPaper(page.paper, in: region, context: cg)
            }
            for block in page.textBlocks where block.frame.intersects(region) {
                (block.text as NSString).draw(in: block.frame, withAttributes: [
                    .font: UIFont.systemFont(ofSize: block.fontSize), .foregroundColor: UIColor.black,
                ])
            }
            if let drawing, !drawing.strokes.isEmpty {
                InkRendering.image(of: drawing, rect: region, scale: max(scale, 1) * 2).draw(in: region)
            }
        }
    }

    /// Same paper patterns as the editor, drawn in page coordinates.
    static func drawPaper(_ style: PaperStyle, in region: CGRect, context: CGContext) {
        let spacing = PaperBackgroundView.lineSpacing
        context.saveGState()
        context.setStrokeColor(UIColor.paperLine.cgColor)
        context.setFillColor(UIColor.paperLine.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1)
        switch style {
        case .ruled, .dottedLined:
            var y = PaperBackgroundView.topMargin + spacing
            while y < region.maxY {
                if y > region.minY {
                    context.move(to: CGPoint(x: region.minX, y: y))
                    context.addLine(to: CGPoint(x: region.maxX, y: y))
                }
                y += spacing
            }
            context.strokePath()
            if style == .dottedLined {
                // Dashed midlines halfway between the baselines.
                context.setStrokeColor(UIColor.paperLine.withAlphaComponent(0.2).cgColor)
                context.setLineDash(phase: 0, lengths: [3, 5])
                var mid = PaperBackgroundView.topMargin + spacing / 2
                while mid < region.maxY {
                    if mid > region.minY {
                        context.move(to: CGPoint(x: region.minX, y: mid))
                        context.addLine(to: CGPoint(x: region.maxX, y: mid))
                    }
                    mid += spacing
                }
                context.strokePath()
                context.setLineDash(phase: 0, lengths: [])
            }
        case .grid:
            var y = (region.minY / spacing).rounded(.down) * spacing
            while y < region.maxY {
                context.move(to: CGPoint(x: region.minX, y: y)); context.addLine(to: CGPoint(x: region.maxX, y: y)); y += spacing
            }
            var x = (region.minX / spacing).rounded(.down) * spacing
            while x < region.maxX {
                context.move(to: CGPoint(x: x, y: region.minY)); context.addLine(to: CGPoint(x: x, y: region.maxY)); x += spacing
            }
            context.strokePath()
        case .dotted:
            var y = (region.minY / spacing).rounded(.down) * spacing + spacing / 2
            while y < region.maxY {
                var x = (region.minX / spacing).rounded(.down) * spacing + spacing / 2
                while x < region.maxX {
                    context.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    x += spacing
                }
                y += spacing
            }
        case .blank:
            break
        }
        context.restoreGState()
    }
}
