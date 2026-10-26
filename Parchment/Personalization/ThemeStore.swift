import SwiftUI
import UIKit

/// Holds everything the user drew in their Personalization Kit and hands it to the UI.
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published private(set) var images: [String: UIImage] = [:]

    @Published var useCustomIcons = UserDefaults.standard.object(forKey: "theme.useCustomIcons") as? Bool ?? true {
        didSet { UserDefaults.standard.set(useCustomIcons, forKey: "theme.useCustomIcons") }
    }
    @Published var useHandwrittenTitles = UserDefaults.standard.object(forKey: "theme.useHandwrittenTitles") as? Bool ?? true {
        didSet { UserDefaults.standard.set(useHandwrittenTitles, forKey: "theme.useHandwrittenTitles") }
    }
    /// When false, icons are tinted like system icons (so black ink stays visible in dark mode).
    @Published var keepInkColors = UserDefaults.standard.bool(forKey: "theme.keepInkColors") {
        didSet { UserDefaults.standard.set(keepInkColors, forKey: "theme.keepInkColors") }
    }

    private let folder: URL

    init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Theme", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
    }

    var hasPersonalization: Bool { !images.isEmpty }
    var wordmark: UIImage? { images["wordmark"] }
    var logo: UIImage? { images["logo"] }
    var emptyLibraryDoodle: UIImage? { images["illustration.empty"] }
    var caughtUpDoodle: UIImage? { images["illustration.caughtUp"] }
    func rating(_ value: Int) -> UIImage? { images["rating.\(value)"] }

    func icon(_ id: String) -> UIImage? { useCustomIcons ? images["icon.\(id)"] : nil }
    func cover(_ index: Int) -> UIImage? { images["cover.\(index)"] }
    var availableCovers: [Int] { (0..<KitLayout.coverCount).filter { images["cover.\($0)"] != nil } }

    func glyph(for character: Character) -> UIImage? {
        KitLayout.glyphID(for: character).flatMap { images[$0] }
    }

    /// True if enough of `text` can be written with the user's own letters.
    func canHandwrite(_ text: String) -> Bool {
        guard useHandwrittenTitles else { return false }
        let letters = text.filter { $0.isLetter || $0.isNumber }
        guard !letters.isEmpty else { return false }
        let covered = letters.filter { glyph(for: $0) != nil }.count
        return Double(covered) / Double(letters.count) >= 0.8
    }

    /// Parchment's own logo in its standard colors, used until you draw your own.
    static let standardLogo: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120), format: format).image { context in
            KitPDFRenderer.drawStandardLogo(in: CGRect(x: 0, y: 0, width: 120, height: 120), context: context.cgContext)
        }
    }()

    var logoOrStandard: UIImage { logo ?? Self.standardLogo }

    /// Applies pages drawn in another app (only the boxes on those pages change).
    func apply(_ extracted: [String: UIImage], onPages pages: Set<Int>) {
        for slot in KitLayout.slots where pages.contains(slot.page) {
            let url = folder.appendingPathComponent(slot.fileName)
            if let image = extracted[slot.id], let png = image.pngData() {
                try? png.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        load()
    }

    /// Replaces the theme with what was drawn on the kit. Empty boxes clear that item,
    /// so the kit always reflects exactly what you see in Parchment.
    func apply(_ extracted: [String: UIImage]) {
        for slot in KitLayout.slots {
            let url = folder.appendingPathComponent(slot.fileName)
            if let image = extracted[slot.id], let png = image.pngData() {
                try? png.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        load()
    }

    func reset() {
        for slot in KitLayout.slots {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(slot.fileName))
        }
        load()
    }

    private func load() {
        var loaded: [String: UIImage] = [:]
        for slot in KitLayout.slots {
            let url = folder.appendingPathComponent(slot.fileName)
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data, scale: 3) {
                loaded[slot.id] = image
            }
        }
        images = loaded
    }
}
