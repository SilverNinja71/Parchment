import Foundation

/// Two-way Obsidian Vault Markdown (.md) sync helper for BelloBook.
/// Exports notebooks with YAML frontmatter (`title`, `folder`, `tags`, `updated`),
/// `[[Wiki-Links]]`, `> [!callout]` textbook blocks, and `$...$` / `$$...$$` LaTeX,
/// and imports Obsidian `.md` notes cleanly as BelloBook notebooks.
@MainActor
enum ObsidianVaultSync {

    static func exportVault(notebooks: [Notebook], to vaultFolderURL: URL) throws -> Int {
        let accessed = vaultFolderURL.startAccessingSecurityScopedResource()
        defer { if accessed { vaultFolderURL.stopAccessingSecurityScopedResource() } }

        var count = 0
        for nb in notebooks {
            let subFolder = (nb.folderPath ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let targetDir = subFolder.isEmpty
                ? vaultFolderURL
                : vaultFolderURL.appendingPathComponent(subFolder, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

            let body = nb.pages.flatMap(\.textBlocks)
                .sorted { $0.y < $1.y }
                .map(\.text)
                .joined(separator: "\n\n")
            let tags = MarkdownTextbookEngine.extractTags(from: body)
            let iso = ISO8601DateFormatter().string(from: nb.modified)

            var md = "---\n"
            md += "title: \"\(nb.title.replacingOccurrences(of: "\"", with: "\\\""))\"\n"
            if !subFolder.isEmpty { md += "folder: \"\(subFolder)\"\n" }
            if let subject = nb.subject, !subject.isEmpty { md += "subject: \"\(subject)\"\n" }
            if !tags.isEmpty { md += "tags: [\(tags.joined(separator: ", "))]\n" }
            md += "updated: \(iso)\n"
            md += "bellobook_id: \(nb.id.uuidString)\n"
            md += "---\n\n"
            md += "# \(nb.title)\n\n"
            md += body.isEmpty ? "_Handwritten or blank logbook page._\n" : body + "\n"

            let safeName = nb.title.replacingOccurrences(of: "/", with: "-")
            let fileURL = targetDir.appendingPathComponent("\(safeName).md")
            try md.write(to: fileURL, atomically: true, encoding: .utf8)
            count += 1
        }
        return count
    }

    static func importMarkdownFiles(from vaultFolderURL: URL, into store: NotebookStore) throws -> Int {
        let accessed = vaultFolderURL.startAccessingSecurityScopedResource()
        defer { if accessed { vaultFolderURL.stopAccessingSecurityScopedResource() } }

        let enumerator = FileManager.default.enumerator(
            at: vaultFolderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var imported = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let relPath = fileURL.deletingLastPathComponent().path
                .replacingOccurrences(of: vaultFolderURL.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            let stripped = stripFrontmatter(raw)
            let title = fileURL.deletingPathExtension().lastPathComponent
            let block = TextBlock(
                text: stripped.trimmingCharacters(in: .whitespacesAndNewlines),
                x: 48,
                y: 80,
                width: 720,
                height: 600,
                fontSize: 18,
                flows: true
            )
            let page = Page(
                kind: .document,
                paper: .ruled,
                width: Page.documentWidth,
                height: Page.documentMinHeight,
                textBlocks: [block]
            )
            let nb = store.createNotebook(title: title, kind: .document, paper: .ruled)
            store.update(nb.id) { item in
                item.folderPath = relPath.isEmpty ? "Obsidian" : relPath
                item.pages = [page]
            }
            imported += 1
        }
        return imported
    }

    private static func stripFrontmatter(_ raw: String) -> String {
        guard raw.hasPrefix("---") else { return raw }
        let lines = raw.components(separatedBy: .newlines)
        guard lines.count > 2 else { return raw }
        if let endIdx = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            return lines[(endIdx + 1)...].joined(separator: "\n")
        }
        return raw
    }
}
