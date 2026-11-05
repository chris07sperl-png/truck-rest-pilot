import SwiftUI

struct ManufacturerListView: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var filter = ""
    @State private var refreshMessage: String?

    var body: some View {
        List {
            if filter.isEmpty {
                Section("Nach Produktart") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(catalog.categories) { c in
                                NavigationLink(value: Route.category(c.id)) {
                                    CategoryTile(category: c, count: catalog.seriesCount(inCategory: c.id))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }

            ForEach(catalog.groupedManufacturers) { group in
                let items = group.items.filter(matches)
                if !items.isEmpty {
                    Section(group.group) {
                        ForEach(items) { m in
                            NavigationLink(value: Route.manufacturer(m.id)) { ManufacturerRow(manufacturer: m) }
                        }
                    }
                }
            }

            Section {
                Text("\(catalog.catalog.manufacturers.count) Hersteller · \(catalog.totalSeries) Produktserien · Stand \(catalog.catalog.updated)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Die Anleitungen kommen direkt von den Herstellern. Zum Aktualisieren des Katalogs nach unten ziehen.")
            }
        }
        .navigationTitle("SHK Anleitungen")
        .searchable(text: $filter, prompt: "Hersteller filtern")
        .refreshable { refreshMessage = await catalog.refreshFromRemote() }
        .alert("Katalog", isPresented: Binding(get: { refreshMessage != nil }, set: { if !$0 { refreshMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(refreshMessage ?? "")
        }
    }

    private func matches(_ m: Manufacturer) -> Bool {
        filter.isEmpty || SearchIndex.compact(m.name).contains(SearchIndex.compact(filter))
    }
}

struct CategoryTile: View {
    let category: ProductCategory
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: category.symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text(category.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text("\(count) Serien").font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 120, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct CategoryView: View {
    @Environment(CatalogStore.self) private var catalog
    let categoryID: String
    @State private var filter = ""

    var body: some View {
        let all = catalog.series(inCategory: categoryID)
        let grouped = Dictionary(grouping: all.filter(matches), by: { $0.manufacturer.id })
        List {
            ForEach(catalog.manufacturers.filter { grouped[$0.id] != nil }) { m in
                Section(m.name) {
                    ForEach(grouped[m.id] ?? []) { item in
                        NavigationLink(value: Route.series(item.series.id)) {
                            SeriesRow(manufacturer: item.manufacturer, series: item.series)
                        }
                    }
                }
            }
        }
        .navigationTitle(catalog.category(categoryID)?.name ?? "Produktart")
        .searchable(text: $filter, prompt: "Serie oder Modell")
        .overlay {
            if grouped.isEmpty { ContentUnavailableView.search(text: filter) }
        }
    }

    private func matches(_ item: SeriesRef) -> Bool {
        guard !filter.isEmpty else { return true }
        let q = SearchIndex.compact(filter)
        let hay = SearchIndex.compact(([item.manufacturer.name, item.series.name] + item.series.models + item.series.keywords).joined(separator: " "))
        return hay.contains(q)
    }
}
