import Foundation
import PDFKit

/// Ein auf dem iPhone gespeichertes PDF (offline verfügbar).
struct LocalDocument: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var fileName: String
    var docType: DocType
    var manufacturerID: String?
    var seriesID: String?
    var sourceURL: URL?
    var pageCount: Int
    var addedAt: Date
}

/// Treffer der Volltextsuche in gespeicherten PDFs (z. B. Störcode "F.28").
struct TextHit: Identifiable, Hashable {
    let documentID: UUID
    let pageIndex: Int
    let snippet: String
    var id: String { "\(documentID)-\(pageIndex)-\(snippet.hashValue)" }
}

enum LibraryError: LocalizedError {
    case notAPDF
    var errorDescription: String? {
        switch self {
        case .notAPDF: "Die Datei ist kein gültiges PDF. Öffne zuerst die PDF-Datei selbst und speichere dann."
        }
    }
}

@Observable
final class LibraryStore {
    private(set) var documents: [LocalDocument] = []
    private(set) var favoriteSeries: [String] = []
    private(set) var favoriteManufacturers: [String] = []
    private(set) var recentSeries: [String] = []
    private(set) var recentSearches: [String] = []
    private(set) var indexingCount = 0

    /// Seitentexte je Dokument für die Volltextsuche.
    @ObservationIgnored private var pageTexts: [UUID: [String]] = [:]
    @ObservationIgnored private let fm = FileManager.default
    @ObservationIgnored private let defaults = UserDefaults.standard

    private let baseDir: URL
    private var filesDir: URL { baseDir.appending(path: "PDFs") }
    private var textDir: URL { baseDir.appending(path: "Text") }
    private var metadataURL: URL { baseDir.appending(path: "library.json") }

    init() {
        baseDir = URL.documentsDirectory.appending(path: "Anleitungen")
        try? fm.createDirectory(at: filesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: textDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: metadataURL),
           let docs = try? JSONDecoder().decode([LocalDocument].self, from: data) {
            documents = docs
        }
        favoriteSeries = defaults.stringArray(forKey: "favoriteSeries") ?? []
        favoriteManufacturers = defaults.stringArray(forKey: "favoriteManufacturers") ?? []
        recentSeries = defaults.stringArray(forKey: "recentSeries") ?? []
        recentSearches = defaults.stringArray(forKey: "recentSearches") ?? []
        loadTextIndex()
    }

    // MARK: Dokumente

    func fileURL(for doc: LocalDocument) -> URL { filesDir.appending(path: doc.fileName) }

    func documents(forSeries id: String) -> [LocalDocument] {
        documents.filter { $0.seriesID == id }.sorted { $0.title < $1.title }
    }

    func documents(forManufacturer id: String) -> [LocalDocument] {
        documents.filter { $0.manufacturerID == id }
    }

    func document(_ id: UUID) -> LocalDocument? { documents.first { $0.id == id } }

    /// Bereits offline gespeichertes Dokument zu einer Online-Adresse.
    func document(withSource url: URL) -> LocalDocument? { documents.first { $0.sourceURL == url } }

    /// Kopiert ein PDF (aus "Dateien" oder einem Download) in die Bibliothek.
    @discardableResult
    func importPDF(from source: URL, title: String, docType: DocType,
                   manufacturerID: String?, seriesID: String?, sourceURL: URL? = nil) throws -> LocalDocument {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        guard let pdf = PDFDocument(url: source) else { throw LibraryError.notAPDF }
        let id = UUID()
        let fileName = "\(id.uuidString).pdf"
        try fm.copyItem(at: source, to: filesDir.appending(path: fileName))

        let doc = LocalDocument(
            id: id, title: title.isEmpty ? source.deletingPathExtension().lastPathComponent : title,
            fileName: fileName, docType: docType, manufacturerID: manufacturerID, seriesID: seriesID,
            sourceURL: sourceURL, pageCount: pdf.pageCount, addedAt: .now
        )
        documents.append(doc)
        saveMetadata()
        indexText(of: doc)
        return doc
    }

    /// Lädt ein PDF aus dem Internet herunter und speichert es offline.
    @MainActor
    func download(from url: URL, title: String, docType: DocType,
                  manufacturerID: String?, seriesID: String?, cookies: [HTTPCookie] = []) async throws -> LocalDocument {
        var request = URLRequest(url: url)
        // Anmeldung aus dem App-Browser mitgeben (Fachpartner-Portale).
        let matching = cookies.filter { cookie in
            guard let host = url.host() else { return false }
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == domain || host.hasSuffix("." + domain)
        }
        for (key, value) in HTTPCookie.requestHeaderFields(with: matching) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (tmp, _) = try await URLSession.shared.download(for: request)
        let named = fm.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        try fm.moveItem(at: tmp, to: named)
        defer { try? fm.removeItem(at: named) }
        return try importPDF(from: named, title: title, docType: docType,
                             manufacturerID: manufacturerID, seriesID: seriesID, sourceURL: url)
    }

