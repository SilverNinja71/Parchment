import UIKit
import PencilKit

/// Low-level helpers for drawing PDF pages into UIKit contexts.
enum PDFDrawing {
    /// Page size as a viewer shows it (crop box, with the page's rotation applied).
    static func displaySize(of page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox)
        let rotated = abs(page.rotationAngle) % 180 == 90
        return rotated ? CGSize(width: box.height, height: box.width) : box.size
    }

    /// Draws `page` filling `targetSize` in a top-left-origin (UIKit) context.
    static func draw(_ page: CGPDFPage, in context: CGContext, targetSize: CGSize) {
        let native = displaySize(of: page)
        guard native.width > 0, native.height > 0 else { return }
        context.saveGState()
        context.translateBy(x: 0, y: targetSize.height)
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: targetSize.width / native.width, y: targetSize.height / native.height)
        // getDrawingTransform never scales up, so ask for the native size and scale ourselves.
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: native),
                                                     rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        context.restoreGState()
    }

    static func image(of page: CGPDFPage, size: CGSize, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            draw(page, in: renderer.cgContext, targetSize: size)
        }
    }
}

extension NotebookStore {
    /// Creates a notebook with one annotatable page per PDF page.
    @discardableResult
    func importPDF(from url: URL) throws -> Notebook {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try importPDF(data: data, title: url.deletingPathExtension().lastPathComponent)
    }

    @discardableResult
    func importPDF(data: Data, title: String, isPersonalizationKit: Bool = false) throws -> Notebook {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider), document.numberOfPages > 0 else {
            throw ParchmentError.invalidFile("Parchment couldn't read this PDF.")
        }
        if document.isEncrypted && !document.isUnlocked && !document.unlockWithPassword("") {
            throw ParchmentError.invalidFile("This PDF is password protected. Remove the password and try again.")
        }

        var pages: [Page] = []
        for number in 1...document.numberOfPages {
            guard let pdfPage = document.page(at: number) else { continue }
            pages.append(.newPDF(index: number - 1, pdfPageSize: PDFDrawing.displaySize(of: pdfPage)))
        }

        var notebook = Notebook(title: title, pages: pages)
        notebook.hasPDF = true
        notebook.isPersonalizationKit = isPersonalizationKit
        notebook.coverColor = isPersonalizationKit ? "B8862B" : Notebook.coverPalette[1]
        try attachPDF(data, to: notebook.id)
        save(notebook)
        return notebook
    }

    /// Opens the notebook's source PDF (cached by the caller).
    func pdfDocument(for id: UUID) -> CGPDFDocument? {
        guard let provider = CGDataProvider(url: pdfURL(for: id) as CFURL) else { return nil }
        return CGPDFDocument(provider)
    }

    /// Flattens a notebook into a regular PDF: original PDF pages stay vector, ink is drawn on top.
    func exportPDF(_ id: UUID) throws -> URL {
        guard let notebook = notebook(id) else { throw ParchmentError.notFound("Notebook not found.") }
        let source = notebook.hasPDF ? pdfDocument(for: id) : nil
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.safeFileName(notebook.title)).pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: url) { context in
            for page in notebook.pages {
                let drawing = loadDrawing(notebook: id, page: page.id).flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
                // Document pages export at their written height; freeform pages are cropped to the ink.
                var bounds = CGRect(origin: .zero, size: page.size)
                if page.kind == .freeform {
                    let ink = drawing.bounds.union(page.textBlocks.reduce(CGRect.null) { $0.union($1.frame) })
                    bounds = ink.isNull ? CGRect(x: 0, y: 0, width: 820, height: 1100) : ink.insetBy(dx: -40, dy: -40)
                } else if page.kind == .document {
                    bounds.size.height = max(Page.documentMinHeight, drawing.bounds.maxY + 60)
                }
                context.beginPage(withBounds: CGRect(origin: .zero, size: bounds.size), pageInfo: [:])
                let cg = context.cgContext
                cg.translateBy(x: -bounds.minX, y: -bounds.minY)

                if page.kind == .pdf, let index = page.pdfPageIndex, let pdfPage = source?.page(at: index + 1) {
                    PDFDrawing.draw(pdfPage, in: cg, targetSize: page.size)
                } else {
                    // Keep the notebook's paper (lined, grid, dotted…) in the exported PDF.
                    UIColor.paper.setFill()
                    cg.fill(bounds)
                    PageRenderer.drawPaper(page.paper, in: bounds, context: cg)
                }
                for block in page.textBlocks {
                    let style = NSMutableParagraphStyle()
                    style.lineBreakMode = .byWordWrapping
                    (block.text as NSString).draw(in: block.frame, withAttributes: [
                        .font: UIFont.systemFont(ofSize: block.fontSize),
                        .foregroundColor: UIColor.black,
                        .paragraphStyle: style,
                    ])
                }
                if !drawing.strokes.isEmpty {
                    let ink = InkRendering.image(of: drawing, rect: bounds, scale: 3)
                    ink.draw(in: bounds)
                }
            }
        }
        return url
    }
}

enum InkRendering {
    /// Renders ink as it looks in light mode (PencilKit adapts colors to dark mode otherwise).
    static func image(of drawing: PKDrawing, rect: CGRect, scale: CGFloat) -> UIImage {
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: rect, scale: scale)
        }
        return image
    }
}
