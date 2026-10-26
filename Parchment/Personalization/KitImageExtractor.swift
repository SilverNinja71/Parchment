import Foundation
import CoreGraphics

// Shared with the Mac tool: Foundation and CoreGraphics only.

/// Reads kit pages that were drawn in another app (Procreate, a photo editor…) and
/// exported as pictures. Each picture is compared with the blank kit, so the box
/// background, dashed lines, writing guides and faint drawings drop away and only
/// your ink is left.
enum KitImageExtractor {
    struct PageResult {
        let page: Int
        let images: [String: CGImage]
    }

    /// Finds which kit page a picture is, then cuts out the ink in each of its boxes.
    static func extract(from image: CGImage, ghosts: KitGhosts?) -> PageResult? {
        blankKit(ghosts: ghosts).flatMap { extract(from: image, kit: $0) }
    }

    /// Same, against an already-rendered blank kit (render it once for many pictures).
    static func extract(from image: CGImage, kit document: CGPDFDocument) -> PageResult? {
        let picture = Bitmap(image, maxWidth: 1600)
        guard let page = matchPage(picture, in: document) else { return nil }
        guard let template = document.page(at: page + 1).map({ Bitmap(pdfPage: $0, width: picture.width, height: picture.height) }) else {
            return nil
        }
        return PageResult(page: page, images: cutOut(picture, template: template, page: page))
    }

    static func blankKit(ghosts: KitGhosts?) -> CGPDFDocument? {
        let data = KitPDFRenderer.makePDF(ghosts: ghosts)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGPDFDocument(provider)
    }

    // MARK: - Which page is it?

    private static func matchPage(_ picture: Bitmap, in document: CGPDFDocument) -> Int? {
        // Kit pages are US Letter shaped; anything else isn't a kit page.
        let aspect = Double(picture.width) / Double(picture.height)
        let kitAspect = Double(KitLayout.pageSize.width / KitLayout.pageSize.height)
        guard abs(aspect - kitAspect) < 0.03 else { return nil }

        // Compare small grayscale versions; the box layout differs on every page.
        let small = picture.resized(width: 61, height: 79)
        var best: (page: Int, score: Double)?
        for number in 1...document.numberOfPages {
            guard let page = document.page(at: number) else { continue }
            let template = Bitmap(pdfPage: page, width: 61, height: 79)
            let score = small.meanDifference(from: template)
            if best == nil || score < best!.score { best = (number - 1, score) }
        }
        guard let best, best.score < 40 else { return nil }
        return best.page
    }

    // MARK: - Cutting out the ink

    private static func cutOut(_ picture: Bitmap, template: Bitmap, page: Int) -> [String: CGImage] {
        let scale = CGFloat(picture.width) / KitLayout.pageSize.width
        var result: [String: CGImage] = [:]

        for slot in KitLayout.slots where slot.page == page {
            // Stay a few points inside the dashed border so it never counts as ink.
            let box = slot.rect.applying(CGAffineTransform(scaleX: scale, y: scale))
                .insetBy(dx: 4 * scale, dy: 4 * scale).integral
            let x0 = max(0, Int(box.minX)), y0 = max(0, Int(box.minY))
            let x1 = min(picture.width, Int(box.maxX)), y1 = min(picture.height, Int(box.maxY))
            guard x1 > x0, y1 > y0 else { continue }
            let width = x1 - x0, height = y1 - y0

            var ink = [UInt8](repeating: 0, count: width * height * 4)
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1, count = 0
            for y in y0..<y1 {
                for x in x0..<x1 {
                    // Distance from the blank kit, forgiving a pixel of misalignment.
                    var distance = Double.greatestFiniteMagnitude
                    for dy in -1...1 {
                        for dx in -1...1 {
                            distance = min(distance, picture.distance(x, y, to: template, x + dx, y + dy))
                        }
                    }
                    let alpha = min(1, max(0, (distance - 70) / 90))
                    guard alpha > 0 else { continue }
                    let source = picture.offset(x, y), target = ((y - y0) * width + (x - x0)) * 4
                    for channel in 0..<3 {
                        ink[target + channel] = UInt8(Double(picture.pixels[source + channel]) * alpha)
                    }
                    ink[target + 3] = UInt8(alpha * 255)
                    if alpha > 0.5 {
                        count += 1
                        minX = min(minX, x - x0); maxX = max(maxX, x - x0)
                        minY = min(minY, y - y0); maxY = max(maxY, y - y0)
                    }
                }
            }
            // Ignore boxes with nothing (or only a speck of JPEG noise) in them.
            guard count >= max(12, width * height / 2000) else { continue }

            let local = CGRect(x: 0, y: 0, width: width, height: height)
            let inkRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            let crop = slot.cropRect(ink: inkRect, box: local, unit: scale).integral
            if let image = makeImage(ink, width: width, height: height, crop: crop) {
                result[slot.id] = image
            }
        }
        return result
    }

