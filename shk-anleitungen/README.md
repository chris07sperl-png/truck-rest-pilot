# SHK Anleitungen (iPhone-App)

Bedienungs-, Montage- und Serviceanleitungen für SHK-Handwerker, sortiert nach Hersteller
und Produktart, mit einer Suche, die auch Tippfehler verzeiht, und mit Offline-PDFs für den Heizungskeller.

## Was die App kann

- **Hersteller-Katalog**: 28 Hersteller (Viessmann, Wolf, Weishaupt, Buderus, Vaillant, Bosch/Junkers,
  Brötje, Remeha, Elco, Hoval, Stiebel Eltron, Daikin, NIBE, Grundfos, Wilo, Geberit, Grohe, …) mit
  197 Produktserien und den Typbezeichnungen vom Typenschild.
- **Nach Produktart**: Gas, Öl, Wärmepumpe, Pellets, Brenner, Regelung, Speicher, Solar, Lüftung,
  Klima, Pumpen, Armaturen, Sanitär, Heizkörper, Elektro-Warmwasser.
- **Anleitung finden**: Pro Gerät und Modell eine gezielte Suche nach Bedienungs-, Montage- oder
  Serviceanleitung, Datenblatt und Ersatzteilliste auf den Seiten des Herstellers, dazu ein Link zum
  offiziellen Dokumenten-Portal, wo es eins gibt.
- **Offline speichern**: Ein im App-Browser geöffnetes PDF lässt sich mit einem Tipp aufs iPhone laden
  und dem Gerät zuordnen. Eigene PDFs können aus der Dateien-App dazukommen.
- **Suche**:
  - Umlaute egal: „Wärmepumpe“, „waermepumpe“ und „warmepumpe“ finden dasselbe.
  - Leerzeichen und Bindestriche egal: „vitodens200w“, „cgb2k“.
  - Typcodes vom Typenschild: „B2HF“, „RC310“, „VWL 75/6“.
  - Kleine Tippfehler: „Vitodnes“.
  - **Volltextsuche in allen Offline-PDFs**, z. B. nach Störcodes wie „F.28“. Der Treffer öffnet das PDF
    an der richtigen Stelle, mit Markierung.
- **Favoriten und Verlauf** für Geräte, die man oft braucht.

## Woher die Daten kommen

Die App liefert **keine fremden PDFs mit**. Die Anleitungen sind urheberrechtlich geschützt und ändern
sich oft. Deshalb:

1. Der Katalog (`SHKAnleitungen/Resources/catalog.json`) enthält Hersteller, Serien und Typen.
2. Die PDFs kommen beim Öffnen direkt vom Hersteller oder aus der Websuche und sind dadurch aktuell.
3. Was du offline speicherst, bleibt nur auf deinem iPhone.

Den Katalog erweitern: `tools/build_catalog.py` bearbeiten (Hersteller und Serien stehen dort als Liste),
`CATALOG_UPDATED` hochsetzen und dann `python3 tools/build_catalog.py` ausführen.

Wenn das Repo öffentlich ist, lädt die App einen neueren Katalog beim Herunterziehen der Hersteller-Liste
von GitHub nach (`CatalogStore.remoteURL`). Ein App-Update ist dafür nicht nötig.

Bei einigen Herstellern sind die Fachpartner-Unterlagen nur nach Login erreichbar (z. B. Viessmann,
Buderus, Vaillant). Der App-Browser merkt sich die Anmeldung.

## App bauen und aufs iPhone bringen

Dafür brauchst du einen **Mac mit Xcode 16 oder neuer**. Das iPhone braucht iOS 17 oder neuer.

1. Ordner `shk-anleitungen` auf den Mac holen und `SHKAnleitungen.xcodeproj` öffnen.
2. Links das Projekt anklicken, dann **Signing & Capabilities**: unter *Team* deine Apple-ID wählen.
   Bei *Bundle Identifier* eine eigene Kennung eintragen, z. B. `de.deinname.shkanleitungen`.
3. iPhone per Kabel anschließen und oben als Ziel auswählen. Dann ▶︎ drücken.
4. Beim ersten Mal auf dem iPhone unter *Einstellungen → Allgemein → VPN & Geräteverwaltung* dem
   Entwickler vertrauen.

Mit einer kostenlosen Apple-ID läuft die App 7 Tage und muss dann neu installiert werden. Für TestFlight
und den App Store brauchst du das Apple Developer Program (99 €/Jahr).

## Aufbau

```
SHKAnleitungen/
  SHKAnleitungenApp.swift      Einstieg, Tabs, Navigation
  Models/Catalog.swift         Katalog-Datenmodell, Laden/Aktualisieren, Web-Suche
  Models/LibraryStore.swift    Offline-PDFs, Volltext-Index, Favoriten, Verlauf
  Search/SearchIndex.swift     Fehlertolerante Suche
  Views/                       Hersteller, Produktart, Produkt, Suche, Browser, PDF-Viewer, Offline, Favoriten
  Resources/catalog.json       erzeugt von tools/build_catalog.py
tools/build_catalog.py         Katalog-Quelle
```

Bei jedem Push baut GitHub Actions die App für den iOS-Simulator
(`.github/workflows/shk-anleitungen-ios.yml`), damit Fehler im Code sofort auffallen.
