import Foundation

/// A whole notebook packed into one file (`.parchment`).
///
/// On the device each notebook is a folder (manifest + one file per page) so saving
/// a stroke only rewrites one small file. For sharing, AirDrop and cloud sync we pack
/// everything into a single binary property list, which stores the drawing and PDF
/// bytes as-is (no base64 bloat).
struct NotebookArchive: Codable {
    static let fileExtension = "parchment"
    static let magic = "parchment-archive"

    var magic = NotebookArchive.magic
    var version = 1
    var notebook: Notebook
    /// Page ID (uuidString) → PencilKit drawing data.
    var drawings: [String: Data]
    var pdf: Data?
    /// The notebook's imported cover image (absent in older archives).
    var coverImage: Data?

    func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> NotebookArchive {
        let archive = try PropertyListDecoder().decode(NotebookArchive.self, from: data)
        guard archive.magic == magic else { throw ParchmentError.invalidFile("This isn't a Parchment notebook.") }
        return archive
    }
}

enum ParchmentError: LocalizedError {
    case invalidFile(String)
    case notFound(String)
    case sync(String)
    case notConfigured(String)

    var errorDescription: String? {
        switch self {
        case .invalidFile(let message), .notFound(let message), .sync(let message), .notConfigured(let message):
            return message
        }
    }
}
