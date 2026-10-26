import SwiftUI

/// Every icon in Parchment goes through this view: the user's hand-drawn version
/// if they made one in the Personalization Kit, otherwise an SF Symbol.
enum ThemeIcon: String {
    case pen, highlighter, eraser, lasso, convert, ruler
    case undo, redo, addPage, pages, share, more
    case library, newNotebook, importPDF, sync, settings, trash
    case study, flashcards, recall, timer, flip, hide
    case reveal, done, next, subjects, deck, allNotes

    /// The standard SF Symbol, shared with the Personalization Kit's faint guides.
    var systemImage: String {
        KitLayout.allIcons.first { $0.id == rawValue }?.symbol ?? "questionmark"
    }
}

struct ThemedIcon: View {
    let icon: ThemeIcon
    var size: CGFloat = 22
    @ObservedObject private var theme = ThemeStore.shared

    init(_ icon: ThemeIcon, size: CGFloat = 22) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        if let image = theme.icon(icon.rawValue) {
            Image(uiImage: image)
                .renderingMode(theme.keepInkColors ? .original : .template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: icon.systemImage)
                .font(.system(size: size * 0.82))
                .frame(width: size, height: size)
        }
    }
}

/// A label that pairs a themed icon with text (for menus and buttons).
struct ThemedLabel: View {
    let title: String
    let icon: ThemeIcon

    init(_ title: String, icon: ThemeIcon) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        Label { Text(title) } icon: { ThemedIcon(icon, size: 20) }
    }
}

/// Writes text with the user's own handwriting from the kit, falling back to a serif font.
struct HandwrittenText: View {
    let text: String
    var size: CGFloat = 20
    var weight: Font.Weight = .semibold
    @ObservedObject private var theme = ThemeStore.shared

    init(_ text: String, size: CGFloat = 20, weight: Font.Weight = .semibold) {
        self.text = text
        self.size = size
        self.weight = weight
    }

    var body: some View {
        if theme.canHandwrite(text) {
            let characters = Array(text.count > 32 ? String(text.prefix(31)) + "…" : text)
            HStack(alignment: .lastTextBaseline, spacing: size * 0.02) {
                ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                    glyph(character)
                }
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
        } else {
            Text(text)
                .font(.system(size: size, weight: weight, design: .serif))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func glyph(_ character: Character) -> some View {
        if character == " " {
            Color.clear.frame(width: size * 0.32, height: 1)
        } else if let image = theme.glyph(for: character) {
            // Kit boxes put the baseline 72% of the way down and caps ~54% of the box tall.
            let height = size * 0.72 / (KitLayout.glyphBaseline - KitLayout.glyphCapLine)
            Image(uiImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .alignmentGuide(.lastTextBaseline) { dimensions in dimensions.height * KitLayout.glyphBaseline }
        } else {
            Text(String(character)).font(.system(size: size, weight: weight, design: .serif))
        }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x8B4A2E
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
