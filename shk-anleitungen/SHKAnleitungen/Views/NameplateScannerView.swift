import SwiftUI
import PhotosUI
import Vision
import VisionKit

/// Ergebnis eines Typenschild-Scans.
struct NameplateScan {
    var manufacturerID: String?
    var seriesID: String?
    var model: String?
    var serialNumber: String?
    var text: String
}

/// Typenschild scannen: live mit der Kamera (Live Text) oder aus einem Foto.
/// Die App erkennt Hersteller, Serie, Modell und – wenn lesbar – die Seriennummer.
struct NameplateScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalog
    let onSelect: (NameplateScan) -> Void

    @State private var lines: [String] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isReadingPhoto = false

    private var liveAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    private var text: String { lines.joined(separator: "\n") }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if liveAvailable {
                    LiveTextScanner(lines: $lines)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .top) {
                            Text("Kamera aufs Typenschild halten")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.regularMaterial, in: Capsule())
                                .padding(.top, 8)
                        }
                } else {
                    ContentUnavailableView {
                        Label("Live-Scan nicht verfügbar", systemImage: "camera.viewfinder")
                    } description: {
                        Text("Mach ein Foto vom Typenschild oder wähle eins aus deinen Fotos.")
                    }
                    .frame(maxHeight: .infinity)
                }
                resultsPanel
            }
            .navigationTitle("Typenschild")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: { Image(systemName: "camera") }
                            .accessibilityLabel("Foto aufnehmen")
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                    }
                    .accessibilityLabel("Foto wählen")
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    isReadingPhoto = true
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        lines = await TextRecognizer.lines(in: image)
                    }
                    isReadingPhoto = false
                    photoItem = nil
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task {
                        isReadingPhoto = true
                        lines = await TextRecognizer.lines(in: image)
                        isReadingPhoto = false
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var resultsPanel: some View {
        let matches = catalog.searchIndex.identify(text: text)
        let manufacturers = catalog.searchIndex.manufacturers(in: text)
        let serial = NameplateParser.serialNumber(in: lines)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(matches.isEmpty ? "Noch kein Gerät erkannt" : "Erkannte Geräte")
                    .font(.headline)
                Spacer()
                if isReadingPhoto { ProgressView() }
                if !lines.isEmpty {
                    Button("Neu") { lines = [] }.font(.subheadline)
                }
            }
            if let serial {
                Label("Seriennummer: \(serial)", systemImage: "number")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(matches) { r in
                        if let item = catalog.series(r.entry.id) {
                            Button {
                                finish(NameplateScan(manufacturerID: item.manufacturer.id, seriesID: item.series.id,
                                                     model: r.matchedModel, serialNumber: serial, text: text))
                            } label: {
                                HStack(spacing: 12) {
                                    ManufacturerBadge(manufacturer: item.manufacturer, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(item.manufacturer.name) \(item.series.name)")
                                            .font(.subheadline.weight(.semibold))
                                            .multilineTextAlignment(.leading)
                                        if let model = r.matchedModel {
                                            Text("Modell \(model)").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .padding(10)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if matches.isEmpty, let mid = manufacturers.first, let m = catalog.manufacturer(mid) {
                        Button {
                            finish(NameplateScan(manufacturerID: m.id, serialNumber: serial, text: text))
                        } label: {
                            Label("Hersteller \(m.name) übernehmen", systemImage: "building.2")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    if !lines.isEmpty {
                        DisclosureGroup("Erkannter Text (\(lines.count) Zeilen)") {
                            Text(text)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .font(.subheadline)
                        Button {
                            finish(NameplateScan(manufacturerID: manufacturers.first, serialNumber: serial, text: text))
                        } label: {
                            Label("Nur Text übernehmen", systemImage: "text.viewfinder")
                        }
                        .font(.subheadline)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding()
        .background(.bar)
    }

    private func finish(_ scan: NameplateScan) {
        onSelect(scan)
        dismiss()
    }
}

// MARK: - Live Text (VisionKit)

private struct LiveTextScanner: UIViewControllerRepresentable {
    @Binding var lines: [String]

    func makeCoordinator() -> Coordinator { Coordinator(lines: $lines) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["de-DE", "en-US"])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        DispatchQueue.main.async { try? vc.startScanning() }
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.lines = $lines
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var lines: Binding<[String]>
        init(lines: Binding<[String]>) { self.lines = lines }

        /// Neue Zeilen sammeln, damit man das Schild abschnittsweise abfahren kann.
        private func collect(_ items: [RecognizedItem]) {
            var current = lines.wrappedValue
            for item in items {
                guard case .text(let text) = item else { continue }
                for line in text.transcript.components(separatedBy: .newlines) {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if t.count >= 2, !current.contains(t) { current.append(t) }
                }
            }
            if current != lines.wrappedValue { lines.wrappedValue = Array(current.suffix(60)) }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            collect(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            collect(allItems)
        }
    }
}

// MARK: - Texterkennung aus Fotos (Vision)

enum TextRecognizer {
    static func lines(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) { () -> [String] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE", "en-US"]
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try? handler.perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

enum NameplateParser {
    private static let label = #"\b(fabr(ik)?\.?\s*-?\s*nr|serien\s*-?\s*nr|serial(\s*no)?|s\s*/\s*n|herstell\s*-?\s*nr|fertigungs\s*-?\s*nr)\.?"#

    /// Sucht die Seriennummer (Fabrik-Nr., Serien-Nr., S/N …) im erkannten Text.
    static func serialNumber(in lines: [String]) -> String? {
        guard let inline = try? NSRegularExpression(pattern: label + #"\s*[:.]?\s*([A-Z0-9][A-Z0-9 \-/]{4,30})"#, options: .caseInsensitive),
              let alone = try? NSRegularExpression(pattern: "^\\s*" + label + #"\s*:?\s*$"#, options: .caseInsensitive)
        else { return nil }

        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            // "Fabrik-Nr. 7838512 1234 5" in einer Zeile
            if let match = inline.firstMatch(in: line, range: range),
               let r = Range(match.range(at: match.numberOfRanges - 1), in: line) {
                let value = line[r].trimmingCharacters(in: .whitespaces)
                if value.filter(\.isNumber).count >= 4 { return value }
            }
            // "Fabrik-Nr." allein, die Nummer steht in der nächsten Zeile
            if alone.firstMatch(in: line, range: range) != nil, index + 1 < lines.count {
                let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if next.filter(\.isNumber).count >= 4, next.count <= 30 { return next }
            }
        }
        return nil
    }
}

// MARK: - Kamera

struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
