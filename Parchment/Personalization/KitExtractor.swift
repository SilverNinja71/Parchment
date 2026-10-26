import UIKit
import PencilKit

/// Cuts the user's ink out of each box of a filled-in Personalization Kit.
enum KitExtractor {
    @MainActor
    static func extract(from notebook: Notebook, store: NotebookStore) -> [String: UIImage] {
        var result: [String: UIImage] = [:]
        for page in notebook.pages {
            guard let kitPage = page.pdfPageIndex, kitPage < KitLayout.pages.count,
                  let data = store.loadDrawing(notebook: notebook.id, page: page.id),
                  let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { continue }

            // The kit PDF is scaled up to the page width inside Parchment.
            let scale = page.width / KitLayout.pageSize.width
            for slot in KitLayout.slots where slot.page == kitPage {
                let box = slot.rect.applying(CGAffineTransform(scaleX: scale, y: scale))
                if let image = image(for: slot, box: box, drawing: drawing) {
                    result[slot.id] = image
                }
            }
        }
        return result
    }

    private static func image(for slot: KitSlot, box: CGRect, drawing: PKDrawing) -> UIImage? {
        let strokes = drawing.strokes.filter { box.intersects($0.renderBounds) }
        guard !strokes.isEmpty else { return nil }
        let ink = strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }.intersection(box)
        guard !ink.isNull, ink.width > 1 || ink.height > 1 else { return nil }

        let crop = slot.cropRect(ink: ink, box: box)

        // Rendering a rect clips any part of a stroke that strays outside the box.
        let clipped = crop.intersection(box)
        let rendered = InkRendering.image(of: PKDrawing(strokes: strokes), rect: clipped, scale: 3)
        guard [.icon, .logo, .rating].contains(slot.kind), clipped != crop else { return rendered }

        // Re-center a clipped icon inside its square so it isn't stretched later.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: crop.size, format: format).image { _ in
            rendered.draw(in: clipped.offsetBy(dx: -crop.minX, dy: -crop.minY))
        }
    }

    /// Writes the blank kit to a temporary file so it can be shared or opened.
    static func blankKitFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Parchment Personalization Kit.\(KitLayout.fileExtension)")
        try KitPDFRenderer.makePDF(ghosts: .standard).write(to: url, options: .atomic)
        return url
    }
}

extension KitGhosts {
    /// Parchment's standard look on iPad: SF Symbols and the system serif (New York).
    static var standard: KitGhosts {
        KitGhosts(
            symbol: { name in
                let configuration = UIImage.SymbolConfiguration(pointSize: 96, weight: .regular)
                guard let symbol = UIImage(systemName: name, withConfiguration: configuration)?
                    .withTintColor(.black, renderingMode: .alwaysOriginal) else { return nil }
                let format = UIGraphicsImageRendererFormat()
                format.scale = 2
                format.opaque = false
                return UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in
                    symbol.draw(at: .zero)
                }.cgImage
            },
            serifFont: { size, bold in
                let system = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .semibold)
                let descriptor = system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor
                return UIFont(descriptor: descriptor, size: size) as CTFont
            })
    }
}
