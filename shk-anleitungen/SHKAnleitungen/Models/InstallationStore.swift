import Foundation
import UIKit

/// Eine Kundenanlage (Objekt) mit den eingebauten Geräten.
struct Installation: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var address = ""
    var phone = ""
    var notes = ""
    var devices: [InstalledDevice] = []
    var createdAt = Date()

    var dueDevices: [InstalledDevice] { devices.filter(\.isServiceDue) }
}

/// Ein Gerät in einer Anlage, verknüpft mit dem Katalog.
struct InstalledDevice: Codable, Identifiable, Hashable {
    var id = UUID()
    var manufacturerID: String?
    var seriesID: String?
    var model = ""
    var serialNumber = ""
    var location = ""
    var installedOn: Date?
    var lastService: Date?
    var serviceIntervalMonths = 12
    var notes = ""
    var photoFileName: String?

    var nextService: Date? {
        guard let lastService else { return nil }
        return Calendar.current.date(byAdding: .month, value: serviceIntervalMonths, to: lastService)
    }

    var isServiceDue: Bool {
        guard let nextService else { return false }
        return nextService <= .now
    }

    /// Fällig innerhalb der nächsten 30 Tage (aber noch nicht überfällig).
    var isServiceSoon: Bool {
        guard let nextService, !isServiceDue else { return false }
        return nextService <= Calendar.current.date(byAdding: .day, value: 30, to: .now)!
    }
}

struct ServiceEntry: Identifiable {
    let installation: Installation
    let device: InstalledDevice
    var id: UUID { device.id }
}

@Observable
final class InstallationStore {
    private(set) var installations: [Installation] = []

    private let baseDir: URL
    private var photosDir: URL { baseDir.appending(path: "Fotos") }
    private var dataURL: URL { baseDir.appending(path: "anlagen.json") }

    init() {
        baseDir = URL.documentsDirectory.appending(path: "Anlagen")
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: dataURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            installations = (try? decoder.decode([Installation].self, from: data)) ?? []
        }
    }

    var sorted: [Installation] {
        installations.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Alle Geräte mit fälliger oder bald fälliger Wartung.
    var serviceList: [ServiceEntry] {
        installations
            .flatMap { inst in inst.devices.filter { $0.isServiceDue || $0.isServiceSoon }.map { ServiceEntry(installation: inst, device: $0) } }
            .sorted { ($0.device.nextService ?? .distantFuture) < ($1.device.nextService ?? .distantFuture) }
    }

    var dueCount: Int { installations.reduce(0) { $0 + $1.dueDevices.count } }

    func installation(_ id: UUID) -> Installation? { installations.first { $0.id == id } }

    func device(_ id: UUID, in installationID: UUID) -> InstalledDevice? {
        installation(installationID)?.devices.first { $0.id == id }
    }

    /// Anlagen, in denen ein Gerät dieser Serie verbaut ist.
    func installations(withSeries seriesID: String) -> [Installation] {
        installations.filter { $0.devices.contains { $0.seriesID == seriesID } }
    }

    func save(_ installation: Installation) {
        if let i = installations.firstIndex(where: { $0.id == installation.id }) {
            installations[i] = installation
        } else {
            installations.append(installation)
        }
        persist()
    }

    func delete(_ installation: Installation) {
        installation.devices.compactMap(\.photoFileName).forEach(deletePhoto)
        installations.removeAll { $0.id == installation.id }
        persist()
    }

    func save(_ device: InstalledDevice, in installationID: UUID) {
        guard var inst = installation(installationID) else { return }
        if let i = inst.devices.firstIndex(where: { $0.id == device.id }) {
            if let old = inst.devices[i].photoFileName, old != device.photoFileName { deletePhoto(old) }
            inst.devices[i] = device
        } else {
            inst.devices.append(device)
        }
        save(inst)
    }

    func delete(deviceID: UUID, in installationID: UUID) {
        guard var inst = installation(installationID) else { return }
        if let photo = inst.devices.first(where: { $0.id == deviceID })?.photoFileName { deletePhoto(photo) }
        inst.devices.removeAll { $0.id == deviceID }
        save(inst)
    }

    func markServiced(deviceID: UUID, in installationID: UUID, on date: Date = .now) {
        guard var device = device(deviceID, in: installationID) else { return }
        device.lastService = date
        save(device, in: installationID)
    }

    // MARK: Fotos

    /// Speichert ein Foto verkleinert als JPEG und gibt den Dateinamen zurück.
    func storePhoto(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.8) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: photosDir.appending(path: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func photoURL(_ name: String) -> URL { photosDir.appending(path: name) }

    func photo(_ name: String) -> UIImage? { UIImage(contentsOfFile: photoURL(name).path) }

    private func deletePhoto(_ name: String) {
        try? FileManager.default.removeItem(at: photoURL(name))
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(installations) {
            try? data.write(to: dataURL, options: .atomic)
        }
    }
}
