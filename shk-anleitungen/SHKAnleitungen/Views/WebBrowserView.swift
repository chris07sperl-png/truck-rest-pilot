import SwiftUI
import WebKit

/// App-interner Browser: Hersteller-Portale und Suchergebnisse öffnen, PDFs offline speichern.
struct WebBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let link: BrowserLink
    @State private var model: BrowserModel
    @State private var showSave = false

    init(link: BrowserLink) {
        self.link = link
        _model = State(initialValue: BrowserModel(url: link.url))
    }

    var body: some View {
        NavigationStack {
            WebViewContainer(webView: model.webView)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if model.isLoading {
                        ProgressView(value: model.progress).progressViewStyle(.linear)
                    }
                }
                .navigationTitle(model.title.isEmpty ? link.title : model.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Fertig") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSave = true
                        } label: {
                            Label("Offline speichern", systemImage: "arrow.down.circle")
                        }
                        .disabled(!model.isPDF)
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button { model.webView.goBack() } label: { Image(systemName: "chevron.backward") }
                            .disabled(!model.canGoBack)
                        Spacer()
                        Button { model.webView.goForward() } label: { Image(systemName: "chevron.forward") }
                            .disabled(!model.canGoForward)
                        Spacer()
                        Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                        Spacer()
                        if let url = model.url {
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                            Spacer()
                            Button { openURL(url) } label: { Image(systemName: "safari") }
                        }
                    }
                }
                .safeAreaInset(edge: .top) {
                    if model.isPDF {
                        Button { showSave = true } label: {
                            Label("PDF erkannt – jetzt offline speichern", systemImage: "arrow.down.doc.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(10)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }
                }
                .sheet(isPresented: $showSave) {
                    if let url = model.url {
                        SaveDocumentSheet(url: url, suggestedTitle: model.suggestedTitle,
                                          manufacturerID: link.manufacturerID, seriesID: link.seriesID,
                                          docType: link.docType, cookieProvider: model.cookies)
                    }
                }
        }
    }
}

@Observable
final class BrowserModel: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var url: URL?
    var title = ""
    var progress = 0.0
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    private var mimeType: String?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    var isPDF: Bool {
        mimeType == "application/pdf" || url?.pathExtension.lowercased() == "pdf"
    }

    var suggestedTitle: String {
        let name = url?.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? ""
        if !title.isEmpty, title.lowercased() != url?.lastPathComponent.lowercased() { return title }
        return name.replacingOccurrences(of: "_", with: " ")
    }

    func cookies() async -> [HTTPCookie] {
        await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
    }

    init(url: URL) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        observations = [
            webView.observe(\.url) { [weak self] wv, _ in self?.url = wv.url },
            webView.observe(\.title) { [weak self] wv, _ in self?.title = wv.title ?? "" },
            webView.observe(\.estimatedProgress) { [weak self] wv, _ in self?.progress = wv.estimatedProgress },
            webView.observe(\.isLoading) { [weak self] wv, _ in self?.isLoading = wv.isLoading },
            webView.observe(\.canGoBack) { [weak self] wv, _ in self?.canGoBack = wv.canGoBack },
            webView.observe(\.canGoForward) { [weak self] wv, _ in self?.canGoForward = wv.canGoForward },
        ]
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame {
            mimeType = navigationResponse.response.mimeType
        }
        decisionHandler(.allow)
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Abfrage beim Speichern: Titel, Dokumentart und Zuordnung zu Hersteller/Serie.
struct SaveDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library

    let url: URL
    let cookieProvider: () async -> [HTTPCookie]
    @State var title: String
    @State var manufacturerID: String?
    @State var seriesID: String?
    @State var docType: DocType
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saved = false

    init(url: URL, suggestedTitle: String, manufacturerID: String?, seriesID: String?, docType: DocType,
         cookieProvider: @escaping () async -> [HTTPCookie]) {
        self.url = url
        self.cookieProvider = cookieProvider
        _title = State(initialValue: suggestedTitle)
        _manufacturerID = State(initialValue: manufacturerID)
        _seriesID = State(initialValue: seriesID)
        _docType = State(initialValue: docType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dokument") {
                    TextField("Titel", text: $title, axis: .vertical)
                    Picker("Art", selection: $docType) {
                        ForEach(DocType.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                }
                Section("Zuordnung") {
                    Picker("Hersteller", selection: $manufacturerID) {
                        Text("Keiner").tag(String?.none)
                        ForEach(catalog.manufacturers) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .onChange(of: manufacturerID) { _, newValue in
                        if let seriesID, catalog.series(seriesID)?.manufacturer.id != newValue { self.seriesID = nil }
                    }
                    if let mid = manufacturerID, let m = catalog.manufacturer(mid) {
                        Picker("Produkt", selection: $seriesID) {
                            Text("Keines").tag(String?.none)
                            ForEach(m.series) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }
                Section {
                    Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                } header: {
                    Text("Quelle")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Offline speichern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else {
                        Button("Speichern") { Task { await save() } }.disabled(title.isEmpty)
                    }
                }
            }
            .overlay {
                if saved {
                    Label("Gespeichert", systemImage: "checkmark.circle.fill")
                        .font(.title2.weight(.semibold))
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            let cookies = await cookieProvider()
            _ = try await library.download(from: url, title: title, docType: docType,
                                           manufacturerID: manufacturerID, seriesID: seriesID, cookies: cookies)
            withAnimation { saved = true }
            try? await Task.sleep(for: .milliseconds(800))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
