import SwiftUI
import PhotosUI

// MARK: - Liste aller Anlagen

struct InstallationsListView: View {
    @Environment(InstallationStore.self) private var store
    @Environment(CatalogStore.self) private var catalog
    @State private var filter = ""
    @State private var newInstallation: Installation?
    @State private var toDelete: Installation?

    var body: some View {
        let items = store.sorted.filter(matches)
        let service = store.serviceList

        List {
            if filter.isEmpty && !service.isEmpty {
                Section("Wartung") {
                    ForEach(service) { entry in
                        NavigationLink(value: Route.device(entry.device.id, installation: entry.installation.id)) {
                            ServiceRow(installation: entry.installation, device: entry.device)
                        }
                    }
                }
            }
            Section(filter.isEmpty ? "Kunden & Objekte" : "Treffer") {
                ForEach(items) { inst in
                    NavigationLink(value: Route.installation(inst.id)) { InstallationRow(installation: inst) }
                        .swipeActions {
                            Button(role: .destructive) { toDelete = inst } label: { Label("Löschen", systemImage: "trash") }
                        }
                }
            }
        }
        .navigationTitle("Anlagen")
        .searchable(text: $filter, prompt: "Kunde, Adresse, Gerät, Seriennr.")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newInstallation = Installation(name: "") } label: { Label("Neue Anlage", systemImage: "plus") }
            }
        }
        .overlay {
            if store.installations.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Anlagen", systemImage: "house")
                } description: {
                    Text("Lege Kunden und Objekte an und hinterlege die verbauten Geräte – mit Seriennummer, Foto vom Typenschild und Wartungstermin. Die passenden Anleitungen sind dann einen Tipp entfernt.")
                } actions: {
                    Button("Erste Anlage anlegen") { newInstallation = Installation(name: "") }
                        .buttonStyle(.borderedProminent)
                }
            } else if items.isEmpty {
                ContentUnavailableView.search(text: filter)
            }
        }
        .sheet(item: $newInstallation) { inst in InstallationEditSheet(installation: inst, isNew: true) }
        .confirmationDialog("Anlage löschen?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible, presenting: toDelete) { inst in
            Button("„\(inst.name)“ löschen", role: .destructive) { store.delete(inst) }
        } message: { inst in
            Text("Alle \(inst.devices.count) Geräte und Fotos dieser Anlage werden gelöscht.")
        }
    }

    private func matches(_ inst: Installation) -> Bool {
        guard !filter.isEmpty else { return true }
        var text = [inst.name, inst.address, inst.phone, inst.notes].joined(separator: " ")
        for d in inst.devices {
            text += " " + [d.model, d.serialNumber, d.location].joined(separator: " ")
            if let sid = d.seriesID, let s = catalog.series(sid) { text += " \(s.manufacturer.name) \(s.series.name)" }
            else if let mid = d.manufacturerID, let m = catalog.manufacturer(mid) { text += " \(m.name)" }
        }
        let hay = SearchIndex.compact(text)
        return SearchIndex.words(filter).allSatisfy { hay.contains($0) }
    }
}

