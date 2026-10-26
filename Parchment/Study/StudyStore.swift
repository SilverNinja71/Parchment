import Foundation
import Combine

/// The 1–5 confidence scale used everywhere in Study.
enum RecallRating: Int, CaseIterable, Identifiable {
    case forgot = 1, wrong, hard, good, easy

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .forgot: return "Forgot"
        case .wrong: return "Wrong"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }

    var colorHex: String {
        switch self {
        case .forgot: return "C2524A"
        case .wrong: return "D9822B"
        case .hard: return "B8862B"
        case .good: return "3F7A4A"
        case .easy: return "2E5E8B"
        }
    }
}

/// Spaced-repetition state (SM-2, the algorithm Anki grew out of), adapted to a 1–5 scale.
struct ReviewSchedule: Codable, Equatable {
    var ease: Double = 2.5
    /// Days until the next review once learned.
    var interval: Double = 0
    var repetitions = 0
    var lapses = 0
    var due: Date = .distantPast
    var lastReviewed: Date?

    var isNew: Bool { lastReviewed == nil }
    func isDue(at date: Date = Date()) -> Bool { due <= date }

    func next(_ rating: RecallRating, now: Date = Date()) -> ReviewSchedule {
        var next = self
        next.lastReviewed = now
        let q = Double(rating.rawValue)

        if rating.rawValue <= 2 {
            // Missed: start over and see it again in this session (1 or 10 minutes, like Anki).
            if !isNew { next.lapses += 1 }
            next.repetitions = 0
            next.interval = 0
            next.due = now.addingTimeInterval(rating == .forgot ? 60 : 600)
        } else {
            next.repetitions += 1
            switch next.repetitions {
            case 1: next.interval = rating == .easy ? 3 : 1
            case 2: next.interval = rating == .easy ? 7 : rating == .hard ? 3 : 6
            default:
                // Like Anki: Hard grows the gap a little, Good by the ease factor, Easy a bit more.
                let grown = rating == .hard ? interval * 1.2 : interval * ease * (rating == .easy ? 1.3 : 1)
                next.interval = max(interval + 1, grown.rounded())
            }
            next.due = now.addingTimeInterval(next.interval * 86_400)
        }
        next.ease = max(1.3, ease + 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
        return next
    }

    /// "1m", "10m", "4d", "2mo" – shown under each rating button, like Anki.
    func preview(_ rating: RecallRating) -> String {
        let seconds = next(rating).due.timeIntervalSinceNow
        switch seconds {
        case ..<3_600: return "\(max(1, Int((seconds / 60).rounded())))m"
        case ..<86_400: return "\(Int((seconds / 3_600).rounded()))h"
        case ..<(86_400 * 30): return "\(Int((seconds / 86_400).rounded()))d"
        case ..<(86_400 * 365): return "\(Int((seconds / (86_400 * 30)).rounded()))mo"
        default: return String(format: "%.1fy", seconds / (86_400 * 365))
        }
    }
}

struct Deck: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var subject: String?
    var created = Date()
}

struct Flashcard: Codable, Identifiable, Equatable {
    var id = UUID()
    var deckID: UUID
    var frontText: String = ""
    var backText: String = ""
    var created = Date()
    var schedule = ReviewSchedule()
}

enum CardSide: String { case front, back }

/// Decks, cards and review history for the Study section.
@MainActor
final class StudyStore: ObservableObject {
    static let shared = StudyStore()
    static let newCardsPerSession = 20

    @Published private(set) var decks: [Deck] = []
    @Published private(set) var cards: [Flashcard] = []
    /// Recall-practice schedule for each notebook page (by page ID).
    @Published private(set) var pageSchedules: [UUID: ReviewSchedule] = [:]
    /// Reviews done per day ("2026-10-19": 42).
    @Published private(set) var reviewLog: [String: Int] = [:]

    private struct Saved: Codable {
        var decks: [Deck]
        var cards: [Flashcard]
        var pageSchedules: [UUID: ReviewSchedule]
        var reviewLog: [String: Int]
    }

    private let folder: URL
    private var stateURL: URL { folder.appendingPathComponent("study.json") }
    private var cardsFolder: URL { folder.appendingPathComponent("cards", isDirectory: true) }

