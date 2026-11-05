import SwiftUI
import UniformTypeIdentifiers

struct SeriesDetailView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    @Environment(InstallationStore.self) private var installations
    let seriesID: String

    @State private var selectedModel: String?
    @State private var browser: BrowserLink?
    @State private var showImporter = false
    @State private var importType: DocType = .bedienung
    @State private var errorMessage: String?
    @State private var found: [DocumentHit] = []
    @State private var isSearching = false

    var body: some View {
        if let item = catalog.series(seriesID) {
            content(item.manufacturer, item.series)
        } else {
            ContentUnavailableView("Produkt nicht gefunden", systemImage: "questionmark.folder")
        }
    }

    private func content(_ m: Manufacturer, _ s: ProductSeries) -> some View {
        List {
            headerSection(m, s)
            modelsSection(s)
            manualsSection(m, s)
            offlineSection(s)
            installedSection(s)
            docTypeSection(m, s)
            moreSection(m, s)
        }
        .navigationTitle(s.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    library.toggleFavorite(series: s.id)
                } label: {
                    Image(systemName: library.isFavorite(series: s.id) ? "star.fill" : "star")
                }
                .accessibilityLabel("Favorit")
            }
        }
        .onAppear { library.noteViewed(series: s.id) }
        .task(id: "\(s.id)|\(selectedModel ?? "")") { await searchManuals(m, s) }
        .sheet(item: $browser) { link in WebBrowserView(link: link) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            importFiles(result, m, s)
        }
        .alert("Fehler", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Abschnitte

    private func headerSection(_ m: Manufacturer, _ s: ProductSeries) -> some View {
        Section {
            HStack(spacing: 14) {
                ManufacturerBadge(manufacturer: m, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(.subheadline).foregroundStyle(.secondary)
                    Text(s.name).font(.title3.weight(.semibold))
                    if let cat = catalog.category(s.category) {
                        Label(cat.name, systemImage: cat.symbol).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func modelsSection(_ s: ProductSeries) -> some View {
        if !s.models.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        modelChip("Alle Modelle", selected: selectedModel == nil) { selectedModel = nil }
                        ForEach(s.models, id: \.self) { model in
                            modelChip(model, selected: selectedModel == model) {
                                selectedModel = selectedModel == model ? nil : model
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Typ / Modell")
            } footer: {
                Text("Typ vom Typenschild wählen, dann wird gezielt nach diesem Gerät gesucht.")
            }
        }
    }

    /// Anleitungen direkt sichtbar: bekannte Dokumente aus dem Katalog plus automatisch gefundene PDFs.
    private func manualsSection(_ m: Manufacturer, _ s: ProductSeries) -> some View {
        let known = s.documents
        let extra = Array(found.filter { hit in !known.contains { $0.url == hit.url } }.prefix(6))
        return Section {
            ForEach(known) { d in
                NavigationLink(value: Route.remotePDF(RemoteDoc(url: d.url, title: d.title, manufacturerID: m.id,
                                                                seriesID: s.id, docType: d.type))) {
                    DocumentHitRow(title: d.title, host: d.url.host() ?? "", isOfficial: isOfficial(d.url, m))
                }
            }
            if isSearching && extra.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Suche Anleitungen …").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(extra) { hit in
                NavigationLink(value: Route.remotePDF(RemoteDoc(url: hit.url, title: hit.title, manufacturerID: m.id,
                                                                seriesID: s.id, docType: .sonstiges))) {
                    DocumentHitRow(title: hit.title, host: hit.host, isOfficial: hit.isOfficial)
                }
            }
            if !isSearching && known.isEmpty && extra.isEmpty {
                Text("Keine PDFs automatisch gefunden – unten nach Dokumentart suchen.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            NavigationLink(value: Route.documentSearch(manufacturerID: m.id, seriesID: s.id, model: selectedModel, docType: nil)) {
                Label("Alle gefundenen Anleitungen", systemImage: "list.bullet.rectangle")
            }
        } header: {
            Text(selectedModel.map { "Anleitungen für \($0)" } ?? "Anleitungen")
        } footer: {
            Text("Antippen öffnet das PDF direkt in der App. Mit „Offline speichern“ ist es auch ohne Netz im Keller da.")
        }
    }

    @ViewBuilder
    private func offlineSection(_ s: ProductSeries) -> some View {
        let offline = library.documents(forSeries: s.id)
        if !offline.isEmpty {
            Section("Offline gespeichert") {
                ForEach(offline) { doc in
                    NavigationLink(value: Route.document(doc.id, page: nil, highlight: nil)) { DocumentRow(document: doc) }
                }
                .onDelete { idx in idx.map { offline[$0] }.forEach(library.delete) }
            }
        }
    }

    @ViewBuilder
    private func installedSection(_ s: ProductSeries) -> some View {
        let installed = installations.installations(withSeries: s.id)
        if !installed.isEmpty {
            Section("In deinen Anlagen") {
                ForEach(installed) { inst in
                    NavigationLink(value: Route.installation(inst.id)) { InstallationRow(installation: inst) }
                }
            }
        }
    }

    private func docTypeSection(_ m: Manufacturer, _ s: ProductSeries) -> some View {
        Section("Nach Dokumentart") {
            ForEach([DocType.bedienung, .montage, .service, .datenblatt, .ersatzteile, .planung]) { type in
                NavigationLink(value: Route.documentSearch(manufacturerID: m.id, seriesID: s.id,
                                                           model: selectedModel, docType: type)) {
                    Label(type.rawValue, systemImage: type.symbol)
                }
            }
        }
    }

    private func moreSection(_ m: Manufacturer, _ s: ProductSeries) -> some View {
        Section {
            Button {
                let q = DocSearch.query(manufacturer: m, series: s, model: selectedModel, type: nil) + " Anleitung"
                browser = BrowserLink(url: DocSearch.webURL(query: q), title: "Websuche",
                                      manufacturerID: m.id, seriesID: s.id)
            } label: {
                Label("Im Browser suchen", systemImage: "globe")
            }
            if let portal = m.docPortal {
                Button {
                    browser = BrowserLink(url: portal, title: "\(m.name) Dokumente", manufacturerID: m.id, seriesID: s.id)
                } label: {
                    Label("Offizielles Dokumenten-Portal", systemImage: "books.vertical")
                }
            }
            Menu {
                ForEach(DocType.allCases) { type in
                    Button(type.rawValue) { importType = type; showImporter = true }
                }
            } label: {
                Label("PDF aus „Dateien“ hinzufügen", systemImage: "folder.badge.plus")
            }
        }
    }

    // MARK: Aktionen

    private func searchManuals(_ m: Manufacturer, _ s: ProductSeries) async {
        isSearching = true
        found = await DocumentFinder.shared.find(
            DocumentQuery.simple(manufacturer: m, series: s, model: selectedModel, type: nil),
            officialDomains: m.searchDomains)
        isSearching = false
    }

    private func importFiles(_ result: Result<[URL], Error>, _ m: Manufacturer, _ s: ProductSeries) {
        switch result {
        case .success(let urls):
            for url in urls {
                do {
                    let title = urls.count == 1 ? "\(s.name) – \(importType.rawValue)" : url.deletingPathExtension().lastPathComponent
                    try library.importPDF(from: url, title: title, docType: importType, manufacturerID: m.id, seriesID: s.id)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func isOfficial(_ url: URL, _ m: Manufacturer) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return m.searchDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private func modelChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
