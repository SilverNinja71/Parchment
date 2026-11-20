import Foundation
import UniformTypeIdentifiers
import UIKit

/// Manages on-device storage for photos, audio, videos, and documents attached to BelloBook pages,
/// as well as Markdown export (Amphi Notes / Cloud / Photos parity).
@MainActor
final class MediaVault {
    static let shared = MediaVault()
    private init() {}

    private var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("BelloBookMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func folder(for notebookID: UUID) -> URL {
        let dir = rootDirectory.appendingPathComponent(notebookID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func fileURL(for attachment: MediaAttachment, in notebookID: UUID) -> URL {
        folder(for: notebookID).appendingPathComponent(Self.safeFileName(attachment.filename, fallback: attachment.id.uuidString))
    }

    /// The last path component only. Attachment names arrive in notebooks that were shared or
    /// synced, so "../../x" must never reach outside the notebook's own media folder.
    static func safeFileName(_ name: String, fallback: String) -> String {
        let last = (name as NSString).lastPathComponent
        return last.isEmpty || last == "." || last == ".." || last == "/" ? fallback : last
    }

    /// Copies a user-picked file into the notebook's private Media Vault and returns a `MediaAttachment`.
    func importFile(from sourceURL: URL, into notebookID: UUID) throws -> MediaAttachment {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension
        let utType = UTType(filenameExtension: ext)
        let kind: MediaKind
        if utType?.conforms(to: .image) == true {
            kind = .image
        } else if utType?.conforms(to: .audio) == true {
            kind = .audio
        } else if utType?.conforms(to: .movie) == true || utType?.conforms(to: .video) == true {
            kind = .video
        } else {
            kind = .file
        }

        let safeBase = sourceURL.deletingPathExtension().lastPathComponent
        let uniqueName = "\(UUID().uuidString.prefix(8))-\(sourceURL.lastPathComponent)"
        let dest = folder(for: notebookID).appendingPathComponent(uniqueName)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0

        return MediaAttachment(
            kind: kind,
            filename: uniqueName,
            title: safeBase.isEmpty ? sourceURL.lastPathComponent : safeBase,
            mimeType: utType?.preferredMIMEType ?? "application/octet-stream",
            byteCount: size
        )
    }

    /// Saves a `UIImage` directly into the notebook's Media Vault (e.g. from Photos library or camera).
    func saveImage(_ image: UIImage, title: String = "Photo", into notebookID: UUID) throws -> MediaAttachment {
        guard let data = image.jpegData(compressionQuality: 0.88) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let filename = "\(UUID().uuidString.prefix(8))-photo.jpg"
        let dest = folder(for: notebookID).appendingPathComponent(filename)
        try data.write(to: dest, options: .atomic)
        return MediaAttachment(
            kind: .image,
            filename: filename,
            title: title,
            mimeType: "image/jpeg",
            byteCount: data.count
        )
    }

    func remove(_ attachment: MediaAttachment, from notebookID: UUID) {
        let url = fileURL(for: attachment, in: notebookID)
        try? FileManager.default.removeItem(at: url)
    }

    /// Generates a clean Markdown (.md) document for a notebook, including text blocks and media links.
    func exportMarkdown(notebook: Notebook) throws -> URL {
        var md = "# \(notebook.title)\n\n"
        if let folder = notebook.folderPath, !folder.isEmpty {
            md += "*Folder:* `\(folder)`\n\n"
        }
        if let subject = notebook.subject, !subject.isEmpty {
            md += "*Subject:* `\(subject)`\n\n"
        }

        for (idx, page) in notebook.pages.enumerated() {
            md += "## Page \(idx + 1) (\(page.kind.title))\n\n"
            let sortedBlocks = page.textBlocks.sorted { $0.y < $1.y }
            for block in sortedBlocks {
                let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    md += "\(text)\n\n"
                }
            }
            if let attachments = page.attachments, !attachments.isEmpty {
                md += "### Attachments\n"
                for item in attachments {
                    switch item.kind {
                    case .image:
                        md += "- ![Image: \(item.title)](\(item.filename))\n"
                    case .audio:
                        let meta = item.artist.isEmpty ? "" : " — \(item.artist)"
                        md += "- [Audio: \(item.title)\(meta)](\(item.filename))\n"
                    case .video:
                        md += "- [Video: \(item.title)](\(item.filename))\n"
                    case .file:
                        md += "- [File: \(item.title)](\(item.filename))\n"
                    }
                }
                md += "\n"
            }
        }

        let safeTitle = notebook.title
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let outName = (safeTitle.isEmpty ? "BelloBook" : safeTitle) + ".md"
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent(outName)
        try md.write(to: outURL, atomically: true, encoding: .utf8)
        return outURL
    }
}
