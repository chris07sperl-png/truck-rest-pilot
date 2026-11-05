import SwiftUI

struct SearchView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    @State private var query = ""
    @State private var category: String?
    @State private var textHits: [TextHit] = []
    @State private var browser: BrowserLink?
    @State private var showScanner = false
    @State private var scannedSeries: String?

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        let results = catalog.searchIndex.search(trimmed, category: category)
        let manufacturerHits = results.filter { $0.entry.kind == .manufacturer }
        let seriesHits = results.filter { $0.entry.kind == .series }
        let docHits = matchingDocuments

        List {
            Section {
                CategoryChips(selection: $category)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            if trimmed.isEmpty {
                emptyState
            } else {
                if !manufacturerHits.isEmpty {
                    Section("Hersteller") {
                        ForEach(manufacturerHits) { r in
                            if let m = catalog.manufacturer(r.entry.id) {
                                NavigationLink(value: Route.manufacturer(m.id)) { ManufacturerRow(manufacturer: m) }
                            }
                        }
                    }
                }
                if !seriesHits.isEmpty {
                    Section("Produkte (\(seriesHits.count))") {
                        ForEach(seriesHits) { r in
                            if let item = catalog.series(r.entry.id) {
                                NavigationLink(value: Route.series(item.series.id)) {
                                    SeriesRow(manufacturer: item.manufacturer, series: item.series,
                                              showManufacturer: true, matchedModel: r.matchedModel)
                                }
                            }
                        }
                    }
                }
                if !docHits.isEmpty {
                    Section("Offline-Dokumente") {
                        ForEach(docHits) { doc in
                            NavigationLink(value: Route.document(doc.id, page: nil, highlight: nil)) { DocumentRow(document: doc) }
                        }
                    }
                }
                if !textHits.isEmpty {
                    Section {
                        ForEach(textHits) { hit in
                            if let doc = library.document(hit.documentID) {
                                NavigationLink(value: Route.document(doc.id, page: hit.pageIndex, highlight: trimmed)) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(doc.title) · Seite \(hit.pageIndex + 1)")
                                            .font(.subheadline.weight(.medium))
                                            .lineLimit(1)
                                        highlighted(hit.snippet)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Im Text deiner PDFs")
                    } footer: {
                        Text("Ideal für Störcodes, Parameter und Fehlermeldungen.")
                    }
                }

                Section {
                    Button {
                        browser = BrowserLink(url: DocSearch.webURL(query: "\(trimmed) Anleitung"), title: "Websuche")
                    } label: {
                        Label("„\(trimmed)“ im Internet suchen (PDF)", systemImage: "globe")
                    }
                }
            }
        }
        .navigationTitle("Suche")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Gerät, Typ, Störcode …")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onSubmit(of: .search) { library.noteSearch(trimmed) }
        .task(id: trimmed) {
            // Kurz warten, damit beim Tippen nicht jede Taste eine Volltextsuche startet.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            textHits = await library.fullTextSearch(trimmed)
        }
        .overlay {
            if !trimmed.isEmpty && results.isEmpty && docHits.isEmpty && textHits.isEmpty {
                ContentUnavailableView {
                    Label("Nichts gefunden", systemImage: "magnifyingglass")
                } description: {
                    Text("Anderen Begriff versuchen oder direkt im Internet suchen.")
                } actions: {
                    Button("Im Internet suchen") {
                        browser = BrowserLink(url: DocSearch.webURL(query: "\(trimmed) Anleitung"), title: "Websuche")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(item: $browser) { link in WebBrowserView(link: link) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showScanner = true } label: {
                    Label("Typenschild scannen", systemImage: "text.viewfinder")
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            NameplateScannerView { scan in
                if let sid = scan.seriesID {
                    scannedSeries = sid
                } else if let mid = scan.manufacturerID, let m = catalog.manufacturer(mid) {
                    query = m.name
                } else {
                    // Längste Zeile mit Ziffern ist meist die Typbezeichnung.
                    query = scan.text.components(separatedBy: .newlines)
                        .filter { $0.contains(where: \.isNumber) }
                        .max { $0.count < $1.count } ?? ""
                }
            }
        }
        .navigationDestination(item: $scannedSeries) { sid in SeriesDetailView(seriesID: sid) }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !library.recentSearches.isEmpty {
            Section {
                ForEach(library.recentSearches, id: \.self) { s in
                    Button { query = s } label: {
                        Label(s, systemImage: "clock.arrow.circlepath")
                    }
                    .tint(.primary)
                }
            } header: {
                HStack {
                    Text("Letzte Suchen")
                    Spacer()
                    Button("Löschen") { library.clearRecentSearches() }.font(.caption)
                }
            }
        }
        let recent = library.recentSeries.compactMap { catalog.series($0) }.prefix(8)
        if !recent.isEmpty {
            Section("Zuletzt angesehen") {
                ForEach(Array(recent)) { item in
                    NavigationLink(value: Route.series(item.series.id)) {
                        SeriesRow(manufacturer: item.manufacturer, series: item.series, showManufacturer: true)
                    }
                }
            }
        }
        Section("Tipps") {
            Label("„vitodens 200“, „cgb2k“ oder „B2HF“ – Leerzeichen und Bindestriche sind egal.", systemImage: "lightbulb")
            Label("Nach Produktart suchen: „wärmepumpe wolf“, „therme“, „hebeanlage“.", systemImage: "square.grid.2x2")
            Label("Störcodes wie „F.28“ werden im Text deiner Offline-PDFs gefunden.", systemImage: "exclamationmark.triangle")
            Label("Oben rechts: Typenschild mit der Kamera scannen.", systemImage: "text.viewfinder")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var matchingDocuments: [LocalDocument] {
        let q = SearchIndex.words(trimmed)
        guard !q.isEmpty else { return [] }
        return library.documents.filter { doc in
            var text = doc.title + " " + doc.docType.rawValue
            if let id = doc.manufacturerID, let m = catalog.manufacturer(id) { text += " " + m.name }
            if let id = doc.seriesID, let s = catalog.series(id) { text += " " + s.series.name + " " + s.series.models.joined(separator: " ") }
            let hay = SearchIndex.compact(text)
            return q.allSatisfy { hay.contains($0) }
        }
    }

    private func highlighted(_ snippet: String) -> Text {
        var attributed = AttributedString(snippet)
        if let range = attributed.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[range].foregroundColor = .primary
            attributed[range].font = .caption.bold()
        }
        return Text(attributed)
    }
}
