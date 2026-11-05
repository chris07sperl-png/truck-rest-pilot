import SwiftUI
import CryptoKit
import PDFKit

/// Verweis auf ein Online-PDF, das direkt in der App angezeigt wird.
struct RemoteDoc: Hashable {
    var url: URL
    var title: String
    var manufacturerID: String?
    var seriesID: String?
    var docType: DocType
}

// MARK: - Online-PDF anzeigen

/// Lädt ein PDF aus dem Internet, zeigt es sofort in der App und bietet „Offline speichern“ an.
struct RemotePDFView: View {
    @Environment(LibraryStore.self) private var library
    let doc: RemoteDoc

    @State private var state: LoadState = .loading
    @State private var browser: BrowserLink?
    @State private var savedMessage: String?

    enum LoadState: Equatable {
        case loading
        case ready(URL)
        case failed(String)
    }

    var body: some View {
        content
            .navigationTitle(doc.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let saved = library.document(withSource: doc.url) {
                        NavigationLink(value: Route.document(saved.id, page: nil, highlight: nil)) {
                            Label("Offline gespeichert", systemImage: "checkmark.circle.fill")
                        }
                    } else if let file = readyFile {
                        Button { save(file) } label: {
                            Label("Offline speichern", systemImage: "arrow.down.circle")
                        }
                    }
                }
            }
            .task(id: doc.url) { await load() }
            .sheet(item: $browser) { link in WebBrowserView(link: link) }
            .overlay(alignment: .bottom) {
                if let savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 60)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }

    private var readyFile: URL? {
        if case .ready(let file) = state { return file }
        return nil
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Anleitung wird geladen …").foregroundStyle(.secondary)
                Text(doc.url.host() ?? "").font(.caption).foregroundStyle(.tertiary)
            }
        case .ready(let file):
            PDFReaderCore(fileURL: file, title: doc.title)
        case .failed(let message):
            ContentUnavailableView {
                Label("PDF nicht verfügbar", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Erneut versuchen") { Task { await load() } }
                Button("Im Browser öffnen") {
                    browser = BrowserLink(url: doc.url, title: doc.title, manufacturerID: doc.manufacturerID,
                                          seriesID: doc.seriesID, docType: doc.docType)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func load() async {
        if let saved = library.document(withSource: doc.url) {
            state = .ready(library.fileURL(for: saved))
            return
        }
        state = .loading
        do {
            state = .ready(try await RemotePDFCache.shared.file(for: doc.url))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func save(_ file: URL) {
        do {
            try library.importPDF(from: file, title: doc.title, docType: doc.docType,
                                  manufacturerID: doc.manufacturerID, seriesID: doc.seriesID, sourceURL: doc.url)
            withAnimation { savedMessage = "Offline gespeichert" }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { savedMessage = nil }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// Zwischenspeicher für angesehene Online-PDFs (wird von iOS bei Platzmangel geleert).
actor RemotePDFCache {
    static let shared = RemotePDFCache()

    enum CacheError: LocalizedError {
        case notPDF, http(Int)
        var errorDescription: String? {
            switch self {
            case .notPDF: "Unter diesem Link liegt kein PDF (mehr). Eventuell ist eine Anmeldung nötig – dann im Browser öffnen."
            case .http(let code): "Der Server hat mit Fehler \(code) geantwortet."
            }
        }
    }

    private let dir: URL = {
        let d = URL.cachesDirectory.appending(path: "OnlinePDFs")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func file(for url: URL) async throws -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let target = dir.appending(path: "\(hash).pdf")
        if FileManager.default.fileExists(atPath: target.path) { return target }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        let (tmp, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CacheError.http(http.statusCode)
        }
        guard PDFDocument(url: tmp) != nil else { throw CacheError.notPDF }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: tmp, to: target)
        return target
    }
}

// MARK: - PDF-Suche in der App

/// Liste gefundener Anleitungen (PDF) für ein Gerät – Antippen öffnet das PDF direkt in der App.
struct DocumentSearchView: View {
    @Environment(CatalogStore.self) private var catalog
    let manufacturerID: String?
    let seriesID: String?
    let model: String?
    let docType: DocType?
    var freeQuery: String?

    @State private var hits: [DocumentHit] = []
    @State private var isLoading = true
    @State private var browser: BrowserLink?

    var body: some View {
        let m = manufacturerID.flatMap { catalog.manufacturer($0) }
        let s = seriesID.flatMap { catalog.series($0)?.series }
        List {
            if let m, let s {
                let known = s.documents.filter { docType == nil || $0.type == docType }
                if !known.isEmpty {
                    Section("Aus dem Katalog") {
                        ForEach(known) { d in
                            NavigationLink(value: Route.remotePDF(RemoteDoc(url: d.url, title: d.title, manufacturerID: m.id,
                                                                            seriesID: s.id, docType: d.type))) {
                                DocumentHitRow(title: d.title, host: d.url.host() ?? "", isOfficial: isOfficial(d.url, m))
                            }
                        }
                    }
                }
            }
            Section {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Suche Anleitungen im Internet …").foregroundStyle(.secondary)
                    }
                } else if hits.isEmpty {
                    Text("Keine PDFs gefunden. Versuch es im Browser oder ohne Modellangabe.")
                        .foregroundStyle(.secondary)
                }
                ForEach(hits) { hit in
                    NavigationLink(value: Route.remotePDF(RemoteDoc(url: hit.url, title: hit.title,
                                                                    manufacturerID: manufacturerID ?? guessedManufacturer,
                                                                    seriesID: seriesID, docType: docType ?? .sonstiges))) {
                        DocumentHitRow(title: hit.title, host: hit.host, isOfficial: hit.isOfficial, snippet: hit.snippet)
                    }
                }
            } header: {
                Text("Gefundene PDFs")
            } footer: {
                Text("Grün markiert: direkt vom Hersteller. Andere Quellen sind Kopien von Händlern – Ausgabedatum auf dem Deckblatt prüfen.")
            }
            if let freeQuery, m == nil {
                Section {
                    Button {
                        browser = BrowserLink(url: DocSearch.webURL(query: freeQuery + " Anleitung"), title: "Websuche")
                    } label: {
                        Label("Im Browser suchen", systemImage: "safari")
                    }
                }
            }
            if let m {
                Section {
                    Button {
                        browser = BrowserLink(url: DocSearch.webURL(query: query(m, s), domains: m.searchDomains),
                                              title: docType?.rawValue ?? "Anleitungen", manufacturerID: m.id,
                                              seriesID: seriesID, docType: docType ?? .bedienung)
                    } label: {
                        Label("Im Browser suchen", systemImage: "safari")
                    }
                    if let portal = m.docPortal {
                        Button {
                            browser = BrowserLink(url: portal, title: "\(m.name) Dokumente", manufacturerID: m.id,
                                                  seriesID: seriesID, docType: docType ?? .bedienung)
                        } label: {
                            Label("Offizielles Dokumenten-Portal", systemImage: "books.vertical")
                        }
                    }
                }
            }
        }
        .navigationTitle(freeQuery.map { "„\($0)“" } ?? docType?.rawValue ?? "Anleitungen")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await search(force: true) }
        .task { await search(force: false) }
        .sheet(item: $browser) { link in WebBrowserView(link: link) }
    }

    private var guessedManufacturer: String? {
        freeQuery.flatMap { catalog.searchIndex.manufacturers(in: $0).first }
    }

    private func query(_ m: Manufacturer, _ s: ProductSeries?) -> String {
        DocumentQuery.simple(manufacturer: m, series: s, model: model, type: docType)
    }

    private func search(force: Bool) async {
        if !force && !hits.isEmpty { return }
        let m = manufacturerID.flatMap { catalog.manufacturer($0) }
        let s = seriesID.flatMap { catalog.series($0)?.series }
        let q: String
        var domains: [String]
        if let freeQuery {
            q = freeQuery + " Anleitung"
            // Hersteller im Suchtext erkennen, damit deren PDFs oben stehen.
            domains = catalog.searchIndex.manufacturers(in: freeQuery)
                .compactMap { catalog.manufacturer($0) }.flatMap(\.searchDomains)
        } else if let m {
            q = query(m, s)
            domains = m.searchDomains
        } else {
            return
        }
        if let m { domains += m.searchDomains }
        isLoading = true
        hits = await DocumentFinder.shared.find(q, officialDomains: domains)
        isLoading = false
    }

    private func isOfficial(_ url: URL, _ m: Manufacturer) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return m.searchDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

struct DocumentHitRow: View {
    let title: String
    let host: String
    let isOfficial: Bool
    var snippet: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.richtext.fill")
                .font(.title2)
                .foregroundStyle(isOfficial ? .green : .red)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium)).lineLimit(3)
                HStack(spacing: 4) {
                    if isOfficial {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("Hersteller")
                    } else {
                        Text(host.replacingOccurrences(of: "www.", with: ""))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !snippet.isEmpty {
                    Text(snippet).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Einfache Suchanfragen für die App-interne Suche (ohne OR-Gruppen).
enum DocumentQuery {
    static func simple(manufacturer: Manufacturer, series: ProductSeries?, model: String?, type: DocType?) -> String {
        var parts = [manufacturer.name.components(separatedBy: CharacterSet(charactersIn: "/(")).first?
            .trimmingCharacters(in: .whitespaces) ?? manufacturer.name]
        if let model, !model.isEmpty {
            if let series { parts.append(series.name.components(separatedBy: " / ").first ?? series.name) }
            parts.append(model)
        } else if let series {
            parts.append(series.name.components(separatedBy: " / ").first ?? series.name)
        }
        parts.append(type?.simpleTerm ?? "Anleitung")
        return parts.joined(separator: " ")
    }
}

extension DocType {
    var simpleTerm: String {
        switch self {
        case .bedienung: "Bedienungsanleitung"
        case .montage: "Montageanleitung"
        case .service: "Serviceanleitung"
        case .planung: "Planungsanleitung"
        case .datenblatt: "Datenblatt"
        case .ersatzteile: "Ersatzteilliste"
        case .sonstiges: "Anleitung"
        }
    }
}
