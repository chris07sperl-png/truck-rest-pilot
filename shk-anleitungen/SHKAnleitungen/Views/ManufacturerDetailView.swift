import SwiftUI

struct ManufacturerDetailView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    let manufacturerID: String
    @State private var filter = ""
    @State private var browser: BrowserLink?

    var body: some View {
        if let m = catalog.manufacturer(manufacturerID) {
            content(m)
        } else {
            ContentUnavailableView("Hersteller nicht gefunden", systemImage: "questionmark.folder")
        }
    }

    private func content(_ m: Manufacturer) -> some View {
        let series = m.series.filter { s in
            filter.isEmpty || SearchIndex.compact(([s.name] + s.models + s.keywords).joined(separator: " "))
                .contains(SearchIndex.compact(filter))
        }
        let byCategory = Dictionary(grouping: series, by: \.category)
        let categoryOrder = catalog.categories.map(\.id).filter { byCategory[$0] != nil }

        return List {
            if filter.isEmpty {
                Section {
                    HStack(spacing: 14) {
                        ManufacturerBadge(manufacturer: m, size: 56)
                        Text(m.info).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    if let portal = m.docPortal {
                        Button {
                            browser = BrowserLink(url: portal, title: "\(m.name) Dokumente", manufacturerID: m.id)
                        } label: {
                            Label("Offizielles Dokumenten-Portal", systemImage: "books.vertical")
                        }
                    }
                    NavigationLink(value: Route.documentSearch(manufacturerID: m.id, seriesID: nil, model: nil, docType: nil)) {
                        Label("Anleitungen von \(m.name) suchen", systemImage: "doc.text.magnifyingglass")
                    }
                    Link(destination: m.website) {
                        Label(m.website.host() ?? "Webseite", systemImage: "safari")
                    }
                } footer: {
                    if let note = m.docPortalNote { Text(note) }
                }

                let offline = library.documents(forManufacturer: m.id)
                if !offline.isEmpty {
                    Section("Offline gespeichert") {
                        ForEach(offline) { doc in
                            NavigationLink(value: Route.document(doc.id, page: nil, highlight: nil)) { DocumentRow(document: doc) }
                        }
                    }
                }
            }

            ForEach(categoryOrder, id: \.self) { catID in
                Section(catalog.category(catID)?.name ?? catID) {
                    ForEach(byCategory[catID] ?? []) { s in
                        NavigationLink(value: Route.series(s.id)) { SeriesRow(manufacturer: m, series: s) }
                    }
                }
            }
        }
        .navigationTitle(m.name)
        .searchable(text: $filter, prompt: "In \(m.name) suchen")
        .overlay {
            if series.isEmpty { ContentUnavailableView.search(text: filter) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    library.toggleFavorite(manufacturer: m.id)
                } label: {
                    Image(systemName: library.isFavorite(manufacturer: m.id) ? "star.fill" : "star")
                }
                .accessibilityLabel("Favorit")
            }
        }
        .sheet(item: $browser) { link in WebBrowserView(link: link) }
    }
}
