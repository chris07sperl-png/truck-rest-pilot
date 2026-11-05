import SwiftUI
import PDFKit

/// PDF-Ansicht mit Suche im Dokument, Seitensprung und Teilen.
struct PDFReaderView: View {
    @Environment(LibraryStore.self) private var library
    let documentID: UUID
    var initialPage: Int?
    var highlight: String?

    @State private var pdf: PDFDocument?
    @State private var searchText = ""
    @State private var matches: [PDFSelection] = []
    @State private var matchIndex = 0
    @State private var currentPage = 0
    @State private var jump: PDFJump?

    var body: some View {
        if let doc = library.document(documentID) {
            reader(doc)
        } else {
            ContentUnavailableView("Dokument nicht gefunden", systemImage: "doc.questionmark")
        }
    }

    private func reader(_ doc: LocalDocument) -> some View {
        PDFKitView(document: pdf, highlights: matches, jump: jump, currentPage: $currentPage)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(doc.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Im Dokument suchen")
            .onSubmit(of: .search) { runSearch() }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty { matches = []; matchIndex = 0 }
            }
            .safeAreaInset(edge: .bottom) {
                if !matches.isEmpty {
                    HStack {
                        Button { step(-1) } label: { Image(systemName: "chevron.up") }
                        Text("\(matchIndex + 1) von \(matches.count)").font(.subheadline.monospacedDigit())
                        Button { step(1) } label: { Image(systemName: "chevron.down") }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
                } else if let pdf {
                    Text("Seite \(currentPage + 1) / \(pdf.pageCount)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: library.fileURL(for: doc)) { Image(systemName: "square.and.arrow.up") }
                }
            }
            .task(id: doc.id) {
                let url = library.fileURL(for: doc)
                let loaded = await Task.detached { PDFDocument(url: url) }.value
                pdf = loaded
                if let highlight, !highlight.isEmpty {
                    searchText = highlight
                    runSearch(preferPage: initialPage)
                } else if let initialPage {
                    jump = PDFJump(page: initialPage)
                }
            }
    }

    private func runSearch(preferPage: Int? = nil) {
        guard let pdf, searchText.count >= 1 else { return }
        matches = pdf.findString(searchText, withOptions: [.caseInsensitive, .diacriticInsensitive])
        guard !matches.isEmpty else { return }
        if let preferPage,
           let i = matches.firstIndex(where: { sel in sel.pages.first.map { pdf.index(for: $0) } == preferPage }) {
            matchIndex = i
        } else {
            matchIndex = 0
        }
        jump = PDFJump(selection: matches[matchIndex])
    }

    private func step(_ delta: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + delta + matches.count) % matches.count
        jump = PDFJump(selection: matches[matchIndex])
    }
}

struct PDFJump: Equatable {
    let id = UUID()
    var page: Int?
    var selection: PDFSelection?
}

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument?
    let highlights: [PDFSelection]
    let jump: PDFJump?
    @Binding var currentPage: Int

    func makeCoordinator() -> Coordinator { Coordinator(currentPage: $currentPage) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.usePageViewController(false)
        context.coordinator.view = view
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged),
                                               name: .PDFViewPageChanged, object: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        view.highlightedSelections = highlights.isEmpty ? nil : highlights
        if let jump, jump != context.coordinator.lastJump, let doc = view.document {
            context.coordinator.lastJump = jump
            if let selection = jump.selection {
                view.setCurrentSelection(selection, animate: false)
                view.go(to: selection)
            } else if let p = jump.page, let page = doc.page(at: min(max(p, 0), doc.pageCount - 1)) {
                view.go(to: page)
            }
        }
    }

    final class Coordinator: NSObject {
        weak var view: PDFView?
        var lastJump: PDFJump?
        var currentPage: Binding<Int>
        init(currentPage: Binding<Int>) { self.currentPage = currentPage }

        @objc func pageChanged() {
            guard let view, let page = view.currentPage, let doc = view.document else { return }
            currentPage.wrappedValue = doc.index(for: page)
        }
    }
}
