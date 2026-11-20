import SwiftUI
import Foundation

/// Obsidian-compatible Markdown, Textbook Callouts (`> [!theorem]`, `> [!definition]`),
/// `[[Wiki-Links]]`, `#tags`, and LaTeX (`$...$`, `$$...$$`) engine for BelloBook.
enum MarkdownTextbookEngine {

    enum BlockKind: Equatable {
        case heading(level: Int, text: String)
        case callout(kind: String, title: String, body: String)
        case latexDisplay(raw: String, pretty: String)
        case paragraph(text: String)
    }

    static func parseBlocks(from text: String) -> [BlockKind] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [BlockKind] = []
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // 1. Display LaTeX block: $$ ... $$
            if trimmed.hasPrefix("$$") {
                if trimmed.hasSuffix("$$") && trimmed.count > 4 {
                    let inner = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                    blocks.append(.latexDisplay(raw: inner, pretty: formatLaTeXForDisplay(inner)))
                    i += 1
                    continue
                } else {
                    var body: [String] = [String(trimmed.dropFirst(2))]
                    i += 1
                    while i < lines.count {
                        let l = lines[i].trimmingCharacters(in: .whitespaces)
                        if l.hasSuffix("$$") {
                            body.append(String(l.dropLast(2)))
                            i += 1
                            break
                        }
                        body.append(l)
                        i += 1
                    }
                    let joined = body.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    blocks.append(.latexDisplay(raw: joined, pretty: formatLaTeXForDisplay(joined)))
                    continue
                }
            }

            // 2. Obsidian Textbook Callout: > [!theorem] Title
            if trimmed.hasPrefix("> [!") {
                if let closeBracket = trimmed.firstIndex(of: "]") {
                    let afterOpen = trimmed.index(trimmed.startIndex, offsetBy: 4)
                    let kind = String(trimmed[afterOpen..<closeBracket]).lowercased()
                    let customTitle = String(trimmed[trimmed.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)
                    let title = customTitle.isEmpty ? kind.capitalized : customTitle
                    var bodyLines: [String] = []
                    i += 1
                    while i < lines.count {
                        let next = lines[i].trimmingCharacters(in: .whitespaces)
                        if next.hasPrefix(">") {
                            bodyLines.append(String(next.dropFirst()).trimmingCharacters(in: .whitespaces))
                            i += 1
                        } else {
                            break
                        }
                    }
                    blocks.append(.callout(kind: kind, title: title, body: bodyLines.joined(separator: "\n")))
                    continue
                }
            }

            // 3. Markdown Headings: # / ## / ###
            if trimmed.hasPrefix("### ") {
                blocks.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                blocks.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                blocks.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
            } else {
                blocks.append(.paragraph(text: trimmed))
            }
            i += 1
        }