    /// Copies `crop` out of a premultiplied RGBA buffer (areas outside it stay transparent).
    private static func makeImage(_ pixels: [UInt8], width: Int, height: Int, crop: CGRect) -> CGImage? {
        let outWidth = max(1, Int(crop.width)), outHeight = max(1, Int(crop.height))
        var out = [UInt8](repeating: 0, count: outWidth * outHeight * 4)
        let originX = Int(crop.minX), originY = Int(crop.minY)
        for y in 0..<outHeight {
            let sourceY = y + originY
            guard sourceY >= 0, sourceY < height else { continue }
            for x in 0..<outWidth {
                let sourceX = x + originX
                guard sourceX >= 0, sourceX < width else { continue }
                let source = (sourceY * width + sourceX) * 4, target = (y * outWidth + x) * 4
                out[target] = pixels[source]
                out[target + 1] = pixels[source + 1]
                out[target + 2] = pixels[source + 2]
                out[target + 3] = pixels[source + 3]
            }
        }
        return out.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: outWidth, height: outHeight, bitsPerComponent: 8,
                      bytesPerRow: outWidth * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }
}

/// An RGBA pixel buffer with a top-left origin.
struct Bitmap {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    /// Draws `image` on white (so transparent exports from Procreate behave like paper).
    init(_ image: CGImage, maxWidth: Int) {
        let width = min(image.width, maxWidth)
        let height = Int((Double(image.height) * Double(width) / Double(image.width)).rounded())
        self.init(width: width, height: height) { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    init(pdfPage page: CGPDFPage, width: Int, height: Int) {
        self.init(width: width, height: height) { context in
            let box = page.getBoxRect(.mediaBox)
            context.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
        }
    }

    private init(width: Int, height: Int, draw: (CGContext) -> Void) {
        self.width = width
        self.height = height
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.interpolationQuality = .high
            draw(context)
        }
        self.pixels = pixels
    }

    func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

    /// Color distance (0…441) between a pixel here and one in `other` (off-edge counts as far).
    func distance(_ x: Int, _ y: Int, to other: Bitmap, _ ox: Int, _ oy: Int) -> Double {
        guard ox >= 0, oy >= 0, ox < other.width, oy < other.height else { return .greatestFiniteMagnitude }
        let a = offset(x, y), b = other.offset(ox, oy)
        let dr = Double(pixels[a]) - Double(other.pixels[b])
        let dg = Double(pixels[a + 1]) - Double(other.pixels[b + 1])
        let db = Double(pixels[a + 2]) - Double(other.pixels[b + 2])
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    func resized(width: Int, height: Int) -> Bitmap {
        let copy = pixels
        let sourceWidth = self.width, sourceHeight = self.height
        return copy.withUnsafeBytes { buffer -> Bitmap in
            let provider = CGDataProvider(data: Data(buffer) as CFData)!
            let image = CGImage(width: sourceWidth, height: sourceHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: sourceWidth * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
            return Bitmap(image, maxWidth: width)
        }
    }

    func meanDifference(from other: Bitmap) -> Double {
        var total = 0.0
        for y in 0..<min(height, other.height) {
            for x in 0..<min(width, other.width) {
                let a = offset(x, y), b = other.offset(x, y)
                let gray = (Int(pixels[a]) + Int(pixels[a + 1]) + Int(pixels[a + 2])) / 3
                let otherGray = (Int(other.pixels[b]) + Int(other.pixels[b + 1]) + Int(other.pixels[b + 2])) / 3
                total += Double(abs(gray - otherGray))
            }
        }
        return total / Double(max(1, width * height))
    }
}
