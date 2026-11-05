import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var editing: LocalDocument?

    var body: some View {
        let grouped = Dictionary(grouping: library.documents) { $0.manufacturerID ?? "" }
        let keys = grouped.keys.sorted { name(for: $0) < name(for: $1) }

        List {
            ForEach(keys, id: \.self) { key in
                Section(name(for: key)) {
                    ForEach(grouped[key, default: []].sorted { $0.title < $1.title }) { doc in
                        NavigationLink(value: Route.document(doc.id, page: nil, highlight: nil)) { DocumentRow(document: doc) }
                            .swipeActions {
                                Button(role: .destructive) { library.delete(doc) } label: { Label("Löschen", systemImage: "trash") }
                                Button { editing = doc } label: { Label("Bearbeiten", systemImage: "pencil") }
                                    .tint(.orange)
                            }
                    }
                }
            }
            if !library.documents.isEmpty {
                Section {
                    Text("\(library.documents.count) Dokumente · \(library.totalSizeText)")
                        .font(.footnote).foregroundStyle(.secondary)
                    if library.indexingCount > 0 {
                        Label("Texte werden für die Suche aufbereitet …", systemImage: "hourglass")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Offline")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showImporter = true } label: { Label("PDF hinzufügen", systemImage: "plus") }
            }
        }
        .overlay {
            if library.documents.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Offline-Anleitungen", systemImage: "arrow.down.circle")
                } description: {
                    Text("Öffne bei einem Produkt „Anleitung finden“ und tippe beim PDF auf „Offline speichern“. Oder füge PDFs aus der Dateien-App hinzu.")
                } actions: {
                    Button("PDF aus Dateien hinzufügen") { showImporter = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    do {
                        let doc = try library.importPDF(from: url, title: url.deletingPathExtension().lastPathComponent,
                                                        docType: .sonstiges, manufacturerID: guessManufacturer(url), seriesID: nil)
                        if urls.count == 1 { editing = doc }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $editing) { doc in EditDocumentSheet(document: doc) }
        .alert("Fehler", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func name(for manufacturerID: String) -> String {
        catalog.manufacturer(manufacturerID)?.name ?? "Ohne Hersteller"
    }

    /// Erkennt den Hersteller am Dateinamen (z. B. "Viessmann_Vitodens.pdf").
    private func guessManufacturer(_ url: URL) -> String? {
        let name = SearchIndex.compact(url.lastPathComponent)
        return catalog.manufacturers.first { m in
            let first = SearchIndex.compact(m.name.components(separatedBy: CharacterSet(charactersIn: " /(")).first ?? m.name)
            return first.count >= 3 && name.contains(first)
        }?.id
    }
}

struct EditDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    @State var document: LocalDocument

    var body: some View {
        NavigationStack {
            Form {
                Section("Dokument") {
                    TextField("Titel", text: $document.title, axis: .vertical)
                    Picker("Art", selection: $document.docType) {
                        ForEach(DocType.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                }
                Section("Zuordnung") {
                    Picker("Hersteller", selection: $document.manufacturerID) {
                        Text("Keiner").tag(String?.none)
                        ForEach(catalog.manufacturers) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .onChange(of: document.manufacturerID) { _, newValue in
                        if let sid = document.seriesID, catalog.series(sid)?.manufacturer.id != newValue { document.seriesID = nil }
                    }
                    if let mid = document.manufacturerID, let m = catalog.manufacturer(mid) {
                        Picker("Produkt", selection: $document.seriesID) {
                            Text("Keines").tag(String?.none)
                            ForEach(m.series) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }
                if let source = document.sourceURL {
                    Section("Quelle") { Link(source.absoluteString, destination: source).font(.caption).lineLimit(3) }
                }
            }
            .navigationTitle("Dokument bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { library.update(document); dismiss() }
                }
            }
        }
    }
}
