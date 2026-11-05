import Foundation

/// Fehlertolerante Suche über Hersteller, Serien, Modelle, Produktarten und Synonyme.
///
/// - Umlaute werden vereinheitlicht ("Wärmepumpe" = "waermepumpe" = "warmepumpe").
/// - Leerzeichen, Bindestriche und Schrägstriche zählen nicht ("vitodens200w" findet "Vitodens 200-W").
/// - Kleine Tippfehler werden toleriert ("Vitodnes" findet "Vitodens").
/// - Alle Suchwörter müssen passen, die Reihenfolge ist egal ("200 viessmann gas").
struct SearchIndex {
    enum Kind { case manufacturer, series }

    struct Entry {
        let kind: Kind
        let id: String
        let manufacturerID: String
        let category: String?
        let title: String
        let titleWords: [String]
        let words: [String]
        /// Begriffe der Produktart (z. B. Synonyme) – zählen nur halb.
        let weakWords: [String]
        let compact: String
        let models: [String]
        /// Erstes Wort des Herstellernamens, kompakt (z. B. "viessmann", "bosch").
        let manufacturerKey: String
    }

    struct Result: Identifiable {
        let entry: Entry
        let score: Int
        let matchedModel: String?
        var id: String { entry.id }
    }

    private let entries: [Entry]

    init(catalog: Catalog) {
        let categories = Dictionary(uniqueKeysWithValues: catalog.categories.map { ($0.id, $0) })
        var entries: [Entry] = []
        for m in catalog.manufacturers {
            let mText = [m.name, m.group, m.info].joined(separator: " ")
            entries.append(Entry(
                kind: .manufacturer, id: m.id, manufacturerID: m.id, category: nil,
                title: m.name, titleWords: Self.words(m.name),
                words: Self.words(mText), weakWords: [], compact: Self.compact(m.name), models: [],
                manufacturerKey: Self.words(m.name).first ?? ""
            ))
            for s in m.series {
                let cat = categories[s.category]
                let text = ([m.name, s.name] + s.models + s.keywords).joined(separator: " ")
                let weak = ([cat?.name ?? ""] + (cat?.synonyms ?? [])).joined(separator: " ")
                entries.append(Entry(
                    kind: .series, id: s.id, manufacturerID: m.id, category: s.category,
                    title: s.name, titleWords: Self.words(s.name),
                    words: Self.words(text), weakWords: Self.words(weak),
                    compact: Self.compact(([m.name, s.name] + s.models).joined(separator: " ")),
                    models: s.models,
                    manufacturerKey: Self.words(m.name).first ?? ""
                ))
            }
        }
        self.entries = entries
    }

    func search(_ query: String, category: String? = nil, limit: Int = 80) -> [Result] {
        let tokens = Self.words(query)
        guard !tokens.isEmpty else { return [] }
        let compactQuery = tokens.joined()

        var results: [Result] = []
        for entry in entries {
            if let category, entry.category != category { continue }
            var total = 0
            var allMatched = true
            for token in tokens {
                let s = Self.score(token: token, entry: entry)
                if s == 0 { allMatched = false; break }
                total += s
            }
            // Zusammengeschriebene Eingabe wie "vitodens200w" oder "cgb2k" erlauben.
            if !allMatched {
                guard compactQuery.count >= 3, entry.compact.contains(compactQuery) else { continue }
                total = 8
            }
            let compactTitle = Self.compact(entry.title)
            if compactTitle == compactQuery { total += 30 }
            else if compactTitle.hasPrefix(compactQuery) { total += 15 }
            if entry.kind == .manufacturer, total >= 10 { total += 5 }

            let model = entry.models.first { model in
                let c = Self.compact(model)
                return c.contains(compactQuery) || tokens.contains { $0.count >= 2 && $0.contains(where: \.isNumber) && c.contains($0) }
            }
            if model != nil { total += 6 }
            results.append(Result(entry: entry, score: total, matchedModel: model))
        }
        return results
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.entry.title < $1.entry.title }
            .prefix(limit)
            .map { $0 }
    }

    /// Erkennt Geräte aus dem Text eines Typenschilds (OCR). Anders als die normale Suche
    /// müssen nicht alle Wörter passen: Typenschilder enthalten viel anderen Text.
    func identify(text: String, limit: Int = 6) -> [Result] {
        let textWords = Set(Self.words(text))
        let textCompact = Self.compact(text)
        guard textCompact.count >= 3 else { return [] }

        var results: [Result] = []
        for entry in entries where entry.kind == .series {
            var score = 0
            var bestModel: String?
            var bestModelLength = 0
            for model in entry.models {
                let c = Self.compact(model)
                guard c.count >= 3, textCompact.contains(c) else { continue }
                if c.count > bestModelLength { bestModel = model; bestModelLength = c.count }
            }
            if bestModel != nil { score += 20 + bestModelLength }

            var titleHits = 0
            for word in Set(entry.titleWords) where word.count >= 3 && textWords.contains(word) {
                titleHits += 1
                score += word.allSatisfy(\.isNumber) ? 3 : 8
            }
            guard bestModel != nil || titleHits > 0 else { continue }

            let hasManufacturer = entry.manufacturerKey.count >= 3 && textCompact.contains(entry.manufacturerKey)
            if hasManufacturer { score += 15 }
            // Nur eine Zahl ohne Hersteller oder Modell ist zu unsicher.
            guard score >= 14 else { continue }
            results.append(Result(entry: entry, score: score, matchedModel: bestModel))
        }
        return results
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.entry.title < $1.entry.title }
            .prefix(limit)
            .map { $0 }
    }

    /// Hersteller, deren Name im Text vorkommt.
    func manufacturers(in text: String) -> [String] {
        let textCompact = Self.compact(text)
        return entries
            .filter { $0.kind == .manufacturer && $0.manufacturerKey.count >= 3 && textCompact.contains($0.manufacturerKey) }
            .map(\.id)
    }

    private static func score(token: String, entry: Entry) -> Int {
        var best = 0
        for word in entry.words {
            best = max(best, wordScore(token: token, word: word) * (entry.titleWords.contains(word) ? 2 : 1))
            if best >= 20 { return best }
        }
        for word in entry.weakWords {
            best = max(best, wordScore(token: token, word: word) / 2)
        }
        if best == 0, token.count >= 2, entry.compact.contains(token) { best = 2 }
        return best
    }

    private static func wordScore(token: String, word: String) -> Int {
        if word == token { return 10 }
        if word.hasPrefix(token) { return 6 }
        if token.count >= 3, word.contains(token) { return 3 }
        // Tippfehler nur bei Wörtern, nicht bei Typcodes wie "B2HF" oder "RC310".
        if token.count >= 4, !token.contains(where: \.isNumber), abs(word.count - token.count) <= 2,
           levenshtein(word, token) <= (token.count >= 7 ? 2 : 1) {
            return 2
        }
        return 0
    }

    // MARK: Normalisierung

    static func normalize(_ s: String) -> String {
        var t = s.lowercased()
        for (a, b) in [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t.folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
    }

    static func words(_ s: String) -> [String] {
        normalize(s)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    static func compact(_ s: String) -> String { words(s).joined() }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
