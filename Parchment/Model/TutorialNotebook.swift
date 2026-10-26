import UIKit
import PencilKit
import CoreText

extension NotebookStore {
    /// Builds the hands-on "Welcome to Parchment" notebook shown on first launch.
    @discardableResult
    func createTutorialNotebook() -> Notebook {
        func page(_ paper: PaperStyle, title: String, body: String) -> Page {
            var page = Page.newDocument(paper: paper)
            page.textBlocks = [
                TextBlock(text: title, x: 60, y: 104, width: 700, height: 44, fontSize: 30),
                TextBlock(text: body, x: 60, y: 160, width: 700, height: 120, fontSize: 19),
            ]
            return page
        }

        let pages = [
            page(.ruled, title: "1 · Gestures & Scratch-Out",
                 body: "Scribble back and forth over the handwriting below to scratch-out erase it! "
                     + "Tip: double-tap your Apple Pencil to switch to the eraser."),
            page(.ruled, title: "2 · Convert Handwriting to Text",
                 body: "Select the Convert tool, circle the sentence below with your Pencil, "
                     + "and tap Convert to see it turn into typeset text. Undo brings your ink back."),
            page(.dottedLined, title: "3 · Paper Styles",
                 body: "Parchment has five papers: Lined, Grid, Dotted, Blank and Dotted-Lined (this page). "
                     + "Dotted-Lined adds a dashed midline for neat handwriting. Open ••• › Paper Style… to try them all."),
            page(.ruled, title: "4 · Make It Yours",
                 body: "Tap the palette button at the top to customize this cover: colors, finishes, "
                     + "the Cover Library or your own photo. Long-press any notebook in the library to change its cover whenever you like."),
        ]

        var notebook = Notebook(title: "Welcome to Parchment", pages: pages)
        notebook.coverDesign = "sunset-gradient"
        notebook.isTutorial = true
        save(notebook)

        let samples: [(text: String, origin: CGPoint, size: CGFloat)?] = [
            ("Erase me!", CGPoint(x: 80, y: 330), 64),
            ("Meeting at 3 PM", CGPoint(x: 80, y: 330), 56),
            ("Neat handwriting", CGPoint(x: 80, y: 384), 40),
            nil,
        ]
        for (page, sample) in zip(pages, samples) {
            guard let sample else { continue }
            let drawing = PKDrawing(strokes: SampleInk.strokes(for: sample.text, at: sample.origin, size: sample.size))
            saveDrawing(drawing.dataRepresentation(), notebook: notebook.id, page: page.id)
        }
        return self.notebook(notebook.id) ?? notebook
    }
}

/// Turns text into real PencilKit strokes (outlines of a handwriting-style font), so the
/// tutorial has ink you can scratch out and convert, just like your own.
enum SampleInk {
    static func strokes(for text: String, at origin: CGPoint, size: CGFloat) -> [PKStroke] {
        let font = CTFontCreateWithName("Noteworthy-Bold" as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        let ink = PKInk(.pen, color: .black)
        var strokes: [PKStroke] = []
        // Real strokes are written one after another; give each its own timestamp.
        let start = Date()

        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)

            for (glyph, position) in zip(glyphs, positions) {
                // Glyph outlines point up; flip them onto the page.
                var transform = CGAffineTransform(translationX: origin.x + position.x, y: origin.y).scaledBy(x: 1, y: -1)
                guard let path = CTFontCreatePathForGlyph(font, glyph, &transform) else { continue }
                for outline in subpaths(of: path) {
                    // Drop repeated points: PencilKit doesn't like zero-length segments.
                    var points: [CGPoint] = []
                    for point in outline where points.last.map({ hypot($0.x - point.x, $0.y - point.y) > 0.5 }) ?? true {
                        points.append(point)
                    }
                    guard points.count > 1 else { continue }
                    let strokePoints = points.enumerated().map { index, point in
                        PKStrokePoint(location: point, timeOffset: Double(index) * 0.01, size: CGSize(width: 2, height: 2),
                                      opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                    }
                    let created = start.addingTimeInterval(Double(strokes.count) * 0.4)
                    strokes.append(PKStroke(ink: ink, path: PKStrokePath(controlPoints: strokePoints, creationDate: created)))
                }
            }
        }
        return strokes
    }

    private static func quadratic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u, b = 2 * u * t, c = t * t
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x, y: a * p0.y + b * p1.y + c * p2.y)
    }

    private static func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        let x: CGFloat = a * p0.x + b * p1.x + c * p2.x + d * p3.x
        let y: CGFloat = a * p0.y + b * p1.y + c * p2.y + d * p3.y
        return CGPoint(x: x, y: y)
    }

    /// Flattens a path's curves into point lists, one per closed shape.
    private static func subpaths(of path: CGPath) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                if !current.isEmpty { result.append(current) }
                current = [points[0]]
            case .addLineToPoint:
                current.append(points[0])
            case .addQuadCurveToPoint:
                let start = current.last ?? points[0]
                for step in 1...6 {
                    current.append(quadratic(start, points[0], points[1], t: CGFloat(step) / 6))
                }
            case .addCurveToPoint:
                let start = current.last ?? points[0]
                for step in 1...8 {
                    current.append(cubic(start, points[0], points[1], points[2], t: CGFloat(step) / 8))
                }
            case .closeSubpath:
                if let first = current.first { current.append(first) }
            @unknown default:
                break
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
