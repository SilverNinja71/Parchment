import Foundation
import CoreGraphics

// This file is shared with the Mac tool in Tools/KitGen, so it must only use
// Foundation and CoreGraphics (no UIKit).

enum KitSlotKind: String, Codable {
    case wordmark, logo, icon, cover, illustration, glyph, rating
}

/// One box on the personalization kit that the user draws in.
struct KitSlot: Identifiable, Hashable {
    let id: String
    let label: String
    let kind: KitSlotKind
    /// 0-based kit page.
    let page: Int
    /// Box in PDF points with a top-left origin.
    let rect: CGRect

    /// File-system-safe name (glyph IDs use code points, so "A" and "a" never collide).
    var fileName: String { id.replacingOccurrences(of: ".", with: "-") + ".png" }

    /// Which part of a box becomes the image, given where the ink is. `unit` is how many
    /// of the caller's units make one kit point (1 for page points, pixels-per-point for images).
    func cropRect(ink: CGRect, box: CGRect, unit: CGFloat = 1) -> CGRect {
        switch kind {
        case .glyph:
            // Keep the full box height so every letter shares the same baseline.
            let pad = box.width * 0.04
            return CGRect(x: ink.minX - pad, y: box.minY, width: ink.width + pad * 2, height: box.height).intersection(box)
        case .cover, .illustration:
            return box
        case .icon, .logo, .rating:
            // A square around the ink, centered, so icons line up in the toolbar.
            let side = max(ink.width, ink.height) * 1.12
            return CGRect(x: ink.midX - side / 2, y: ink.midY - side / 2, width: side, height: side)
        case .wordmark:
            return ink.insetBy(dx: -6 * unit, dy: -6 * unit)
        }
    }
}

enum KitLayout {
    static let version = 1
    static let keyword = "ParchmentKit-\(version)"
    static let fileExtension = "parchmentkit"
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 48

    /// Fractions of a glyph box's height (from the top) for the writing guides.
    static let glyphCapLine: CGFloat = 0.18
    static let glyphXHeightLine: CGFloat = 0.35
    static let glyphBaseline: CGFloat = 0.72

    static let pages: [(title: String, subtitle: String)] = [
        ("Your mark & toolbar", "Write the app's name, draw a little logo, then draw each toolbar icon."),
        ("Covers & doodles", "Design up to six notebook covers and a doodle for the empty library."),
        ("Your handwriting · A to Z", "Parchment writes notebook titles with your letters. Sit capitals on the solid line."),
        ("Your handwriting · a to z, 0 to 9", "Lowercase letters reach the dashed middle line; tall ones reach the top line."),
        ("Study & subjects", "Icons for studying, your 1 to 5 rating buttons, and a doodle for finishing a session."),
    ]

    /// Toolbar and app icons in kit order, with the SF Symbol Parchment shows by default.
    /// IDs are referenced by the app's `ThemeIcon`.
    static let icons: [(id: String, label: String, symbol: String)] = [
        ("pen", "Pen", "pencil.tip"), ("highlighter", "Highlighter", "highlighter"), ("eraser", "Eraser", "eraser"),
        ("lasso", "Lasso", "lasso"), ("convert", "Convert to text", "character.cursor.ibeam"), ("ruler", "Ruler", "ruler"),
        ("undo", "Undo", "arrow.uturn.backward"), ("redo", "Redo", "arrow.uturn.forward"), ("addPage", "Add page", "doc.badge.plus"),
        ("pages", "Pages", "sidebar.left"), ("share", "Share", "square.and.arrow.up"), ("more", "More", "ellipsis.circle"),
        ("library", "Library", "books.vertical"), ("newNotebook", "New notebook", "plus"), ("importPDF", "Import PDF", "doc.richtext"),
        ("sync", "Sync", "arrow.triangle.2.circlepath"), ("settings", "Settings", "gearshape"), ("trash", "Delete", "trash"),
    ]

    /// Icons for the Study section and the sidebar (kit page 5).
    static let studyIcons: [(id: String, label: String, symbol: String)] = [
        ("study", "Study", "graduationcap"), ("flashcards", "Flashcards", "rectangle.on.rectangle.angled"),
        ("recall", "Recall practice", "brain.head.profile"), ("timer", "Timer", "timer"),
        ("flip", "Flip card", "arrow.left.arrow.right"), ("hide", "Hide page", "eye.slash"),
        ("reveal", "Show answer", "eye"), ("done", "Done", "checkmark.circle"),
        ("next", "Next", "arrow.right.circle"), ("subjects", "Subjects", "folder"),
        ("deck", "Deck", "square.stack"), ("allNotes", "All notes", "note.text"),
    ]

    static var allIcons: [(id: String, label: String, symbol: String)] { icons + studyIcons }

