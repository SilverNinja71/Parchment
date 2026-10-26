import SwiftUI

/// App-wide preferences, stored in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// MyScript's "Active pen" mode: Apple Pencil writes, fingers scroll. Turn on to write with a finger.
    @Published var fingerDraws: Bool { didSet { defaults.set(fingerDraws, forKey: Keys.fingerDraws) } }
    /// Scribble back and forth over ink to erase it, like MyScript's scratch-out gesture.
    @Published var scratchOutToErase: Bool { didSet { defaults.set(scratchOutToErase, forKey: Keys.scratchOut) } }
    @Published var defaultPageKind: PageKind { didSet { defaults.set(defaultPageKind.rawValue, forKey: Keys.pageKind) } }
    @Published var defaultPaper: PaperStyle { didSet { defaults.set(defaultPaper.rawValue, forKey: Keys.paper) } }
    @Published var recognitionLanguage: String { didSet { defaults.set(recognitionLanguage, forKey: Keys.language) } }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let fingerDraws = "settings.fingerDraws"
        static let scratchOut = "settings.scratchOut"
        static let pageKind = "settings.defaultPageKind"
        static let paper = "settings.defaultPaper"
        static let language = "settings.recognitionLanguage"
    }

    init() {
        #if targetEnvironment(simulator)
        let fingerDefault = true // there's no Apple Pencil in the simulator
        #else
        let fingerDefault = false
        #endif
        fingerDraws = defaults.object(forKey: Keys.fingerDraws) as? Bool ?? fingerDefault
        scratchOutToErase = defaults.object(forKey: Keys.scratchOut) as? Bool ?? true
        defaultPageKind = PageKind(rawValue: defaults.string(forKey: Keys.pageKind) ?? "") ?? .document
        defaultPaper = PaperStyle(rawValue: defaults.string(forKey: Keys.paper) ?? "") ?? .ruled
        recognitionLanguage = defaults.string(forKey: Keys.language) ?? "automatic"
    }
}
