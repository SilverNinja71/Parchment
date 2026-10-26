import Foundation
import CoreGraphics

/// The three page types Parchment supports, mirroring MyScript:
/// - `document`: fixed width, grows downward as you write (ruled paper by default)
/// - `freeform`: an infinite canvas that grows in every direction you write
/// - `pdf`: a page of an imported PDF that you annotate on top of
enum PageKind: String, Codable, CaseIterable, Identifiable {
    case document, freeform, pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .document: return "Document"
        case .freeform: return "Freeform"
        case .pdf: return "PDF"
        }
    }

    var systemImage: String {
        switch self {
        case .document: return "doc.text"
        case .freeform: return "scribble.variable"
        case .pdf: return "doc.richtext"
        }
    }
}

enum PaperStyle: String, Codable, CaseIterable, Identifiable {
    case ruled, grid, dotted, dottedLined, blank

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ruled: return "Lined"
        case .grid: return "Grid"
        case .dotted: return "Dotted"
        case .dottedLined: return "Dotted-Lined"
        case .blank: return "Blank"
        }
    }

    /// Lined styles leave a roomy top margin, like a real notebook page.
    var hasTopMargin: Bool { self == .ruled || self == .dottedLined }
}

/// The surface finish of a notebook cover.
enum CoverMaterial: String, Codable, CaseIterable, Identifiable {
    case smooth, leather, linen, gridEmboss, geometric, kitDoodle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smooth: return "Smooth"
        case .leather: return "Leather"
        case .linen: return "Linen"
        case .gridEmboss: return "Grid Emboss"
        case .geometric: return "Geometric"
        case .kitDoodle: return "My Doodle"
        }
    }
}

/// Typeset text produced by converting handwriting (or typed by the user).
struct TextBlock: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var fontSize: Double = 22
    /// A paragraph that spans the page and wraps (reflows) as it grows.
    var flows: Bool?

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set { x = newValue.minX; y = newValue.minY; width = newValue.width; height = newValue.height }
    }
}

struct Page: Codable, Identifiable, Equatable {
    static let documentWidth: Double = 820
    static let documentMinHeight: Double = 1100
    static let freeformMinSize: Double = 2400

    var id = UUID()
    var kind: PageKind
    var paper: PaperStyle
    var width: Double
    var height: Double
    /// Index into the notebook's source PDF (pdf pages only).
    var pdfPageIndex: Int?
    var textBlocks: [TextBlock] = []

    var size: CGSize {
        get { CGSize(width: width, height: height) }
        set { width = newValue.width; height = newValue.height }
    }

    static func newDocument(paper: PaperStyle = .ruled) -> Page {
        Page(kind: .document, paper: paper, width: documentWidth, height: documentMinHeight)
    }

    static func newFreeform(paper: PaperStyle = .dotted) -> Page {
        Page(kind: .freeform, paper: paper, width: freeformMinSize, height: freeformMinSize)
    }

    static func newPDF(index: Int, pdfPageSize: CGSize) -> Page {
        // PDF pages are scaled so they are as wide as a document page.
        let scale = documentWidth / max(pdfPageSize.width, 1)
        return Page(kind: .pdf, paper: .blank, width: documentWidth,
                    height: (pdfPageSize.height * scale).rounded(), pdfPageIndex: index)
    }
}

struct Notebook: Codable, Identifiable, Equatable {
    /// The curated cover colors, by name.
    static let namedPalette: [(name: String, hex: String)] = [
        ("Classic Parchment", "B08A57"), ("Obsidian Dark", "2B2D33"), ("Sage Green", "7C9A7E"),
        ("Royal Cobalt", "2F4FA8"), ("Terracotta", "C0643F"), ("Dusty Rose", "C4878F"),
        ("Mustard", "D1A33A"), ("Plum", "6E3F6B"),
    ]
    static let coverPalette = namedPalette.map(\.hex)

    var formatVersion = 1
    var id = UUID()
    var title: String
    var created = Date()
    var modified = Date()
    var coverColor: String = Notebook.coverPalette[0]
    /// Index of a hand-drawn cover from the personalization kit, if chosen.
    var customCover: Int?
    var pages: [Page]
    var hasPDF = false
    /// True for the special notebook made from a Parchment Personalization Kit.
    var isPersonalizationKit = false
    /// The subject (Notability-style divider) this notebook is filed under.
    var subject: String?
    /// Cover finish; nil means smooth (notebooks from before covers could be styled).
    var coverMaterial: CoverMaterial?
    /// A design from the Cover Library, which overrides color and material.
    var coverDesign: String?
    /// True when the cover is a photo/image the user imported (stored as cover.jpg).
    var hasCoverImage: Bool?
    /// The built-in "Welcome to Parchment" tutorial notebook.
    var isTutorial: Bool?
}

/// A subject groups notebooks (e.g. "Biology") and is what you pick to study.
struct Subject: Codable, Hashable, Identifiable {
    var name: String
    var colorHex: String
    var id: String { name }
}
