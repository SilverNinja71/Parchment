import Foundation

/// Anki integration for BelloBook:
/// - Cloze deletion parsing (`{{c1::answer}}` and `{{c1::answer::hint}}`)
/// - Anki Tab-Separated `.txt` import & export (`#separator:tab`, `#deck:...`)
/// - Direct desktop AnkiConnect sync (`http://127.0.0.1:8765`)
enum AnkiBridge {

    // MARK: - Cloze Deletion Support

    static func containsCloze(_ text: String) -> Bool {
        text.range(of: #"\{\{c\d+::"#, options: .regularExpression) != nil
    }

    /// Replaces `{{c1::answer}}` with `[...]` or `{{c1::answer::hint}}` with `[hint]`.
    static func clozePrompt(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{c\d+::([^:}]+)(?:::([^}]+))?\}\}"#) else {
            return text
        }
        let ns = text as NSString
        var out = text
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            let hintRange = m.range(at: 2)
            let replacement = hintRange.location != NSNotFound ? "[\(ns.substring(with: hintRange))]" : "[…]"
            if let r = Range(m.range, in: out) {
                out.replaceSubrange(r, with: replacement)
            }
        }
        return out
    }

    /// Reveals `{{c1::answer}}` as `answer` on the back of the card.
    static func clozeAnswer(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{c\d+::([^:}]+)(?:::([^}]+))?\}\}"#) else {
            return text
        }
        let ns = text as NSString
        var out = text
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            let ansRange = m.range(at: 1)
            if ansRange.location != NSNotFound, let r = Range(m.range, in: out) {
                out.replaceSubrange(r, with: ns.substring(with: ansRange))
            }
        }
        return out
    }

    // MARK: - Anki TSV (.txt) Export & Import

    static func exportAnkiTSV(deck: Deck, cards: [Flashcard]) throws -> URL {
        var lines: [String] = [
            "#separator:tab",
            "#html:false",
            "#deck:\(deck.name)",
            "#tags column:3"
        ]
        let tag = (deck.subject ?? "BelloBook").replacingOccurrences(of: " ", with: "_")
        for card in cards {
            let front = card.frontText
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\n", with: "<br>")
            let backSource = containsCloze(card.frontText) && card.backText.isEmpty
                ? clozeAnswer(card.frontText)
                : card.backText
            let back = backSource
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\n", with: "<br>")
            lines.append("\(front)\t\(back)\t\(tag)")
        }
        let content = lines.joined(separator: "\n")
        let safeName = deck.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName)-Anki.txt")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func parseAnkiTSV(_ raw: String) -> [(front: String, back: String)] {
        var results: [(String, String)] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let cols = trimmed.components(separatedBy: "\t")
            if cols.count >= 2 {
                let front = cols[0].replacingOccurrences(of: "<br>", with: "\n")
                let back = cols[1].replacingOccurrences(of: "<br>", with: "\n")
                if !front.isEmpty { results.append((front, back)) }
            } else if containsCloze(trimmed) {
                results.append((clozePrompt(trimmed), clozeAnswer(trimmed)))
            }
        }
        return results
    }

    // MARK: - AnkiConnect Desktop Sync (http://127.0.0.1:8765)

    static func pushDeckToAnkiConnect(deck: Deck, cards: [Flashcard], endpoint: String = "http://127.0.0.1:8765") async throws -> Int {
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }

        // 1. Ensure deck exists in Anki
        try await invokeAnkiConnect(url: url, action: "createDeck", params: ["deck": deck.name])

        // 2. Add notes
        let notes: [[String: Any]] = cards.map { card in
            let front = card.frontText
            let back = card.backText.isEmpty && containsCloze(front) ? clozeAnswer(front) : card.backText
            return [
                "deckName": deck.name,
                "modelName": "Basic",
                "fields": ["Front": front, "Back": back],
                "options": ["allowDuplicate": false],
                "tags": ["bellobook", (deck.subject ?? "notes").replacingOccurrences(of: " ", with: "_")]
            ]
        }
        try await invokeAnkiConnect(url: url, action: "addNotes", params: ["notes": notes])
        return cards.count
    }

    private static func invokeAnkiConnect(url: URL, action: String, params: [String: Any]) async throws {
        let payload: [String: Any] = ["action": action, "version": 6, "params": params]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 6
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = json["error"] as? String {
            throw NSError(domain: "AnkiConnect", code: 1, userInfo: [NSLocalizedDescriptionKey: err])
        }
    }
}
