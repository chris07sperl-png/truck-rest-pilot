import SwiftUI
import UniformTypeIdentifiers

struct SeriesDetailView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    let seriesID: String

    @State private var selectedModel: String?
    @State private var browser: BrowserLink?
    @State private var showImporter = false
    @State private var importType: DocType = .bedienung
    @State private var errorMessage: String?

    var body: some View {
        if let item = catalog.series(seriesID) {
            content(item.manufacturer, item.series)
        } else {
            ContentUnavailableView("Produkt nicht gefunden", systemImage: "questionmark.folder")
        }
    }

    private func content(_ m: Manufacturer, _ s: ProductSeries) -> some View {
        let offline = library.documents(forSeries: s.id)
        return List {
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

            if !offline.isEmpty {
                Section("Offline gespeichert") {
                    ForEach(offline) { doc in
                        NavigationLink(value: Route.document(doc.id, page: nil, highlight: nil)) { DocumentRow(document: doc) }
                    }
                    .onDelete { idx in idx.map { offline[$0] }.forEach(library.delete) }
                }
            }

            if !s.documents.isEmpty {
                Section("Direkte Dokumente") {
                    ForEach(s.documents) { doc in
                        Button {
                            browser = BrowserLink(url: doc.url, title: doc.title, manufacturerID: m.id, seriesID: s.id, docType: doc.type)
                        } label: {
                            Label(doc.title, systemImage: doc.type.symbol)
                        }
                    }
                }
            }

            Section {
                ForEach([DocType.bedienung, .montage, .service, .datenblatt, .ersatzteile, .planung]) { type in
                    Button {
                        let q = DocSearch.query(manufacturer: m, series: s, model: selectedModel, type: type)
                        browser = BrowserLink(url: DocSearch.webURL(query: q, domains: m.searchDomains),
                                              title: type.rawValue, manufacturerID: m.id, seriesID: s.id, docType: type)
                    } label: {
                        HStack {
                            Label(type.rawValue, systemImage: type.symbol)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                }
            } header: {
                Text(selectedModel.map { "Anleitung finden für \($0)" } ?? "Anleitung finden")
            } footer: {
                Text("Sucht PDFs auf den Seiten von \(m.name). PDF öffnen und mit „Offline speichern“ aufs iPhone laden – dann geht es auch ohne Netz im Keller.")
            }

            Section {
                Button {
                    let q = DocSearch.query(manufacturer: m, series: s, model: selectedModel, type: nil) + " Anleitung"
                    browser = BrowserLink(url: DocSearch.webURL(query: q), title: "Websuche",
                                          manufacturerID: m.id, seriesID: s.id)
                } label: {
                    Label("Im ganzen Internet suchen", systemImage: "globe")
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
        .sheet(item: $browser) { link in WebBrowserView(link: link) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    do {
                        let title = "\(s.name) – \(importType.rawValue)"
                        try library.importPDF(from: url, title: urls.count == 1 ? title : url.deletingPathExtension().lastPathComponent,
                                              docType: importType, manufacturerID: m.id, seriesID: s.id)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("Fehler", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
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
