import SwiftUI

struct FavoritesView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let manufacturers = library.favoriteManufacturers.compactMap { catalog.manufacturer($0) }
        let series = library.favoriteSeries.compactMap { catalog.series($0) }
        let recent = library.recentSeries.compactMap { catalog.series($0) }

        List {
            if !manufacturers.isEmpty {
                Section("Hersteller") {
                    ForEach(manufacturers) { m in
                        NavigationLink(value: Route.manufacturer(m.id)) { ManufacturerRow(manufacturer: m) }
                    }
                    .onDelete { idx in idx.map { manufacturers[$0].id }.forEach(library.toggleFavorite(manufacturer:)) }
                }
            }
            if !series.isEmpty {
                Section("Produkte") {
                    ForEach(series) { item in
                        NavigationLink(value: Route.series(item.series.id)) {
                            SeriesRow(manufacturer: item.manufacturer, series: item.series, showManufacturer: true)
                        }
                    }
                    .onDelete { idx in idx.map { series[$0].series.id }.forEach(library.toggleFavorite(series:)) }
                }
            }
            if !recent.isEmpty {
                Section("Zuletzt angesehen") {
                    ForEach(recent) { item in
                        NavigationLink(value: Route.series(item.series.id)) {
                            SeriesRow(manufacturer: item.manufacturer, series: item.series, showManufacturer: true)
                        }
                    }
                }
            }
        }
        .navigationTitle("Favoriten")
        .overlay {
            if manufacturers.isEmpty && series.isEmpty && recent.isEmpty {
                ContentUnavailableView("Noch keine Favoriten", systemImage: "star",
                                       description: Text("Tippe bei Herstellern oder Geräten auf den Stern, die du oft brauchst."))
            }
        }
    }
}
