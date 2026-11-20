import Foundation

/// Obsidian Vault Markdown (.md) helper for BelloBook.
/// Writes notebooks as notes with YAML frontmatter (`title`, `folder`, `tags`, `updated`),
/// `[[Wiki-Links]]`, `> [!callout]` textbook blocks, and `$...$` / `$$...$$` LaTeX. Syncing with
/// an Obsidian vault uses `markdown(for:)`; reading notes back in (`importMarkdownFiles`) is not
/// wired to any screen yet.
@MainActor
enum ObsidianVaultSync {

    /// One notebook as an Obsidian note: YAML frontmatter, a title heading, then its typed text
    /// page by page. Handwriting stays in the notebook's `.parchment` file.
    static func markdown(for nb: Notebook) -> String {
        // A block's y is measured within its own page, so sort inside each page.
        let body = nb.pages
            .flatMap { $0.textBlocks.sorted { $0.y < $1.y } }
            .map(\.text)
            .joined(separator: "\n\n")
        let tags = MarkdownTextbookEngine.extractTags(from: body)

        var md = "---\n"
        md += "title: \(yaml(nb.title))\n"
        if let folder = nb.folderPath, !folder.isEmpty { md += "folder: \(yaml(folder))\n" }
        if let subject = nb.subject, !subject.isEmpty { md += "subject: \(yaml(subject))\n" }
        if !tags.isEmpty { md += "tags: [\(tags.joined(separator: ", "))]\n" }
        md += "updated: \(ISO8601DateFormatter().string(from: nb.modified))\n"
        md += "bellobook_id: \(nb.id.uuidString)\n"
        md += "---\n\n"
        md += "# \(nb.title.components(separatedBy: .newlines).joined(separator: " "))\n\n"
        md += body.isEmpty ? "_Handwritten or blank logbook page._\n" : body + "\n"
        return md
    }

    /// A YAML double-quoted string: backslashes and quotes escaped, kept on one line.
    static func yaml(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .components(separatedBy: .newlines)
            .joined(separator: " ")
        return "\"\(escaped)\""
    }

    /// The notebook a Markdown note was written from, if BelloBook wrote it.
    static func notebookID(inFrontmatterOf markdown: String) -> UUID? {
        guard markdown.hasPrefix("---") else { return nil }
        for line in markdown.components(separatedBy: .newlines).dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if trimmed.hasPrefix("bellobook_id:") {
                let value = trimmed.dropFirst("bellobook_id:".count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \""))
                return UUID(uuidString: value)
            }
        }
        return nil
    }

    static func exportVault(notebooks: [Notebook], to vaultFolderURL: URL) throws -> Int {
        let accessed = vaultFolderURL.startAccessingSecurityScopedResource()
        defer { if accessed { vaultFolderURL.stopAccessingSecurityScopedResource() } }

        var count = 0
        var usedPaths = Set<String>()
        for nb in notebooks {
            // Folder names come from notebooks that may have been shared or synced: keep every
            // part inside the vault.
            let subFolder = (nb.folderPath ?? "")
                .split(separator: "/").map(String.init)
                .filter { $0 != "." && $0 != ".." }
                .map(NotebookStore.safeFileName)
                .joined(separator: "/")
            let targetDir = subFolder.isEmpty
                ? vaultFolderURL
                : vaultFolderURL.appendingPathComponent(subFolder, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

            // Two notebooks with the same title must not write over each other.
            var safeName = NotebookStore.safeFileName(nb.title)
            if !usedPaths.insert("\(subFolder)/\(safeName)".lowercased()).inserted {
                safeName += " \(nb.id.uuidString.prefix(4))"
            }
            let fileURL = targetDir.appendingPathComponent("\(safeName).md")
            try markdown(for: nb).write(to: fileURL, atomically: true, encoding: .utf8)
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
