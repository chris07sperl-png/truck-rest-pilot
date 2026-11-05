import SwiftUI

@main
struct SHKAnleitungenApp: App {
    @State private var catalog = CatalogStore()
    @State private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(catalog)
                .environment(library)
        }
    }
}

/// Navigationsziele, die in jedem Tab gleich funktionieren.
enum Route: Hashable {
    case manufacturer(String)
    case series(String)
    case category(String)
    case document(UUID, page: Int?, highlight: String?)
}

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack { ManufacturerListView().withRoutes() }
                .tabItem { Label("Hersteller", systemImage: "building.2") }
            NavigationStack { SearchView().withRoutes() }
                .tabItem { Label("Suche", systemImage: "magnifyingglass") }
            NavigationStack { LibraryView().withRoutes() }
                .tabItem { Label("Offline", systemImage: "arrow.down.circle") }
            NavigationStack { FavoritesView().withRoutes() }
                .tabItem { Label("Favoriten", systemImage: "star") }
        }
    }
}

extension View {
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .manufacturer(let id): ManufacturerDetailView(manufacturerID: id)
            case .series(let id): SeriesDetailView(seriesID: id)
            case .category(let id): CategoryView(categoryID: id)
            case .document(let id, let page, let highlight): PDFReaderView(documentID: id, initialPage: page, highlight: highlight)
            }
        }
    }
}
