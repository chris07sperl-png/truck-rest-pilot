import SwiftUI

/// Farbiges Kürzel als Hersteller-Logo-Ersatz (keine fremden Markenlogos in der App).
struct ManufacturerBadge: View {
    let manufacturer: Manufacturer
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(manufacturer.tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(manufacturer.initials)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
            .accessibilityHidden(true)
    }
}

struct ManufacturerRow: View {
    let manufacturer: Manufacturer

    var body: some View {
        HStack(spacing: 12) {
            ManufacturerBadge(manufacturer: manufacturer)
            VStack(alignment: .leading, spacing: 2) {
                Text(manufacturer.name).font(.headline)
                Text(manufacturer.info)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SeriesRow: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    let manufacturer: Manufacturer
    let series: ProductSeries
    var showManufacturer = false
    var matchedModel: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: catalog.category(series.category)?.symbol ?? "doc")
                .font(.title3)
                .foregroundStyle(manufacturer.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(series.name).font(.body.weight(.medium))
                Group {
                    if let matchedModel {
                        Text("Modell: \(matchedModel)")
                    } else if showManufacturer {
                        Text("\(manufacturer.name) · \(catalog.category(series.category)?.name ?? "")")
                    } else if !series.models.isEmpty {
                        Text(series.models.prefix(4).joined(separator: ", "))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            let offline = library.documents(forSeries: series.id).count
            if offline > 0 {
                Label("\(offline)", systemImage: "arrow.down.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }
}

struct DocumentRow: View {
    @Environment(CatalogStore.self) private var catalog
    let document: LocalDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.title2)
                .foregroundStyle(.red)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title).font(.body.weight(.medium)).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var subtitle: String {
        var parts = [document.docType.rawValue, "\(document.pageCount) S."]
        if let id = document.manufacturerID, let m = catalog.manufacturer(id) { parts.insert(m.name, at: 0) }
        return parts.joined(separator: " · ")
    }
}

/// Horizontale Auswahl der Produktarten.
struct CategoryChips: View {
    @Environment(CatalogStore.self) private var catalog
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Alle", symbol: "square.grid.2x2", selected: selection == nil) { selection = nil }
                ForEach(catalog.categories) { c in
                    chip(title: c.name, symbol: c.symbol, selected: selection == c.id) {
                        selection = selection == c.id ? nil : c.id
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// Öffnet eine Webseite im App-Browser (mit "Offline speichern").
struct BrowserLink: Identifiable {
    let url: URL
    let title: String
    var manufacturerID: String?
    var seriesID: String?
    var docType: DocType = .bedienung
    var id: URL { url }
}
