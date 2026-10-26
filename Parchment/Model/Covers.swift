import SwiftUI
import UIKit

enum CoverCategory: String, CaseIterable, Identifiable {
    case minimalist, academic, artistic, technical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimalist: return "Minimalist"
        case .academic: return "Academic & Classic"
        case .artistic: return "Abstract & Artistic"
        case .technical: return "Dark & Technical"
        }
    }
}

/// Procedural artwork drawn on top of a design's background.
enum CoverArt: String {
    case none, watercolor, blueprint, marble, carbon, triangles, circles
}

/// How the title sits on a cover.
enum CoverTitleStyle {
    /// Stamped in metallic foil.
    case foil
    /// On a printed spine-label, like a collegiate notebook.
    case label
    /// Small and quiet, bottom-left.
    case minimal
}

/// One cover in the built-in Cover Library. Everything is drawn in code, so covers stay
/// sharp at any size and cost nothing to download.
struct CoverDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let category: CoverCategory
    /// Gradient stops from top-left to bottom-right.
    let colors: [String]
    let spine: String
    let material: CoverMaterial
    let art: CoverArt
    /// SF Symbol stamped on the cover, if any.
    let foil: String?
    /// Foil and title color.
    let accent: String
    let titleStyle: CoverTitleStyle
}

enum CoverCatalog {
    static let all: [CoverDefinition] = [
        // Minimalist
        CoverDefinition(id: "cloud", name: "Cloud", category: .minimalist, colors: ["F1EFEA", "DDD8CF"], spine: "C9C2B6",
                        material: .smooth, art: .none, foil: nil, accent: "6B6459", titleStyle: .minimal),
        CoverDefinition(id: "mint-haze", name: "Mint Haze", category: .minimalist, colors: ["DCEFE6", "B7D9C8"], spine: "9CC4B0",
                        material: .smooth, art: .none, foil: nil, accent: "3E6B57", titleStyle: .minimal),
        CoverDefinition(id: "blush", name: "Blush", category: .minimalist, colors: ["F6DEDA", "E5BDB6"], spine: "D6A69E",
                        material: .smooth, art: .none, foil: "leaf", accent: "A8675E", titleStyle: .foil),
        CoverDefinition(id: "lavender-foil", name: "Lavender Foil", category: .minimalist, colors: ["E2DAF1", "C3B6E3"], spine: "A897D3",
                        material: .linen, art: .none, foil: "sparkle", accent: "B08A57", titleStyle: .foil),
        // Academic & Classic
        CoverDefinition(id: "oxford-leather", name: "Oxford Leather", category: .academic, colors: ["74402A", "4A2615"], spine: "331A0E",
                        material: .leather, art: .none, foil: "book.closed", accent: "D4AF37", titleStyle: .foil),
        CoverDefinition(id: "ledger-green", name: "Ledger Green", category: .academic, colors: ["35594A", "1F3429"], spine: "16261E",
                        material: .leather, art: .none, foil: nil, accent: "E9DFC4", titleStyle: .label),
        CoverDefinition(id: "collegiate-navy", name: "Collegiate Navy", category: .academic, colors: ["2A3C6B", "17223F"], spine: "101830",
                        material: .linen, art: .none, foil: "graduationcap", accent: "E8D9A8", titleStyle: .label),
        CoverDefinition(id: "marbled-ledger", name: "Marbled Ledger", category: .academic, colors: ["E7DFD3", "C9BBA8"], spine: "5B3A28",
                        material: .smooth, art: .marble, foil: nil, accent: "5B3A28", titleStyle: .label),
        // Abstract & Artistic
        CoverDefinition(id: "sunset-gradient", name: "Sunset Gradient", category: .artistic, colors: ["FFA36C", "E0527A", "6B3FA0"], spine: "4E2B78",
                        material: .smooth, art: .none, foil: "sun.max", accent: "FFFFFF", titleStyle: .foil),
        CoverDefinition(id: "watercolor", name: "Watercolor", category: .artistic, colors: ["FBF7EE", "F3EDE0"], spine: "8FB8D6",
                        material: .smooth, art: .watercolor, foil: nil, accent: "3B5B78", titleStyle: .minimal),
        CoverDefinition(id: "blueprint", name: "Blueprint", category: .artistic, colors: ["2463A8", "174177"], spine: "0F2E55",
                        material: .smooth, art: .blueprint, foil: "compass.drawing", accent: "FFFFFF", titleStyle: .minimal),
        CoverDefinition(id: "prism", name: "Prism", category: .artistic, colors: ["7FD3C9", "5B8DEF", "A86BE0"], spine: "4B4C9E",
                        material: .smooth, art: .triangles, foil: nil, accent: "FFFFFF", titleStyle: .minimal),
        // Dark & Technical
        CoverDefinition(id: "carbon-fiber", name: "Carbon Fiber", category: .technical, colors: ["2E2E31", "19191B"], spine: "0E0E0F",
                        material: .smooth, art: .carbon, foil: nil, accent: "0A60FF", titleStyle: .minimal),
        CoverDefinition(id: "dark-grid", name: "Dark Grid", category: .technical, colors: ["232838", "151824"], spine: "0C0E16",
                        material: .gridEmboss, art: .none, foil: "square.grid.3x3", accent: "6FA0FF", titleStyle: .minimal),
        CoverDefinition(id: "obsidian-slate", name: "Obsidian Slate", category: .technical, colors: ["35383F", "1E2025"], spine: "121316",
                        material: .leather, art: .none, foil: "circle.hexagongrid", accent: "C9CCD4", titleStyle: .foil),
        CoverDefinition(id: "orbit", name: "Orbit", category: .technical, colors: ["1B2233", "0D1220"], spine: "080B14",
                        material: .smooth, art: .circles, foil: nil, accent: "8FB4FF", titleStyle: .minimal),
    ]

