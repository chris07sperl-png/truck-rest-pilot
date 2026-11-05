import Foundation
import SwiftUI

// MARK: - Katalog-Datenmodell (entspricht Resources/catalog.json)

struct Catalog: Codable {
    var version: Int
    var updated: String
    var categories: [ProductCategory]
    var manufacturers: [Manufacturer]
}

struct ProductCategory: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var synonyms: [String]
}

struct Manufacturer: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var group: String
    var info: String
    var website: URL
    var docPortal: URL?
    var docPortalNote: String?
    var searchDomains: [String]
    var color: String
    var series: [ProductSeries]

    var tint: Color { Color(hex: color) }
    var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }
}

struct ProductSeries: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var category: String
    var models: [String]
    var keywords: [String]
    var documents: [CatalogDocument]
}

/// Direkt-Link auf ein bekanntes Dokument (optional im Katalog hinterlegt).
struct CatalogDocument: Codable, Identifiable, Hashable {
    var title: String
    var type: DocType
    var url: URL
    var id: URL { url }
}

enum DocType: String, Codable, CaseIterable, Identifiable {
    case bedienung = "Bedienungsanleitung"
    case montage = "Montageanleitung"
    case service = "Serviceanleitung"
    case planung = "Planungsanleitung"
    case datenblatt = "Datenblatt"
    case ersatzteile = "Ersatzteilliste"
    case sonstiges = "Sonstiges"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .bedienung: "book"
        case .montage: "wrench.and.screwdriver"
        case .service: "stethoscope"
        case .planung: "ruler"
        case .datenblatt: "doc.text"
        case .ersatzteile: "shippingbox"
        case .sonstiges: "doc"
        }
    }

    /// Suchbegriffe, mit denen Hersteller diese Dokumentart üblicherweise benennen.
    var searchTerms: String {
        switch self {
        case .bedienung: "(Bedienungsanleitung OR Betriebsanleitung)"
        case .montage: "(Montageanleitung OR Installationsanleitung OR \"Montage- und Serviceanleitung\")"
        case .service: "(Serviceanleitung OR Wartungsanleitung OR Störungsbehebung)"
        case .planung: "(Planungsanleitung OR Planungsunterlage)"
        case .datenblatt: "(Datenblatt OR \"technische Daten\")"
        case .ersatzteile: "(Ersatzteilliste OR Ersatzteile)"
        case .sonstiges: "Anleitung"
        }
    }
}

struct ManufacturerGroup: Identifiable {
    let group: String
    let items: [Manufacturer]
    var id: String { group }
}

struct SeriesRef: Identifiable, Hashable {
    let manufacturer: Manufacturer
    let series: ProductSeries
    var id: String { series.id }
}

// MARK: - Store

@Observable
final class CatalogStore {
    /// Optional: Adresse einer aktuelleren catalog.json im Internet. Wenn erreichbar,
    /// wird sie beim Aktualisieren geladen und lokal zwischengespeichert.
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/chris07sperl-png/truck-rest-pilot/main/shk-anleitungen/SHKAnleitungen/Resources/catalog.json")

    private(set) var catalog: Catalog
    private(set) var searchIndex: SearchIndex
    private var manufacturersByID: [String: Manufacturer] = [:]
    private var seriesByID: [String: (Manufacturer, ProductSeries)] = [:]
    private var categoriesByID: [String: ProductCategory] = [:]

    init() {
        let catalog = Self.loadCached() ?? Self.loadBundled()
        self.catalog = catalog
        self.searchIndex = SearchIndex(catalog: catalog)
        rebuildLookups()
    }

