import Foundation

/// Ein gefundenes PDF im Internet.
struct DocumentHit: Identifiable, Hashable {
    let title: String
    let url: URL
    let snippet: String
    /// Liegt auf einer Domain des Herstellers.
    let isOfficial: Bool
    var id: URL { url }
    var host: String { url.host()?.replacingOccurrences(of: "www.", with: "") ?? "" }
}

/// Sucht Anleitungen als PDF direkt aus der App – ohne Umweg über eine Suchmaschinen-Webseite.
///
/// Fragt Bing (RSS-Ausgabe) und DuckDuckGo (HTML-Version) ab, behält nur PDF-Links,
/// sortiert Herstellerseiten nach oben und entfernt Doppelte.
actor DocumentFinder {
    static let shared = DocumentFinder()

    private var cache: [String: [DocumentHit]] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept-Language": "de-DE,de;q=0.9",
        ]
        return URLSession(configuration: config)
    }()

    func find(_ query: String, officialDomains: [String], limit: Int = 25) async -> [DocumentHit] {
        let fullQuery = query + " filetype:pdf"
        if let cached = cache[fullQuery] { return cached }

        async let bing = bingResults(fullQuery)
        async let ddg = duckDuckGoResults(fullQuery)
        let raw = await bing + ddg

        var seen = Set<String>()
        var hits: [DocumentHit] = []
        for (title, link, snippet) in raw {
            guard var url = URL(string: link), let host = url.host()?.lowercased() else { continue }
            // Nur PDFs; http auf https anheben (iOS lädt kein unverschlüsseltes http).
            guard url.path().lowercased().contains(".pdf") || link.lowercased().contains(".pdf") else { continue }
            if url.scheme == "http", var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                c.scheme = "https"
                url = c.url ?? url
            }
            let key = host + url.path().lowercased()
            guard seen.insert(key).inserted else { continue }
            let official = officialDomains.contains { host == $0 || host.hasSuffix("." + $0) }
            hits.append(DocumentHit(title: Self.cleanTitle(title, url: url), url: url,
                                    snippet: snippet, isOfficial: official))
        }
        // Herstellerseiten zuerst, sonst Reihenfolge der Suchmaschine beibehalten.
        let sorted = hits.enumerated()
            .sorted { ($0.element.isOfficial ? 0 : 1, $0.offset) < ($1.element.isOfficial ? 0 : 1, $1.offset) }
            .map(\.element)
        let result = Array(sorted.prefix(limit))
        if !result.isEmpty { cache[fullQuery] = result }
        return result
    }

    // MARK: Bing (RSS)

    private func bingResults(_ query: String) async -> [(String, String, String)] {
        var c = URLComponents(string: "https://www.bing.com/search")!
        c.queryItems = [URLQueryItem(name: "format", value: "rss"), URLQueryItem(name: "q", value: query),
                        URLQueryItem(name: "setlang", value: "de"), URLQueryItem(name: "count", value: "30")]
        guard let url = c.url, let response = try? await session.data(from: url) else { return [] }
        return RSSItemParser.parse(response.0)
    }

    // MARK: DuckDuckGo (HTML)

    private func duckDuckGoResults(_ query: String) async -> [(String, String, String)] {
        var c = URLComponents(string: "https://html.duckduckgo.com/html/")!
        c.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "kl", value: "de-de")]
        guard let url = c.url, let response = try? await session.data(from: url),
              let html = String(data: response.0, encoding: .utf8) else { return [] }
        return Self.parseDuckDuckGo(html)
    }

    static func parseDuckDuckGo(_ html: String) -> [(String, String, String)] {
        // Attribut-Reihenfolge kann variieren: class vor href oder href vor class.
        let patterns = [#"<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#,
                        #"<a[^>]*href="([^"]+)"[^>]*class="result__a"[^>]*>(.*?)</a>"#]
        let ns = html as NSString
        let matches = patterns
            .compactMap { try? NSRegularExpression(pattern: $0, options: [.dotMatchesLineSeparators]) }
            .flatMap { $0.matches(in: html, range: NSRange(location: 0, length: ns.length)) }
            .sorted { $0.range.location < $1.range.location }
        return matches.compactMap { m in
            var href = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            // Weiterleitungslinks "//duckduckgo.com/l/?uddg=<Ziel>&rut=…" auflösen.
            if href.contains("uddg="), let comps = URLComponents(string: href.hasPrefix("//") ? "https:" + href : href),
               let target = comps.queryItems?.first(where: { $0.name == "uddg" })?.value {
                href = target
            }
            guard href.hasPrefix("http") else { return nil }
            let title = stripTags(ns.substring(with: m.range(at: 2)))
            return (title, href, "")
        }
    }

    // MARK: Hilfen

    static func stripTags(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (a, b) in [("&amp;", "&"), ("&quot;", "\""), ("&#x27;", "'"), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Macht aus Dateinamen wie "Wolf-CGB-2_Montageanleitung.pdf" einen lesbaren Titel.
    static func cleanTitle(_ title: String, url: URL) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count >= 8, !t.lowercased().hasPrefix("http") { return t }
        let name = url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        return name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
    }
}

/// Liest <item><title>/<link>/<description> aus einem RSS-Feed.
private final class RSSItemParser: NSObject, XMLParserDelegate {
    private var items: [(String, String, String)] = []
    private var inItem = false
    private var element = ""
    private var title = "", link = "", desc = ""

    static func parse(_ data: Data) -> [(String, String, String)] {
        let delegate = RSSItemParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        element = elementName
        if elementName == "item" { inItem = true; title = ""; link = ""; desc = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch element {
        case "title": title += string
        case "link": link += string
        case "description": desc += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            inItem = false
            items.append((title.trimmingCharacters(in: .whitespacesAndNewlines),
                          link.trimmingCharacters(in: .whitespacesAndNewlines),
                          DocumentFinder.stripTags(desc)))
        }
        element = ""
    }
}