    static func design(_ id: String) -> CoverDefinition? { all.first { $0.id == id } }
}

/// Everything that decides how a cover looks, edited by the cover customizer.
struct CoverAppearance: Equatable {
    var colorHex: String
    var material: CoverMaterial = .smooth
    /// A Cover Library design (wins over color and material).
    var designID: String?
    /// Which hand-drawn kit cover to use when the material is "My Doodle".
    var customCover: Int?
    /// An imported photo (wins over everything).
    var image: UIImage?

    var design: CoverDefinition? { designID.flatMap(CoverCatalog.design) }

    /// The look of a Cover Library design on its own.
    static func design(_ id: String) -> CoverAppearance {
        var appearance = CoverAppearance()
        appearance.designID = id
        return appearance
    }

    init(colorHex: String = Notebook.coverPalette[0], material: CoverMaterial = .smooth) {
        self.colorHex = colorHex
        self.material = material
    }

    @MainActor
    init(notebook: Notebook, store: NotebookStore) {
        colorHex = notebook.coverColor
        // Notebooks from before cover styles used `customCover` alone for kit doodles.
        material = notebook.coverMaterial ?? (notebook.customCover != nil ? .kitDoodle : .smooth)
        designID = notebook.coverDesign
        customCover = notebook.customCover
        image = notebook.hasCoverImage == true ? CoverImageCache.image(for: notebook, store: store) : nil
    }

    func apply(to notebook: inout Notebook) {
        notebook.coverColor = colorHex
        notebook.coverMaterial = material
        notebook.coverDesign = designID
        notebook.customCover = material == .kitDoodle ? customCover : nil
        notebook.hasCoverImage = image != nil
    }

    static func == (lhs: CoverAppearance, rhs: CoverAppearance) -> Bool {
        lhs.colorHex == rhs.colorHex && lhs.material == rhs.material && lhs.designID == rhs.designID
            && lhs.customCover == rhs.customCover && lhs.image === rhs.image
    }
}

/// Keeps decoded cover photos in memory so the library grid stays smooth.
@MainActor
enum CoverImageCache {
    private static var cache: [String: UIImage] = [:]

    static func image(for notebook: Notebook, store: NotebookStore) -> UIImage? {
        let key = "\(notebook.id.uuidString)-\(store.revisions[notebook.id, default: 0])"
        if let image = cache[key] { return image }
        guard let data = store.coverImageData(for: notebook.id), let image = UIImage(data: data) else { return nil }
        cache = cache.filter { !$0.key.hasPrefix(notebook.id.uuidString) }
        cache[key] = image
        return image
    }
}