    var manufacturers: [Manufacturer] {
        catalog.manufacturers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var groupedManufacturers: [ManufacturerGroup] {
        let order = ["Heiztechnik", "Wärmepumpen & Klima", "Holz & Pellets", "Pumpen & Armaturen", "Wasser & Druckhaltung", "Sanitär", "Installationssysteme", "Heizkörper & Lüftung"]
        let grouped = Dictionary(grouping: manufacturers, by: \.group)
        return grouped.keys
            .sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
            .map { ManufacturerGroup(group: $0, items: grouped[$0] ?? []) }
    }

    var categories: [ProductCategory] { catalog.categories }

    func manufacturer(_ id: String) -> Manufacturer? { manufacturersByID[id] }
    func series(_ id: String) -> SeriesRef? {
        seriesByID[id].map { SeriesRef(manufacturer: $0.0, series: $0.1) }
    }
    func category(_ id: String) -> ProductCategory? { categoriesByID[id] }

    /// Alle Serien einer Produktart über alle Hersteller.
    func series(inCategory id: String) -> [SeriesRef] {
        manufacturers.flatMap { m in m.series.filter { $0.category == id }.map { SeriesRef(manufacturer: m, series: $0) } }
    }

    func seriesCount(inCategory id: String) -> Int {
        catalog.manufacturers.reduce(0) { $0 + $1.series.filter { $0.category == id }.count }
    }

    var totalSeries: Int { catalog.manufacturers.reduce(0) { $0 + $1.series.count } }

    // MARK: Aktualisieren aus dem Internet

    @MainActor
    func refreshFromRemote() async -> String {
        guard let url = Self.remoteURL else { return "Keine Online-Quelle eingestellt." }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return "Online-Katalog nicht erreichbar."
            }
            let remote = try JSONDecoder().decode(Catalog.self, from: data)
            guard remote.version >= catalog.version, remote.updated >= catalog.updated else {
                return "Katalog ist bereits aktuell (Stand \(catalog.updated))."
            }
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try data.write(to: Self.cacheURL, options: .atomic)
            apply(remote)
            return "Katalog aktualisiert (Stand \(remote.updated))."
        } catch {
            return "Aktualisierung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func apply(_ catalog: Catalog) {
        self.catalog = catalog
        self.searchIndex = SearchIndex(catalog: catalog)
        rebuildLookups()
    }

    private func rebuildLookups() {
        manufacturersByID = Dictionary(uniqueKeysWithValues: catalog.manufacturers.map { ($0.id, $0) })
        categoriesByID = Dictionary(uniqueKeysWithValues: catalog.categories.map { ($0.id, $0) })
        var s: [String: (Manufacturer, ProductSeries)] = [:]
        for m in catalog.manufacturers { for item in m.series { s[item.id] = (m, item) } }
        seriesByID = s
    }

    private static var cacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "catalog-remote.json")
    }

    private static func loadCached() -> Catalog? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode(Catalog.self, from: data) else { return nil }
        let bundled = loadBundled()
        // Nach einem App-Update kann der mitgelieferte Katalog neuer sein.
        return cached.updated >= bundled.updated ? cached : nil
    }

    private static func loadBundled() -> Catalog {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else {
            assertionFailure("catalog.json fehlt oder ist fehlerhaft")
            return Catalog(version: 0, updated: "", categories: [], manufacturers: [])
        }
        return catalog
    }
}

// MARK: - Web-Suche nach Anleitungen

enum DocSearch {
    static func query(manufacturer: Manufacturer, series: ProductSeries?, model: String?, type: DocType?) -> String {
        var parts = [manufacturer.name.components(separatedBy: " (").first ?? manufacturer.name]
        if let model { parts.append("\"\(model)\"") }
        else if let series { parts.append(series.name.components(separatedBy: " / ").first ?? series.name) }
        if let type { parts.append(type.searchTerms) }
        return parts.joined(separator: " ")
    }

    /// Google-Suche nach PDF-Dokumenten, optional auf die Hersteller-Domains beschränkt.
    static func webURL(query: String, domains: [String] = [], pdfOnly: Bool = true) -> URL {
        var q = query
        if !domains.isEmpty {
            q += " (" + domains.map { "site:\($0)" }.joined(separator: " OR ") + ")"
        }
        if pdfOnly { q += " filetype:pdf" }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "hl", value: "de")]
        return components.url!
    }
}

// MARK: - Hilfen

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