        return blocks
    }

    /// Converts LaTeX expressions into clean typographic Unicode math for native SwiftUI display.
    static func formatLaTeXForDisplay(_ latex: String) -> String {
        var s = latex
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // \frac{a}{b} -> (a)/(b)
        if let fracRegex = try? NSRegularExpression(pattern: #"\\frac\{([^{}]+)\}\{([^{}]+)\}"#) {
            let ns = s as NSString
            let matches = fracRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches {
                let num = ns.substring(with: m.range(at: 1))
                let den = ns.substring(with: m.range(at: 2))
                if let r = Range(m.range, in: s) {
                    s.replaceSubrange(r, with: "(\(num))/(\(den))")
                }
            }
        }

        // \sqrt{x} -> √(x)
        if let sqrtRegex = try? NSRegularExpression(pattern: #"\\sqrt\{([^{}]+)\}"#) {
            let ns = s as NSString
            let matches = sqrtRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches {
                let inner = ns.substring(with: m.range(at: 1))
                if let r = Range(m.range, in: s) {
                    s.replaceSubrange(r, with: "√(\(inner))")
                }
            }
        }

        let symbols: [(String, String)] = [
            (#"\cdot"#, "·"), (#"\times"#, "×"), (#"\div"#, "÷"), (#"\pm"#, "±"),
            (#"\leq"#, "≤"), (#"\geq"#, "≥"), (#"\neq"#, "≠"), (#"\approx"#, "≈"),
            (#"\rightarrow"#, "→"), (#"\to"#, "→"), (#"\Rightarrow"#, "⇒"), (#"\iff"#, "⇔"),
            (#"\infty"#, "∞"), (#"\sum"#, "∑"), (#"\prod"#, "∏"), (#"\int"#, "∫"),
            (#"\partial"#, "∂"), (#"\nabla"#, "∇"),
            (#"\alpha"#, "α"), (#"\beta"#, "β"), (#"\gamma"#, "γ"), (#"\delta"#, "δ"),
            (#"\theta"#, "θ"), (#"\lambda"#, "λ"), (#"\mu"#, "μ"), (#"\pi"#, "π"),
            (#"\sigma"#, "σ"), (#"\omega"#, "ω"), (#"\Delta"#, "Δ"), (#"\Omega"#, "Ω"),
            (#"\sin"#, "sin"), (#"\cos"#, "cos"), (#"\tan"#, "tan"),
            (#"\ln"#, "ln"), (#"\log"#, "log"),
            (#"^{2}"#, "²"), (#"^{3}"#, "³"), (#"^2"#, "²"), (#"^3"#, "³")
        ]
        for (k, v) in symbols {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s
    }

    static func extractWikiLinks(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]"#) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces)
        }
    }

    static func extractTags(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|\s)#([A-Za-z][A-Za-z0-9_/-]*)"#) else { return [] }
        let ns = text as NSString
        var seen = Set<String>()
        var tags: [String] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range(at: 1))
            if seen.insert(tag).inserted { tags.append(tag) }
        }
        return tags
    }

    static func backlinks(to notebook: Notebook, in allNotebooks: [Notebook]) -> [Notebook] {
        let target = notebook.title.lowercased()
        return allNotebooks.filter { other in
            guard other.id != notebook.id else { return false }
            let combined = other.pages.flatMap(\.textBlocks).map(\.text).joined(separator: "\n")
            return extractWikiLinks(from: combined).contains { $0.lowercased() == target }
        }
    }
}

/// Obsidian-style Textbook & LaTeX Preview Sheet for any BelloBook notebook.
struct TextbookPreviewSheet: View {
    let notebook: Notebook
    var onOpenLinkedNotebook: (String) -> Void = { _ in }

    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss

    private var combinedMarkdown: String {
        notebook.pages.flatMap(\.textBlocks)
            .sorted { $0.y < $1.y }
            .map(\.text)
            .joined(separator: "\n")
    }

    private var blocks: [MarkdownTextbookEngine.BlockKind] {
        MarkdownTextbookEngine.parseBlocks(from: combinedMarkdown)
    }

    private var tags: [String] { MarkdownTextbookEngine.extractTags(from: combinedMarkdown) }
    private var wikiLinks: [String] { MarkdownTextbookEngine.extractWikiLinks(from: combinedMarkdown) }
    private var incomingBacklinks: [Notebook] { MarkdownTextbookEngine.backlinks(to: notebook, in: store.notebooks) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Obsidian YAML-style Metadata Header
                    if !tags.isEmpty || !wikiLinks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            if !tags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(tags, id: \.self) { tag in
                                            Text("#\(tag)")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(Style.accent)
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 4)
                                                .background(Style.accent.opacity(0.10), in: Capsule())
                                        }
                                    }
                                }
                            }
                            if !wikiLinks.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        Text("Links:")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        ForEach(wikiLinks, id: \.self) { link in
                                            Button {
                                                dismiss()
                                                onOpenLinkedNotebook(link)
                                            } label: {
                                                Text("[[\(link)]]")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(Style.selection)
                                                    .padding(.horizontal, 9)
                                                    .padding(.vertical, 4)
                                                    .background(Style.selection.opacity(0.10), in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.chrome, in: RoundedRectangle(cornerRadius: Style.cardRadius))
                    }

                    if blocks.isEmpty {
                        ContentUnavailableView(
                            "Textbook & Markdown Preview",
                            systemImage: "book.pages",
                            description: Text("Type Markdown headings (#), Obsidian callouts (> [!theorem]), [[Wiki-Links]], or LaTeX ($...$, $$...$$) on your pages to view formatted textbook notes.")
                        )
                    } else {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            renderBlock(block)
                        }
                    }

                    // Incoming Obsidian Backlinks
                    if !incomingBacklinks.isEmpty {
                        Divider().padding(.top, 8)
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Linked Mentions (\(incomingBacklinks.count))", systemImage: "link")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            ForEach(incomingBacklinks) { source in
                                Button {
                                    dismiss()
                                    onOpenLinkedNotebook(source.title)
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.text").foregroundStyle(Style.accent)
                                        Text(source.title).font(.subheadline.weight(.medium))
                                        Spacer()
                                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .background(Color.chrome, in: RoundedRectangle(cornerRadius: Style.controlRadius))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.paper)
            .navigationTitle("Textbook & Obsidian View")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        }
        .wideSheet()
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownTextbookEngine.BlockKind) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(level == 1 ? .title.bold() : level == 2 ? .title2.bold() : .title3.bold())
                .padding(.top, level == 1 ? 8 : 4)
        case .callout(let kind, let title, let body):
            let tint = calloutColor(kind)
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: calloutIcon(kind))
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)
                Text(MarkdownTextbookEngine.formatLaTeXForDisplay(body))
                    .font(.body)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: Style.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Style.cardRadius)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
        case .latexDisplay(let raw, let pretty):
            VStack(spacing: 4) {
                Text(pretty)
                    .font(.system(.title3, design: .serif))
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(raw)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.chrome, in: RoundedRectangle(cornerRadius: Style.cardRadius))
        case .paragraph(let text):
            Text(MarkdownTextbookEngine.formatLaTeXForDisplay(text))
                .font(.body)
                .lineSpacing(4)
        }
    }

    private func calloutColor(_ kind: String) -> Color {
        switch kind {
        case "theorem", "important", "formula": return Style.accent
        case "definition", "tip", "example": return Color(red: 0.18, green: 0.58, blue: 0.32)
        case "warning", "caution": return Color(red: 0.82, green: 0.28, blue: 0.14)
        default: return Style.selection
        }
    }

    private func calloutIcon(_ kind: String) -> String {
        switch kind {
        case "theorem", "formula": return "function"
        case "definition": return "book.closed"
        case "tip", "example": return "lightbulb"
        case "warning", "caution": return "exclamationmark.triangle"
        default: return "info.circle"
        }
    }
}