    init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Study", isDirectory: true)
        try? FileManager.default.createDirectory(at: cardsFolder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            decks = saved.decks
            cards = saved.cards
            pageSchedules = saved.pageSchedules
            reviewLog = saved.reviewLog
        }
    }

    // MARK: - Decks

    @discardableResult
    func addDeck(name: String, subject: String?) -> Deck {
        let deck = Deck(name: name.isEmpty ? "New Deck" : name, subject: subject)
        decks.append(deck)
        save()
        return deck
    }

    func renameDeck(_ id: UUID, to name: String) {
        guard let index = decks.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        decks[index].name = name
        save()
    }

    func deleteDeck(_ id: UUID) {
        for card in cards where card.deckID == id { removeDrawings(for: card.id) }
        cards.removeAll { $0.deckID == id }
        decks.removeAll { $0.id == id }
        save()
    }

    func cards(in deckID: UUID?) -> [Flashcard] {
        guard let deckID else { return cards }
        return cards.filter { $0.deckID == deckID }
    }

    /// Anki's deck counts: new cards waiting and learned cards due.
    func counts(for deckID: UUID?) -> (new: Int, due: Int) {
        let deckCards = cards(in: deckID)
        let new = min(deckCards.filter(\.schedule.isNew).count, Self.newCardsPerSession * max(1, deckID == nil ? decks.count : 1))
        let due = deckCards.filter { !$0.schedule.isNew && $0.schedule.isDue() }.count
        return (new, due)
    }

    /// Cards to study now: due reviews first, then a limited number of new cards.
    func sessionQueue(for deckID: UUID?) -> [UUID] {
        let deckCards = cards(in: deckID)
        let due = deckCards.filter { !$0.schedule.isNew && $0.schedule.isDue() }.sorted { $0.schedule.due < $1.schedule.due }
        let new = deckCards.filter(\.schedule.isNew).sorted { $0.created < $1.created }
            .prefix(Self.newCardsPerSession * max(1, deckID == nil ? decks.count : 1))
        return (due + new).map(\.id)
    }

    // MARK: - Cards

    func card(_ id: UUID) -> Flashcard? { cards.first { $0.id == id } }

    func saveCard(_ card: Flashcard, front: Data?, back: Data?) {
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            cards[index] = card
        } else {
            cards.append(card)
        }
        write(front, to: drawingURL(card.id, .front))
        write(back, to: drawingURL(card.id, .back))
        save()
    }

    func deleteCard(_ id: UUID) {
        removeDrawings(for: id)
        cards.removeAll { $0.id == id }
        save()
    }

    func drawing(for id: UUID, side: CardSide) -> Data? {
        try? Data(contentsOf: drawingURL(id, side))
    }

    func review(_ id: UUID, rating: RecallRating) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].schedule = cards[index].schedule.next(rating)
        logReview()
        save()
    }

    // MARK: - Recall practice (notebook pages)

    func pageSchedule(_ pageID: UUID) -> ReviewSchedule { pageSchedules[pageID] ?? ReviewSchedule() }

    func reviewPage(_ pageID: UUID, rating: RecallRating) {
        pageSchedules[pageID] = pageSchedule(pageID).next(rating)
        logReview()
        save()
    }

    // MARK: - Stats

    var reviewedToday: Int { reviewLog[Self.dayKey(Date())] ?? 0 }

    /// Days in a row with at least one review, ending today or yesterday.
    var streak: Int {
        var day = Date()
        if reviewLog[Self.dayKey(day)] == nil { day = day.addingTimeInterval(-86_400) }
        var count = 0
        while reviewLog[Self.dayKey(day)] != nil {
            count += 1
            day = day.addingTimeInterval(-86_400)
        }
        return count
    }

    private func logReview() {
        reviewLog[Self.dayKey(Date()), default: 0] += 1
    }

    private static func dayKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    // MARK: - Files

    private func drawingURL(_ id: UUID, _ side: CardSide) -> URL {
        cardsFolder.appendingPathComponent("\(id.uuidString)-\(side.rawValue).drawing")
    }

    private func write(_ data: Data?, to url: URL) {
        if let data { try? data.write(to: url, options: .atomic) } else { try? FileManager.default.removeItem(at: url) }
    }

    private func removeDrawings(for id: UUID) {
        try? FileManager.default.removeItem(at: drawingURL(id, .front))
        try? FileManager.default.removeItem(at: drawingURL(id, .back))
    }

    private func save() {
        let saved = Saved(decks: decks, cards: cards, pageSchedules: pageSchedules, reviewLog: reviewLog)
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: stateURL, options: .atomic) }
    }
}