    func update(_ doc: LocalDocument) {
        guard let i = documents.firstIndex(where: { $0.id == doc.id }) else { return }
        documents[i] = doc
        saveMetadata()
    }

    func delete(_ doc: LocalDocument) {
        try? fm.removeItem(at: fileURL(for: doc))
        try? fm.removeItem(at: textDir.appending(path: "\(doc.id.uuidString).json"))
        pageTexts[doc.id] = nil
        documents.removeAll { $0.id == doc.id }
        saveMetadata()
    }

    var totalSizeText: String {
        let bytes = documents.reduce(Int64(0)) { sum, doc in
            let attributes = try? fm.attributesOfItem(atPath: fileURL(for: doc).path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            return sum + size
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func saveMetadata() {
        if let data = try? JSONEncoder().encode(documents) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }

    // MARK: Volltext

    private func loadTextIndex() {
        for doc in documents {
            let url = textDir.appending(path: "\(doc.id.uuidString).json")
            if let data = try? Data(contentsOf: url), let pages = try? JSONDecoder().decode([String].self, from: data) {
                pageTexts[doc.id] = pages
            } else {
                indexText(of: doc)
            }
        }
    }

    private func indexText(of doc: LocalDocument) {
        let fileURL = fileURL(for: doc)
        let textURL = textDir.appending(path: "\(doc.id.uuidString).json")
        let id = doc.id
        indexingCount += 1
        Task { @MainActor [weak self] in
            let pages = await Task.detached(priority: .utility) { () -> [String] in
                var pages: [String] = []
                if let pdf = PDFDocument(url: fileURL) {
                    for i in 0..<pdf.pageCount { pages.append(pdf.page(at: i)?.string ?? "") }
                }
                if let data = try? JSONEncoder().encode(pages) { try? data.write(to: textURL, options: .atomic) }
                return pages
            }.value
            guard let self else { return }
            indexingCount -= 1
            if document(id) != nil { pageTexts[id] = pages }
        }
    }

    /// Durchsucht den Text aller gespeicherten PDFs.
    func fullTextSearch(_ query: String, limitPerDocument: Int = 5, limit: Int = 150) async -> [TextHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        let texts = pageTexts
        return await Task.detached(priority: .userInitiated) { () -> [TextHit] in
            var hits: [TextHit] = []
            for (docID, pages) in texts {
                var perDoc = 0
                for (index, text) in pages.enumerated() where perDoc < limitPerDocument {
                    guard let range = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                    let start = text.index(range.lowerBound, offsetBy: -70, limitedBy: text.startIndex) ?? text.startIndex
                    let end = text.index(range.upperBound, offsetBy: 90, limitedBy: text.endIndex) ?? text.endIndex
                    let snippet = text[start..<end]
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                    hits.append(TextHit(documentID: docID, pageIndex: index, snippet: snippet))
                    perDoc += 1
                    if hits.count >= limit { return hits }
                }
            }
            return hits
        }.value
    }

    // MARK: Favoriten & Verlauf

    func isFavorite(series id: String) -> Bool { favoriteSeries.contains(id) }
    func isFavorite(manufacturer id: String) -> Bool { favoriteManufacturers.contains(id) }

    func toggleFavorite(series id: String) {
        if let i = favoriteSeries.firstIndex(of: id) { favoriteSeries.remove(at: i) } else { favoriteSeries.insert(id, at: 0) }
        defaults.set(favoriteSeries, forKey: "favoriteSeries")
    }

    func toggleFavorite(manufacturer id: String) {
        if let i = favoriteManufacturers.firstIndex(of: id) { favoriteManufacturers.remove(at: i) } else { favoriteManufacturers.insert(id, at: 0) }
        defaults.set(favoriteManufacturers, forKey: "favoriteManufacturers")
    }

    func noteViewed(series id: String) {
        recentSeries.removeAll { $0 == id }
        recentSeries.insert(id, at: 0)
        recentSeries = Array(recentSeries.prefix(15))
        defaults.set(recentSeries, forKey: "recentSeries")
    }

    func noteSearch(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(t) == .orderedSame }
        recentSearches.insert(t, at: 0)
        recentSearches = Array(recentSearches.prefix(10))
        defaults.set(recentSearches, forKey: "recentSearches")
    }

    func clearRecentSearches() {
        recentSearches = []
        defaults.removeObject(forKey: "recentSearches")
    }
}
