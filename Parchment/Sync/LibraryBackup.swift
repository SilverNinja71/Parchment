import Foundation

/// Everything that isn't a notebook: flashcards, study progress, subjects and the
/// hand-drawn theme. It travels with the notebooks as one file, so signing in on a
/// new install brings back all of your work, not just your notes.
struct LibraryBackup: Codable {
    static let fileName = "Parchment Library.parchmentlibrary"
    /// Fixed ID for this file in the sync records (notebooks use their own IDs).
    static let recordID = UUID(uuidString: "0A7C1D2E-3F40-4B5C-8D6E-7F8091A2B3C4")!

    var version = 1
    var modified: Date
    var study: Data
    var cardDrawings: [String: Data]
    var subjects: [Subject]
    var theme: [String: Data]

    private static let changedKey = "library.changedAt"

    /// When anything in the library last changed on this device (nil if never).
    static var changedAt: Date? {
        get { UserDefaults.standard.object(forKey: changedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: changedKey) }
    }

    /// Call whenever flashcards, study progress, subjects or the theme change.
    static func touch() { changedAt = Date() }

    func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> LibraryBackup {
        try PropertyListDecoder().decode(LibraryBackup.self, from: data)
    }

    /// Gathers the current library.
    @MainActor
    static func current(store: NotebookStore) -> LibraryBackup? {
        let (study, drawings) = StudyStore.shared.backupPayload()
        guard let study else { return nil }
        return LibraryBackup(modified: changedAt ?? Date(), study: study, cardDrawings: drawings,
                             subjects: store.subjects, theme: ThemeStore.shared.backupImages())
    }

    /// Brings a backup onto this device. With `merging`, both sides changed since the last
    /// sync, so flashcards and subjects from both are kept; the newer theme wins.
    @MainActor
    func restore(store: NotebookStore, merging: Bool) {
        StudyStore.shared.restore(state: study, drawings: cardDrawings, merging: merging)
        store.restoreSubjects(subjects)
        if !merging {
            ThemeStore.shared.restoreImages(theme)
        } else if !theme.isEmpty,
                  !ThemeStore.shared.hasPersonalization || modified > (Self.changedAt ?? .distantPast) {
            // A merge may adopt a drawn theme, but a device without one never erases yours.
            ThemeStore.shared.restoreImages(theme)
        }
    }
}