struct InstallationRow: View {
    let installation: Installation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(installation.name).font(.headline)
                if !installation.dueDevices.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .accessibilityLabel("Wartung fällig")
                }
            }
            if !installation.address.isEmpty {
                Text(installation.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(installation.devices.count == 1 ? "1 Gerät" : "\(installation.devices.count) Geräte")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ServiceRow: View {
    let installation: Installation
    let device: InstalledDevice
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.isServiceDue ? "exclamationmark.triangle.fill" : "clock")
                .foregroundStyle(device.isServiceDue ? .red : .orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(installation.name).font(.subheadline.weight(.semibold))
                Text(DeviceText.title(device, catalog: catalog)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let next = device.nextService {
                    Text(device.isServiceDue ? "Fällig seit \(next.formatted(date: .abbreviated, time: .omitted))"
                                             : "Fällig am \(next.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(device.isServiceDue ? .red : .orange)
                }
            }
        }
    }
}

enum DeviceText {
    static func title(_ device: InstalledDevice, catalog: CatalogStore) -> String {
        var parts: [String] = []
        if let sid = device.seriesID, let s = catalog.series(sid) {
            parts = [s.manufacturer.name, s.series.name]
        } else if let mid = device.manufacturerID, let m = catalog.manufacturer(mid) {
            parts = [m.name]
        }
        if !device.model.isEmpty { parts.append(device.model) }
        return parts.isEmpty ? "Gerät" : parts.joined(separator: " · ")
    }
}

// MARK: - Anlage

struct InstallationDetailView: View {
    @Environment(InstallationStore.self) private var store
    @Environment(CatalogStore.self) private var catalog
    let installationID: UUID
    @State private var editing: Installation?
    @State private var newDevice: InstalledDevice?

    var body: some View {
        if let inst = store.installation(installationID) {
            List {
                Section {
                    if !inst.address.isEmpty {
                        Button {
                            openMaps(inst.address)
                        } label: {
                            Label(inst.address, systemImage: "mappin.and.ellipse")
                        }
                    }
                    if !inst.phone.isEmpty, let url = URL(string: "tel:" + inst.phone.filter { $0.isNumber || $0 == "+" }) {
                        Link(destination: url) { Label(inst.phone, systemImage: "phone") }
                    }
                    if !inst.notes.isEmpty {
                        Label(inst.notes, systemImage: "note.text").foregroundStyle(.secondary)
                    }
                    if inst.address.isEmpty && inst.phone.isEmpty && inst.notes.isEmpty {
                        Button("Adresse und Notizen ergänzen") { editing = inst }
                    }
                }

                Section("Geräte") {
                    ForEach(inst.devices) { device in
                        NavigationLink(value: Route.device(device.id, installation: inst.id)) {
                            DeviceRow(device: device)
                        }
                    }
                    .onDelete { idx in
                        idx.map { inst.devices[$0].id }.forEach { store.delete(deviceID: $0, in: inst.id) }
                    }
                    Button {
                        newDevice = InstalledDevice()
                    } label: {
                        Label("Gerät hinzufügen", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(inst.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bearbeiten") { editing = inst }
                }
            }
            .sheet(item: $editing) { i in InstallationEditSheet(installation: i, isNew: false) }
            .sheet(item: $newDevice) { d in DeviceEditSheet(device: d, installationID: inst.id) }
        } else {
            ContentUnavailableView("Anlage nicht gefunden", systemImage: "house")
        }
    }

    private func openMaps(_ address: String) {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: address)]
        if let url = components.url { UIApplication.shared.open(url) }
    }
}

struct DeviceRow: View {
    @Environment(CatalogStore.self) private var catalog
    let device: InstalledDevice

    var body: some View {
        HStack(spacing: 12) {
            if let mid = device.manufacturerID ?? device.seriesID.flatMap({ catalog.series($0)?.manufacturer.id }),
               let m = catalog.manufacturer(mid) {
                ManufacturerBadge(manufacturer: m, size: 36)
            } else {
                Image(systemName: "shippingbox").font(.title3).frame(width: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(DeviceText.title(device, catalog: catalog)).font(.subheadline.weight(.medium)).lineLimit(2)
                HStack(spacing: 8) {
                    if !device.location.isEmpty { Text(device.location) }
                    if !device.serialNumber.isEmpty { Text("S/N \(device.serialNumber)").monospaced() }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let next = device.nextService {
                    Text("Wartung \(next.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(device.isServiceDue ? .red : device.isServiceSoon ? .orange : .secondary)
                }
            }
        }
    }
}

// MARK: - Gerät

struct DeviceDetailView: View {
    @Environment(InstallationStore.self) private var store
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    let deviceID: UUID
    let installationID: UUID
    @State private var editing: InstalledDevice?
    @State private var showPhoto = false
    @State private var confirmService = false

    var body: some View {
        if let device = store.device(deviceID, in: installationID), let inst = store.installation(installationID) {
            List {
                if let photo = device.photoFileName, let image = store.photo(photo) {
                    Section {
                        Button { showPhoto = true } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: 220)
                                .clipped()
                        }
                        .listRowInsets(EdgeInsets())
                    }
                    .fullScreenCover(isPresented: $showPhoto) { PhotoViewer(image: image) }
                }

                Section("Gerät") {
                    LabeledContent("Anlage", value: inst.name)
                    if let sid = device.seriesID, let s = catalog.series(sid) {
                        LabeledContent("Hersteller", value: s.manufacturer.name)
                        LabeledContent("Produkt", value: s.series.name)
                    } else if let mid = device.manufacturerID, let m = catalog.manufacturer(mid) {
                        LabeledContent("Hersteller", value: m.name)
                    }
                    if !device.model.isEmpty { LabeledContent("Typ / Modell", value: device.model) }
                    if !device.serialNumber.isEmpty {
                        LabeledContent("Seriennummer") {
                            Text(device.serialNumber).monospaced().textSelection(.enabled)
                        }
                    }
                    if !device.location.isEmpty { LabeledContent("Standort", value: device.location) }
                    if let d = device.installedOn {
                        LabeledContent("Eingebaut", value: d.formatted(date: .abbreviated, time: .omitted))
                    }
                }

                Section("Wartung") {
                    if let last = device.lastService {
                        LabeledContent("Letzte Wartung", value: last.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let next = device.nextService {
                        LabeledContent("Nächste Wartung") {
                            Text(next.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(device.isServiceDue ? .red : device.isServiceSoon ? .orange : .secondary)
                        }
                    }
                    LabeledContent("Intervall", value: "\(device.serviceIntervalMonths) Monate")
                    Button {
                        confirmService = true
                    } label: {
                        Label("Wartung heute erledigt", systemImage: "checkmark.seal")
                    }
                }

                if !device.notes.isEmpty {
                    Section("Notizen") { Text(device.notes).textSelection(.enabled) }
                }

                if let sid = device.seriesID, let s = catalog.series(sid) {
                    Section("Anleitungen") {
                        ForEach(library.documents(forSeries: sid)) { doc in
                            NavigationLink(value: Route.document(doc.id, page: nil, highlight: nil)) { DocumentRow(document: doc) }
                        }
                        NavigationLink(value: Route.series(sid)) {
                            Label("Alle Anleitungen zu \(s.series.name)", systemImage: "books.vertical")
                        }
                    }
                } else if let mid = device.manufacturerID {
                    Section("Anleitungen") {
                        NavigationLink(value: Route.manufacturer(mid)) {
                            Label("Produkte des Herstellers", systemImage: "books.vertical")
                        }
                    }
                }
            }
            .navigationTitle(device.model.isEmpty ? "Gerät" : device.model)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Bearbeiten") { editing = device } }
            }
            .sheet(item: $editing) { d in DeviceEditSheet(device: d, installationID: installationID) }
            .confirmationDialog("Wartung für heute eintragen?", isPresented: $confirmService, titleVisibility: .visible) {
                Button("Wartung am \(Date.now.formatted(date: .abbreviated, time: .omitted)) eintragen") {
                    store.markServiced(deviceID: deviceID, in: installationID)
                }
            }
        } else {
            ContentUnavailableView("Gerät nicht gefunden", systemImage: "shippingbox")
        }
    }
}

private struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .gesture(MagnifyGesture().onChanged { scale = max(1, min(5, $0.magnification)) })
                .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5 } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Typenschild", image: Image(uiImage: image)))
                }
            }
        }
    }
}

