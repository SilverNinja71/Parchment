import Foundation

/// Anki integration for BelloBook:
/// - Cloze deletion parsing (`{{c1::answer}}` and `{{c1::answer::hint}}`)
/// - Anki Tab-Separated `.txt` import & export (`#separator:tab`, `#deck:...`)
/// - Sending a deck to desktop Anki over your network through AnkiConnect
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

    // MARK: - Anki fields

    /// One field as Anki HTML: markup escaped, line breaks as <br>, no tabs.
    private static func ankiField(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// Front and back as Anki should show them: a cloze front becomes its prompt, so the
    /// answer isn't given away. Nil for a card with nothing typed on the front (handwriting
    /// only), which Anki can't take.
    static func ankiSides(_ card: Flashcard) -> (front: String, back: String)? {
        let front = card.frontText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !front.isEmpty else { return nil }
        let isCloze = containsCloze(front)
        let back = card.backText.isEmpty && isCloze ? clozeAnswer(front) : card.backText
        return (ankiField(isCloze ? clozePrompt(front) : front), ankiField(back))
    }

    // MARK: - Anki TSV (.txt) Export & Import

    static func exportAnkiTSV(deck: Deck, cards: [Flashcard]) throws -> URL {
        var lines: [String] = [
            "#separator:tab",
            "#html:true",
            "#deck:\(deck.name)",
            "#tags column:3"
        ]
        let tag = (deck.subject ?? "BelloBook").replacingOccurrences(of: " ", with: "_")
        for sides in cards.compactMap(ankiSides) {
            lines.append("\(sides.front)\t\(sides.back)\t\(tag)")
        }
        let content = lines.joined(separator: "\n")
        let safeName = deck.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName)-Anki.txt")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func parseAnkiTSV(_ raw: String) -> [(front: String, back: String)] {
        var results: [(front: String, back: String)] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let cols = trimmed.components(separatedBy: "\t")
            if cols.count >= 2 {
                let front = cols[0].replacingOccurrences(of: "<br>", with: "\n")
                let back = cols[1].replacingOccurrences(of: "<br>", with: "\n")
                if !front.isEmpty { results.append((front: front, back: back)) }
            } else if containsCloze(trimmed) {
                results.append((front: clozePrompt(trimmed), back: clozeAnswer(trimmed)))
            }
        }
        return results
    }

    // MARK: - AnkiConnect Desktop Sync

    /// Sends a deck to Anki on a computer through the AnkiConnect add-on.
    ///
    /// `endpoint` is that computer's address on your network (for example
    /// "http://192.168.1.20:8765"): on an iPad, 127.0.0.1 is the iPad itself. Returns how many
    /// cards Anki took, out of how many the deck has; cards already in Anki, or with only
    /// handwriting on the front, are left out.
    static func pushDeckToAnkiConnect(deck: Deck, cards: [Flashcard], endpoint: String) async throws -> (added: Int, total: Int) {
        var address = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.lowercased().hasPrefix("http") { address = "http://" + address }
        guard let url = URL(string: address), url.host != nil else { throw URLError(.badURL) }

        // 1. Ensure deck exists in Anki
        try await invokeAnkiConnect(url: url, action: "createDeck", params: ["deck": deck.name])

        // 2. Add the notes Anki will accept. addNotes can refuse the whole batch over one
        //    duplicate, so ask first which ones can be added.
        let tags = ["bellobook", (deck.subject ?? "notes").replacingOccurrences(of: " ", with: "_")]
        let notes: [[String: Any]] = cards.compactMap(ankiSides).map { sides in
            [
                "deckName": deck.name,
                "modelName": "Basic",
                "fields": ["Front": sides.front, "Back": sides.back],
                "options": ["allowDuplicate": false],
                "tags": tags
            ]
        }
        guard !notes.isEmpty else { return (0, cards.count) }
        let answer = try await invokeAnkiConnect(url: url, action: "canAddNotes", params: ["notes": notes])
        let allowed = answer as? [Bool] ?? []
        let fresh = notes.enumerated().filter { $0.offset < allowed.count && allowed[$0.offset] }.map { $0.element }
        if !fresh.isEmpty {
            try await invokeAnkiConnect(url: url, action: "addNotes", params: ["notes": fresh])
        }
        return (fresh.count, cards.count)
    }

    /// Calls AnkiConnect and returns its `result`, throwing the `error` it reports.
    @discardableResult
    private static func invokeAnkiConnect(url: URL, action: String, params: [String: Any]) async throws -> Any? {
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
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let err = json?["error"] as? String {
            throw NSError(domain: "AnkiConnect", code: 1, userInfo: [NSLocalizedDescriptionKey: err])
        }
        return json?["result"]
    }
}