    /// Labels for the 1–5 rating boxes (match `RecallRating`).
    static let ratingLabels = ["Forgot", "Wrong", "Hard", "Good", "Easy"]

    static let coverCount = 6
    static let uppercase = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let lowercaseAndDigits = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    static let slots: [KitSlot] = makeSlots()

    static func slot(_ id: String) -> KitSlot? { slots.first { $0.id == id } }

    static func glyphID(for character: Character) -> String? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return nil }
        return "glyph.\(scalar.value)"
    }

    private static func makeSlots() -> [KitSlot] {
        var slots: [KitSlot] = []
        let contentWidth = pageSize.width - margin * 2

        // Page 0 – wordmark, logo and icons.
        let logoSize: CGFloat = 110
        slots.append(KitSlot(id: "wordmark", label: "Write \"Parchment\" (or any name you like)", kind: .wordmark, page: 0,
                             rect: CGRect(x: margin, y: 150, width: contentWidth - logoSize - 16, height: logoSize)))
        slots.append(KitSlot(id: "logo", label: "Logo", kind: .logo, page: 0,
                             rect: CGRect(x: pageSize.width - margin - logoSize, y: 150, width: logoSize, height: logoSize)))
        let iconGap: CGFloat = 12
        let iconSize = (contentWidth - iconGap * 5) / 6
        for (index, icon) in icons.enumerated() {
            let row = CGFloat(index / 6), column = CGFloat(index % 6)
            slots.append(KitSlot(id: "icon.\(icon.id)", label: icon.label, kind: .icon, page: 0,
                                 rect: CGRect(x: margin + column * (iconSize + iconGap), y: 322 + row * (iconSize + 40),
                                              width: iconSize, height: iconSize)))
        }

        // Page 1 – covers and the empty-library doodle.
        let coverGap: CGFloat = 20
        let coverWidth = (contentWidth - coverGap * 2) / 3
        let coverHeight = (coverWidth * 4 / 3).rounded()
        for index in 0..<coverCount {
            let row = CGFloat(index / 3), column = CGFloat(index % 3)
            slots.append(KitSlot(id: "cover.\(index)", label: "Cover \(index + 1)", kind: .cover, page: 1,
                                 rect: CGRect(x: margin + column * (coverWidth + coverGap), y: 150 + row * (coverHeight + 36),
                                              width: coverWidth, height: coverHeight)))
        }
        slots.append(KitSlot(id: "illustration.empty", label: "Doodle for an empty library", kind: .illustration, page: 1,
                             rect: CGRect(x: margin, y: 150 + 2 * (coverHeight + 36) + 4, width: contentWidth, height: 96)))

        // Pages 2 and 3 – handwriting glyphs.
        func addGlyphs(_ characters: [Character], page: Int, top: CGFloat) {
            let gap: CGFloat = 12
            let width = (contentWidth - gap * 5) / 6
            let height: CGFloat = 84
            for (index, character) in characters.enumerated() {
                guard let id = glyphID(for: character) else { continue }
                let row = CGFloat(index / 6), column = CGFloat(index % 6)
                slots.append(KitSlot(id: id, label: String(character), kind: .glyph, page: page,
                                     rect: CGRect(x: margin + column * (width + gap), y: top + row * (height + 20),
                                                  width: width, height: height)))
            }
        }
        addGlyphs(uppercase, page: 2, top: 150)
        addGlyphs(lowercaseAndDigits, page: 3, top: 142)

        // Page 4 – study icons, 1–5 ratings, "all caught up" doodle.
        for (index, icon) in studyIcons.enumerated() {
            let row = CGFloat(index / 6), column = CGFloat(index % 6)
            slots.append(KitSlot(id: "icon.\(icon.id)", label: icon.label, kind: .icon, page: 4,
                                 rect: CGRect(x: margin + column * (iconSize + iconGap), y: 150 + row * (iconSize + 40),
                                              width: iconSize, height: iconSize)))
        }
        let ratingGap: CGFloat = 12
        let ratingWidth = (contentWidth - ratingGap * 4) / 5
        for (index, label) in ratingLabels.enumerated() {
            slots.append(KitSlot(id: "rating.\(index + 1)", label: "\(index + 1) · \(label)", kind: .rating, page: 4,
                                 rect: CGRect(x: margin + CGFloat(index) * (ratingWidth + ratingGap), y: 410,
                                              width: ratingWidth, height: ratingWidth)))
        }
        slots.append(KitSlot(id: "illustration.caughtUp", label: "Doodle for \"All caught up!\"", kind: .illustration, page: 4,
                             rect: CGRect(x: margin, y: 560, width: contentWidth, height: 150)))
        return slots
    }
}