// MARK: - Bearbeiten

struct InstallationEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(InstallationStore.self) private var store
    @State var installation: Installation
    let isNew: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Kunde / Objekt") {
                    TextField("Name", text: $installation.name)
                    TextField("Adresse", text: $installation.address, axis: .vertical)
                        .textContentType(.fullStreetAddress)
                    TextField("Telefon", text: $installation.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                Section("Notizen") {
                    TextField("z. B. Schlüssel beim Nachbarn, Zugang Keller", text: $installation.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(isNew ? "Neue Anlage" : "Anlage bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        installation.name = installation.name.trimmingCharacters(in: .whitespaces)
                        store.save(installation)
                        dismiss()
                    }
                    .disabled(installation.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct DeviceEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(InstallationStore.self) private var store
    @Environment(CatalogStore.self) private var catalog
    @State var device: InstalledDevice
    let installationID: UUID

    @State private var showScanner = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Typenschild scannen", systemImage: "text.viewfinder")
                    }
                } footer: {
                    Text("Erkennt Hersteller, Gerät, Typ und Seriennummer automatisch.")
                }

                Section("Gerät") {
                    Picker("Hersteller", selection: $device.manufacturerID) {
                        Text("Keiner").tag(String?.none)
                        ForEach(catalog.manufacturers) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .onChange(of: device.manufacturerID) { _, newValue in
                        if let sid = device.seriesID, catalog.series(sid)?.manufacturer.id != newValue { device.seriesID = nil }
                    }
                    if let mid = device.manufacturerID, let m = catalog.manufacturer(mid) {
                        Picker("Produkt", selection: $device.seriesID) {
                            Text("Keines").tag(String?.none)
                            ForEach(m.series) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    HStack {
                        TextField("Typ / Modell", text: $device.model)
                            .autocorrectionDisabled()
                        if let sid = device.seriesID, let s = catalog.series(sid), !s.series.models.isEmpty {
                            Menu {
                                ForEach(s.series.models, id: \.self) { model in
                                    Button(model) { device.model = model }
                                }
                            } label: {
                                Image(systemName: "list.bullet")
                            }
                            .accessibilityLabel("Typ auswählen")
                        }
                    }
                    TextField("Seriennummer", text: $device.serialNumber)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .monospaced()
                    TextField("Standort (z. B. Keller, Dachboden)", text: $device.location)
                }

                Section("Daten") {
                    OptionalDatePicker(title: "Einbaudatum", date: $device.installedOn)
                    OptionalDatePicker(title: "Letzte Wartung", date: $device.lastService)
                    Stepper("Wartung alle \(device.serviceIntervalMonths) Monate",
                            value: $device.serviceIntervalMonths, in: 1...60)
                }

                Section("Foto") {
                    if let image = pendingImage ?? device.photoFileName.flatMap(store.photo) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .frame(maxWidth: .infinity)
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: { Label("Foto aufnehmen", systemImage: "camera") }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Foto auswählen", systemImage: "photo")
                    }
                    if pendingImage != nil || device.photoFileName != nil {
                        Button("Foto entfernen", role: .destructive) {
                            pendingImage = nil
                            device.photoFileName = nil
                        }
                    }
                }

                Section("Notizen") {
                    TextField("z. B. Ersatzteile, Einstellungen, Besonderheiten", text: $device.notes, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .navigationTitle(store.device(device.id, in: installationID) == nil ? "Neues Gerät" : "Gerät bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                }
            }
            .sheet(isPresented: $showScanner) {
                NameplateScannerView { scan in apply(scan) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in pendingImage = image }.ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        pendingImage = image
                    }
                    photoItem = nil
                }
            }
        }
    }

    private func apply(_ scan: NameplateScan) {
        if let mid = scan.manufacturerID { device.manufacturerID = mid }
        if let sid = scan.seriesID { device.seriesID = sid }
        if let model = scan.model, device.model.isEmpty { device.model = model }
        if let serial = scan.serialNumber, device.serialNumber.isEmpty { device.serialNumber = serial }
    }

    private func save() {
        if let image = pendingImage, let name = store.storePhoto(image) {
            device.photoFileName = name
        }
        store.save(device, in: installationID)
        dismiss()
    }
}

/// Datum, das auch "unbekannt" sein darf.
struct OptionalDatePicker: View {
    let title: String
    @Binding var date: Date?

    var body: some View {
        Toggle(title, isOn: Binding(get: { date != nil }, set: { date = $0 ? (date ?? .now) : nil }))
        if let value = date {
            DatePicker(title, selection: Binding(get: { value }, set: { date = $0 }),
                       in: ...Date.now.addingTimeInterval(86_400 * 366), displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
