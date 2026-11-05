#!/usr/bin/env python3
"""Erzeugt SHKAnleitungen/Resources/catalog.json.

Der Katalog enthält Hersteller, Produktarten und Produktserien. Die App lädt
keine fremden PDFs mit, sondern verlinkt auf die offiziellen Dokumenten-Portale
der Hersteller und baut gezielte Suchen (Hersteller + Serie + Modell +
Dokumentart). So bleiben die Anleitungen immer aktuell und es gibt keine
Urheberrechtsprobleme.

Neue Hersteller oder Serien einfach unten in MANUFACTURERS ergänzen und das
Skript erneut ausführen:

    python3 tools/build_catalog.py
"""
import json
import re
import sys
from pathlib import Path

# Bei Änderungen am Katalog hochsetzen, damit die App die neue Version erkennt.
CATALOG_UPDATED = "2026-11-06"

OUT = Path(__file__).resolve().parent.parent / "SHKAnleitungen" / "Resources" / "catalog.json"

# id, Anzeigename, SF-Symbol, Suchbegriffe (Synonyme)
CATEGORIES = [
    ("gas", "Gas-Heizung", "flame", ["gastherme", "therme", "brennwert", "gasbrennwert", "wandgerät", "kessel", "gaskessel"]),
    ("oel", "Öl-Heizung", "drop.fill", ["öl", "oel", "ölbrennwert", "ölkessel", "heizöl"]),
    ("wp", "Wärmepumpe", "fan", ["wärmepumpe", "wp", "luft-wasser", "sole-wasser", "erdwärme", "monoblock", "split", "inverter"]),
    ("holz", "Holz & Pellets", "leaf", ["pellet", "pellets", "holz", "scheitholz", "hackgut", "biomasse"]),
    ("brenner", "Brenner", "flame.fill", ["brenner", "ölbrenner", "gasbrenner", "gebläsebrenner", "zweistoff"]),
    ("regelung", "Regelung & Smart Home", "dial.medium", ["regler", "regelung", "thermostat", "bedienmodul", "app", "gateway", "smart home", "raumregler", "fernbedienung"]),
    ("speicher", "Speicher & Warmwasser", "cylinder", ["speicher", "warmwasser", "trinkwasser", "puffer", "pufferspeicher", "boiler", "frischwasser"]),
    ("solar", "Solarthermie", "sun.max", ["solar", "kollektor", "flachkollektor", "röhrenkollektor", "solarstation"]),
    ("lueftung", "Lüftung", "wind", ["lüftung", "wohnraumlüftung", "kwl", "wärmerückgewinnung", "lüftungsgerät"]),
    ("klima", "Klima", "snowflake", ["klima", "klimagerät", "klimaanlage", "kälte", "multisplit", "split"]),
    ("pumpe", "Pumpen & Hebeanlagen", "arrow.triangle.2.circlepath", ["pumpe", "umwälzpumpe", "heizungspumpe", "zirkulation", "hebeanlage", "druckerhöhung"]),
    ("armatur", "Armaturen & Ventile", "slider.horizontal.3", ["ventil", "thermostatventil", "strangregulierventil", "druckminderer", "filter", "rückspülfilter", "mischer", "hydraulischer abgleich"]),
    ("sanitaer", "Sanitär", "shower", ["sanitär", "wc", "spülkasten", "vorwand", "dusche", "armatur", "waschtisch", "unterputz", "installationssystem", "rohr"]),
    ("heizflaeche", "Heizkörper & Fußbodenheizung", "heater.vertical", ["heizkörper", "fußbodenheizung", "flächenheizung", "verteiler", "konvektor"]),
    ("elektro", "Elektro-Warmwasser", "bolt", ["durchlauferhitzer", "elektrospeicher", "kleinspeicher", "warmwasser elektrisch"]),
    ("wasser", "Wasseraufbereitung", "drop.triangle", ["enthärtung", "enthärtungsanlage", "wasserfilter", "rückspülfilter", "entkalkung", "leckageschutz", "wasserstop", "heizungswasser"]),
    ("druck", "Druckhaltung & Ausdehnung", "gauge.with.dots.needle.50percent", ["ausdehnungsgefäß", "mag", "membranausdehnungsgefäß", "druckhaltung", "entgasung", "vordruck", "nachspeisung"]),
]

# Jeder Hersteller: Gruppe, Kurzinfo, Webseite, Dokumenten-Portal (nur wenn
# bekannt), Domains für die Hersteller-Suche, Farbe, Serien.
# Serie: (Name, Kategorie, [Modelle/Typen], [zusätzliche Suchbegriffe])
MANUFACTURERS = [
    {
        "name": "Viessmann", "group": "Heiztechnik",
        "info": "Gas- und Öl-Brennwert, Wärmepumpen, Regelungen (Vitotronic, ViCare).",
        "website": "https://www.viessmann.de",
        "docPortal": "https://www.viessmann.de/de/services/bedienungsanleitungen.html",
        "docPortalNote": "Anleitungen als PDF in der ViBooks-Datenbank. Fachpartner-Unterlagen nach Login.",
        "domains": ["viessmann.de", "viessmann.com"], "color": "#FF4F00",
        "series": [
            ("Vitodens 050-W", "gas", ["B0HA", "B0KA"], []),
            ("Vitodens 100-W", "gas", ["B1HF", "B1KF", "B1HE", "B1KE"], []),
            ("Vitodens 111-W", "gas", ["B1LF", "B1LE"], ["kompakt", "speicher integriert"]),
            ("Vitodens 200-W", "gas", ["B2HF", "B2KF", "B2HE", "B2KE", "B2HA"], []),
            ("Vitodens 222-F", "gas", ["B2TF", "B2SF", "B2TE", "B2SE"], ["kompakt"]),
            ("Vitodens 222-W", "gas", ["B2LF", "B2LE"], []),
            ("Vitodens 300-W", "gas", ["B3HF", "B3HE", "B3HA"], []),
            ("Vitodens 333-F", "gas", ["B3TF", "B3SF", "B3TE"], []),
            ("Vitocrossal 100 / 200 / 300", "gas", ["CI1", "CU3A", "CR3B", "CM2"], ["gewerbe", "großkessel"]),
            ("Vitoladens 300-C / 300-T", "oel", ["J3RA", "VW3B"], []),
            ("Vitola 200", "oel", ["VB2A"], ["niedertemperatur"]),
            ("Vitocal 060-A", "wp", ["T0E", "T0S"], ["warmwasser-wärmepumpe"]),
            ("Vitocal 100-S / 111-S", "wp", ["AWB", "AWBT"], []),
            ("Vitocal 150-A / 151-A", "wp", ["AWO-M-E", "AWOT-M-E"], ["propan", "r290"]),
            ("Vitocal 200-S / 222-S", "wp", ["AWB-E", "AWBT-E"], []),
            ("Vitocal 250-A / 252-A", "wp", ["AWO-E-AC", "HAWO-AC", "AWOT-E-AC"], ["propan", "r290"]),
            ("Vitocal 250-S", "wp", ["AWB-AC"], []),
            ("Vitocal 300-G / 333-G", "wp", ["BW", "BWT", "BWC"], ["sole"]),
            ("Vitocal 262-A", "wp", ["T2E"], ["warmwasser-wärmepumpe"]),
            ("Vitoligno 300-C", "holz", ["VL3C"], ["pelletkessel"]),
            ("Vitotronic 100 / 200 / 300", "regelung", ["HC1B", "HO1B", "KO2B", "GW6B"], ["kesselregelung"]),
            ("Vitotrol 100 / 200 / 300", "regelung", ["UTDB", "200-E", "300-E"], ["raumthermostat", "fernbedienung"]),
            ("Vitoconnect / ViCare", "regelung", ["OPTO2", "OT2", "100"], ["wlan", "internet"]),
            ("Vitocell 100 / 300", "speicher", ["100-V", "100-W", "100-B", "100-E", "300-V", "300-B"], []),
            ("Vitosol 100 / 200 / 300", "solar", ["100-FM", "200-FM", "300-TM", "200-TM"], []),
            ("Vitovent 200 / 300", "lueftung", ["200-C", "200-W", "300-W", "300-F"], []),
        ],
    },
    {
        "name": "Wolf", "group": "Heiztechnik",
        "info": "Brennwerttechnik, Wärmepumpen, Wohnraumlüftung und Regelungen.",
        "website": "https://www.wolf.eu/de-de",
        "docPortal": "https://www.wolf.eu/de-de/professional/downloads",
        "docPortalNote": "Montage- und Bedienungsanleitungen im WOLF Downloadbereich für Fachpartner.",
        "domains": ["wolf.eu", "wolf-heiztechnik.de"], "color": "#D0021B",
        "series": [
            ("CGB-2 / CGB-2K", "gas", ["CGB-2-14", "CGB-2-20", "CGB-2-24", "CGB-2K-20", "CGB-2K-24"], ["kombitherme"]),
            ("FGB / FGB-K", "gas", ["FGB-24", "FGB-28", "FGB-35", "FGB-K-28", "FGB-K-35"], []),
            ("TGB-2", "gas", ["TGB-2-20", "TGB-2-24", "TGB-2-35"], []),
            ("CGS-2 / CGW-2 / CSZ-2", "gas", ["CGS-2", "CGW-2", "CSZ-2"], ["schichtenspeicher", "kompakt"]),
            ("MGK-2 / MGK-130", "gas", ["MGK-2-170", "MGK-2-250", "MGK-2-390", "MGK-2-630", "MGK-130"], ["gewerbe", "großkessel"]),
            ("COB-2 / TOB", "oel", ["COB-2-15", "COB-2-20", "COB-2-29", "TOB-18", "TOB-24"], ["ölbrennwert"]),
            ("CHA-Monoblock", "wp", ["CHA-07/400V", "CHA-10/400V", "CHA-16/400V"], ["propan", "r290"]),
            ("CHC-Monoblock / CHC-Split", "wp", ["CHC-Monoblock", "CHC-Split"], ["kompaktzentrale"]),
            ("FHA-Monoblock", "wp", ["FHA-05/06", "FHA-08/10", "FHA-11/14", "FHA-17/20"], []),
            ("BWL-1S / BWL-1 / BWS-1", "wp", ["BWL-1S-07", "BWL-1S-10", "BWL-1S-14", "BWL-1-08", "BWL-1-12", "BWS-1-06", "BWS-1-10"], ["split"]),
            ("WPM-1 / WPM-2 Wärmepumpenmanager", "regelung", ["WPM-1", "WPM-2"], []),
            ("Bedienmodul BM-2 / AM", "regelung", ["BM-2", "AM", "BM"], ["bedienmodul", "anzeigemodul"]),
            ("Mischermodul MM-2 / Kaskadenmodul KM-2", "regelung", ["MM-2", "KM-2", "KM"], ["mischer", "kaskade"]),
            ("Solarmodul SM1-2 / SM2-2", "regelung", ["SM1-2", "SM2-2"], ["solarregler"]),
            ("WOLF Link / ISM7", "regelung", ["WOLF Link home", "WOLF Link pro", "ISM7i", "ISM7e"], ["smartset", "lan", "wlan", "app"]),
            ("SEW / SEM / BSP Speicher", "speicher", ["SEW-1", "SEW-2", "SEM-1", "SEM-2", "BSP", "SPU-2"], ["pufferspeicher"]),
            ("CRK-12 / TopSon F3-1 / CFK-1", "solar", ["CRK-12", "TopSon F3-1", "CFK-1"], []),
            ("CWL Excellent / CWL-2", "lueftung", ["CWL-180", "CWL-300", "CWL-400", "CWL-2-225", "CWL-2-325", "CWL-2-400"], ["wohnraumlüftung"]),
            ("CWL-F / CWL-D", "lueftung", ["CWL-F-150", "CWL-F-300", "CWL-D-70"], ["dezentral"]),
            ("CFL WT / KG Top", "lueftung", ["CFL-WT", "KG Top"], ["klimagerät", "rlt"]),
        ],
    },
    {
        "name": "Weishaupt", "group": "Heiztechnik",
        "info": "Öl- und Gasbrenner, Brennwertkessel Thermo Condens, Wärmepumpen.",
        "website": "https://www.weishaupt.de",
        "docPortal": "https://www.weishaupt.de/suche",
        "docPortalNote": "Dokumente über die Suche auf weishaupt.de. Nach exakter Typbezeichnung vom Typenschild suchen.",
        "domains": ["weishaupt.de", "weishaupt.ch", "weishaupt.at"], "color": "#E2001A",
        "series": [
            ("Ölbrenner WL5 / WL10 / WL20 / WL30", "brenner", ["WL5/1-B", "WL5-PB-H", "WL10/2-D", "WL20", "WL30"], ["purflam"]),
            ("Gasbrenner WG5 / WG10 / WG20 / WG30 / WG40", "brenner", ["WG5/1-A", "WG10", "WG20", "WG30", "WG40/1-A"], ["ln", "low nox"]),
            ("monarch WM-L / WM-G / WM-GL", "brenner", ["WM-L10", "WM-L20", "WM-G10", "WM-G20", "WM-GL10", "WM-GL20"], ["zweistoffbrenner", "industrie"]),
            ("Thermo Condens WTC-GW", "gas", ["WTC-GW 15-B", "WTC-GW 25-B", "WTC-GW 32-B"], ["gas-brennwert"]),
            ("Thermo Condens WTC-GB", "gas", ["WTC-GB 60-A", "WTC-GB 90-A", "WTC-GB 120-A", "WTC-GB 170-A", "WTC-GB 250-A", "WTC-GB 300-A"], ["bodenstehend"]),
            ("Thermo Condens WTC-OB", "oel", ["WTC-OB 15-A", "WTC-OB 25-A", "WTC-OB 35-A"], ["öl-brennwert"]),
            ("Luft/Wasser-Wärmepumpen WWP L / WBB", "wp", ["WWP L 26 I-2", "WWP LB", "WBB 12", "WBB 20"], ["biblock"]),
            ("Sole/Wasser-Wärmepumpen WWP S", "wp", ["WWP S 10 ID", "WWP S 15 ID", "WWP S 18 ID"], []),
            ("Wärmepumpen WWP T", "wp", ["WWP T 290 F", "WWP T 290 FW2A"], ["warmwasser-wärmepumpe"]),
            ("Wärmetauscher-Speicher WTU", "speicher", ["WTU 20-S", "WTU 30-S", "WTU 50-S", "WTU 55-S"], []),
            ("Regelung WCM / WEM", "regelung", ["WCM-CPU", "WCM-FS", "WCM-EM", "WEM-EM-HK", "WEM-EM-WW"], ["fernbedienstation", "erweiterungsmodul"]),
            ("Speicher WAS / WAS Sol", "speicher", ["WAS 70 Bloc-Eco", "WAS 150", "WAS 200", "WAS Sol 400"], []),
            ("Solarkollektoren WTS-F", "solar", ["WTS-F2"], []),
        ],
    },
    {
        "name": "Buderus", "group": "Heiztechnik",
        "info": "Logamax, Logano, Logatherm, Logamatic – Teil von Bosch Home Comfort.",
        "website": "https://www.buderus.de",
        "docPortal": None, "docPortalNote": "Fachkunden-Unterlagen nach Login auf buderus.de.",
        "domains": ["buderus.de", "bosch-homecomfort.com"], "color": "#003B6F",
        "series": [
            ("Logamax plus GB172i / GB182i / GB192i", "gas", ["GB172i", "GB172i.2", "GB182i", "GB182i.2", "GB192i", "GB192i.2"], ["wandgerät"]),
            ("Logamax plus GB162 / GB062", "gas", ["GB162-50", "GB162-85", "GB162-100", "GB062"], []),
            ("Logano plus KB192i / KB195i", "gas", ["KB192i", "KB192i.2", "KB195i"], ["bodenstehend"]),
            ("Logano plus GB125 / G125", "oel", ["GB125", "G125", "GB145"], []),
            ("Logatherm WLW196i / WLW186i / WLW176i", "wp", ["WLW196i AR", "WLW196i IR", "WLW186i AR", "WLW176i AR"], ["luft-wasser"]),
            ("Logatherm WSW196i / WSW186i", "wp", ["WSW196i", "WSW186i"], ["sole"]),
            ("Logatherm WPL AR / WPS", "wp", ["WPL 7 AR", "WPL 10 AR", "WPS 6", "WPS 10"], []),
            ("Logamatic RC310 / RC220 / RC200 / RC100", "regelung", ["RC310", "RC220", "RC200", "RC100", "BC400"], ["bedieneinheit", "ems plus"]),
            ("Logamatic HMC300 / BC10 / MC110", "regelung", ["HMC300", "BC10", "MC110", "MM100", "SM100"], ["kesselregelung"]),
            ("Logamatic 5000 / 4000", "regelung", ["5311", "5313", "4323"], ["gewerbe"]),
            ("MX300 Gateway / MyDevice App", "regelung", ["MX300", "MX400", "KM200"], ["internet", "app"]),
            ("Logalux SU / SM / PNR / L", "speicher", ["SU160", "SU200", "SU300/5", "SM300", "SM400", "PNR500", "L135"], []),
            ("Logasol SKN / SKT", "solar", ["SKN4.0", "SKT1.0"], []),
            ("Logavent HRV", "lueftung", ["HRV156", "HRV176"], []),
        ],
    },
    {
        "name": "Vaillant", "group": "Heiztechnik",
        "info": "ecoTEC, aroTHERM, flexoTHERM, sensoCOMFORT und Warmwassertechnik.",
        "website": "https://www.vaillant.de",
        "docPortal": None, "docPortalNote": "Dokumente auf vaillant.de und im FachpartnerNET.",
        "domains": ["vaillant.de", "vaillant.com"], "color": "#00917E",
        "series": [
            ("ecoTEC plus", "gas", ["VC 15CS/1-5", "VC 20CS/1-5", "VC 25CS/1-5", "VCW 26CS/1-5", "VC 206/5-5"], ["kombitherme"]),
            ("ecoTEC pure / exclusive", "gas", ["VCW 236/7-2", "VC 20CS/1-7", "VC 30CS/1-7"], []),
            ("ecoCOMPACT", "gas", ["VSC 206/4-5", "VSC 266/4-5"], ["kompakt"]),
            ("ecoVIT exclusiv / ecoCRAFT exclusiv", "gas", ["VKK 226/4", "VKK 286/4", "VKK 806/3-E"], ["bodenstehend", "gewerbe"]),
            ("icoVIT exclusiv", "oel", ["VKO 246/3-7", "VKO 356/3-7"], []),
            ("aroTHERM plus", "wp", ["VWL 35/6 A", "VWL 55/6 A", "VWL 75/6 A", "VWL 105/6 A", "VWL 125/6 A"], ["propan", "r290", "monoblock"]),
            ("aroTHERM Split / Split plus", "wp", ["VWL 55/5 AS", "VWL 75/5 AS", "VWL 125/5 AS"], ["split"]),
            ("flexoTHERM exclusive / flexoCOMPACT exclusive", "wp", ["VWF 57/4", "VWF 87/4", "VWF 117/4", "VWF 88/4"], ["sole"]),
            ("uniTOWER / Hydraulikstation", "wp", ["VWL 58/5 IS", "VWL 77/5 IS", "VWZ MEH 97/6"], []),
            ("sensoCOMFORT VRC 720", "regelung", ["VRC 720", "VRC 720f", "VR 70", "VR 71"], ["systemregler"]),
            ("multiMATIC VRC 700 / calorMATIC", "regelung", ["VRC 700", "VRC 470", "VRT 350", "VRT 370"], []),
            ("sensoHOME / VRT 380", "regelung", ["VRT 380", "VRT 380f"], ["raumthermostat"]),
            ("myVAILLANT connect / VR 920 / VR 940", "regelung", ["VR 920", "VR 921", "VR 940f"], ["internet", "app"]),
            ("uniSTOR / allSTOR / auroSTOR", "speicher", ["VIH R 200", "VIH R 300", "VPS 500", "VIH S 300"], ["pufferspeicher"]),
            ("auroTHERM", "solar", ["VFK 145", "VFK 155", "VTK 1140"], []),
            ("recoVAIR", "lueftung", ["VAR 260/4", "VAR 360/4"], []),
            ("electronicVED / miniVED", "elektro", ["VED E 18/8", "VED E 21/8", "VED H 3/3"], ["durchlauferhitzer"]),
        ],
    },
    {
        "name": "Bosch / Junkers", "group": "Heiztechnik",
        "info": "Condens, Compress, Cerapur und Regler (früher Junkers).",
        "website": "https://www.bosch-homecomfort.com/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["bosch-homecomfort.com", "junkers.com"], "color": "#ED0007",
        "series": [
            ("Condens 9000i W / 7000i W", "gas", ["GC9000iW", "GC7000iW", "GC7000iWT"], []),
            ("Condens 5300i WM / 2300i W", "gas", ["GC5300iWM", "GC2300iW"], []),
            ("Cerapur / Ceraclass / Cerastar", "gas", ["ZSB", "ZWB", "ZSR", "ZWR", "ZSC", "ZWC"], ["junkers"]),
            ("Compress 7400i AW / 6800i AW", "wp", ["CS7400iAW", "CS6800iAW"], ["luft-wasser"]),
            ("Compress 5800i AW / 3400i AWS", "wp", ["CS5800iAW", "CS3400iAWS"], []),
            ("Compress 7000 / 6000 LW", "wp", ["CS7001iAW", "CS6000AW"], []),
            ("Regler CW 400 / CR 400 / CR 100 / CR 10", "regelung", ["CW400", "CW100", "CR400", "CR100", "CR10"], ["ems plus"]),
            ("EasyControl / MX300", "regelung", ["CT200", "MX300", "MB LAN 2"], ["app", "smart home"]),
            ("Tronic Heat 3500 / 3000", "elektro", ["TH3500", "TH3000"], ["elektroheizkessel"]),
        ],
    },
    {
        "name": "Brötje", "group": "Heiztechnik",
        "info": "Gas-Brennwert, Wärmepumpen und ISR-Regelung für das Fachhandwerk.",
        "website": "https://www.broetje.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["broetje.de"], "color": "#E30613",
        "series": [
            ("WGB EVO / WGB Pro EVO", "gas", ["WGB 15 I", "WGB 20 I", "WGB 28 I", "WGB-K 20 I", "WGB Pro 50"], []),
            ("EcoTherm Plus / EcoCondens", "gas", ["WGB 50", "BBS EVO", "BBK EVO"], []),
            ("BLW NEO / BLW Split K", "wp", ["BLW NEO 8", "BLW NEO 12", "BLW Split K 8"], []),
            ("SensoTherm BLW / BSW", "wp", ["BLW Sen", "BSW NEO"], []),
            ("ISR Plus / IDA", "regelung", ["ISR Plus", "IDA", "RGT", "QAA75"], ["isr"]),
        ],
    },
    {
        "name": "Remeha", "group": "Heiztechnik",
        "info": "Gas-Brennwert (Tzerra, Calenta, Quinta) und Regelung iSense/eTwist.",
        "website": "https://www.remeha.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["remeha.de", "remeha.com"], "color": "#E3000F",
        "series": [
            ("Tzerra Ace / Calenta Ace", "gas", ["Tzerra Ace 24", "Calenta Ace 28", "Calenta Ace 40C"], []),
            ("Quinta Ace", "gas", ["Quinta Ace 45", "Quinta Ace 65", "Quinta Ace 115", "Quinta Ace 160"], ["gewerbe"]),
            ("Gas 220 Ace / Gas 320/620 Ace", "gas", ["Gas 220 Ace", "Gas 320 Ace", "Gas 620 Ace"], ["bodenstehend"]),
            ("Mercuria Ace / Elga Ace", "wp", ["Mercuria Ace", "Elga Ace"], ["hybrid"]),
            ("eTwist / iSense", "regelung", ["eTwist", "iSense", "SCB-10"], []),
        ],
    },
    {
        "name": "Elco", "group": "Heiztechnik",
        "info": "Thision-Brennwertgeräte, Brenner Vectron, Wärmepumpen Aerotop.",
        "website": "https://www.elco.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["elco.de", "elco.net"], "color": "#E2001A",
        "series": [
            ("Thision S Plus / Thision Mini", "gas", ["Thision S Plus 13", "Thision S Plus 19", "Thision Mini"], []),
            ("Straton / Trigon", "gas", ["Straton XL", "Trigon XL"], ["gewerbe"]),
            ("Vectron Öl- und Gasbrenner", "brenner", ["VL 1", "VL 2", "VG 1", "VG 2", "EK"], []),
            ("Aerotop", "wp", ["Aerotop T", "Aerotop S", "Aerotop SX"], []),
            ("Remocon", "regelung", ["Remocon Net", "Remocon Plus"], []),
        ],
    },
    {
        "name": "Hoval", "group": "Heiztechnik",
        "info": "UltraGas, Belaria, Thermalia und Regelung TopTronic E.",
        "website": "https://www.hoval.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["hoval.de", "hoval.com"], "color": "#E3000F",
        "series": [
            ("UltraGas / TopGas", "gas", ["UltraGas 15", "UltraGas 2 (100)", "TopGas comfort"], []),
            ("UltraOil", "oel", ["UltraOil 16", "UltraOil 25", "UltraOil 35"], []),
            ("Belaria pro / Belaria compact", "wp", ["Belaria pro comfort", "Belaria compact IR"], ["luft-wasser"]),
            ("Thermalia", "wp", ["Thermalia comfort", "Thermalia dual"], ["sole"]),
            ("TopTronic E", "regelung", ["TopTronic E", "HovalConnect"], []),
            ("CombiVal / EnerVal", "speicher", ["CombiVal ER", "CombiVal CR", "EnerVal"], []),
            ("HomeVent", "lueftung", ["HomeVent comfort FR"], []),
        ],
    },
    {
        "name": "Stiebel Eltron", "group": "Wärmepumpen & Klima",
        "info": "Wärmepumpen, Lüftung und Elektro-Warmwasser.",
        "website": "https://www.stiebel-eltron.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["stiebel-eltron.de", "stiebel-eltron.com"], "color": "#E30613",
        "series": [
            ("WPL-A / WPL 25 / HPA-O", "wp", ["WPL-A 05 HK", "WPL-A 07 HK", "WPL 25 A", "HPA-O 13 CS Premium"], ["luft-wasser"]),
            ("WPE-I / WPF / WPC", "wp", ["WPE-I 04 H", "WPF 10", "WPC 10"], ["sole"]),
            ("LWZ / WWK", "wp", ["LWZ 5 S", "LWZ 8 CS", "WWK 300 electronic"], ["integralgerät", "warmwasser-wärmepumpe"]),
            ("WPM / ISG", "regelung", ["WPM", "ISG web", "ISG plus"], ["wärmepumpenmanager", "internet"]),
            ("DHE / DHB / DCE", "elektro", ["DHE Connect", "DHB-E", "DCE-X"], ["durchlauferhitzer"]),
            ("SHZ / PSH / SNU", "elektro", ["SHZ 100 LCD", "PSH 80 Classic", "SNU 5 SL"], ["elektrospeicher"]),
            ("VLR / LWZ Lüftung", "lueftung", ["VLR 70 L Trend", "LWZ 280"], []),
        ],
    },
    {
        "name": "Daikin", "group": "Wärmepumpen & Klima",
        "info": "Altherma-Wärmepumpen und Klimageräte.",
        "website": "https://www.daikin.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["daikin.de", "daikin.eu"], "color": "#0097E0",
        "series": [
            ("Altherma 3 R / 3 H HT", "wp", ["ERGA-EV", "EHVH", "EPRA-ETV", "ERRA"], []),
            ("Altherma 3 M / 3 GEO", "wp", ["EBLA", "EDLA", "EGSAH"], ["monoblock", "sole"]),
            ("Altherma ROTEX HPSU", "wp", ["HPSU compact", "HPU hybrid"], ["rotex"]),
            ("Klimageräte Perfera / Stylish / Emura", "klima", ["FTXM", "FTXA", "FTXJ", "FTXTM"], []),
            ("Sensira / Comfora", "klima", ["FTXF", "FTXP"], []),
            ("Madoka / Daikin Onecta", "regelung", ["BRC1H", "Onecta"], ["fernbedienung"]),
        ],
    },
    {
        "name": "Mitsubishi Electric", "group": "Wärmepumpen & Klima",
        "info": "Ecodan-Wärmepumpen und Klimageräte.",
        "website": "https://www.mitsubishi-les.com/de-de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["mitsubishi-les.com"], "color": "#E60012",
        "series": [
            ("Ecodan Monoblock / Split", "wp", ["PUZ-WM", "PUD-SHWM", "SUZ-SWM", "ERST20D"], []),
            ("Klimageräte MSZ", "klima", ["MSZ-AP", "MSZ-LN", "MSZ-EF", "MSZ-HR"], []),
            ("MELCloud", "regelung", ["MAC-567IF", "MELCloud"], ["wlan"]),
        ],
    },
    {
        "name": "Panasonic", "group": "Wärmepumpen & Klima",
        "info": "Aquarea-Wärmepumpen und Etherea-Klimageräte.",
        "website": "https://www.aircon.panasonic.eu/DE_de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["aircon.panasonic.eu", "panasonic.com"], "color": "#0041C0",
        "series": [
            ("Aquarea Generation J / K / L", "wp", ["WH-MDC", "WH-MXC", "WH-ADC", "WH-SDC"], []),
            ("Etherea / TZ", "klima", ["CS-Z", "CS-TZ"], []),
        ],
    },
    {
        "name": "NIBE", "group": "Wärmepumpen & Klima",
        "info": "Luft- und Erdwärmepumpen aus Schweden.",
        "website": "https://www.nibe.eu/de-de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["nibe.eu", "nibe.de"], "color": "#E2001A",
        "series": [
            ("F2120 / S2125", "wp", ["F2120-8", "F2120-12", "S2125-8", "S2125-12"], ["luft-wasser"]),
            ("F1255 / S1155 / S1255", "wp", ["F1255-6", "S1155-6", "S1255-6"], ["sole"]),
            ("SMO S40 / VVM S320", "regelung", ["SMO S40", "VVM S320", "SMO 20"], ["myuplink"]),
            ("F750 / S735", "wp", ["F750", "S735"], ["abluft"]),
        ],
    },
    {
        "name": "Fröling", "group": "Holz & Pellets",
        "info": "Pellet-, Scheitholz- und Hackgutkessel.",
        "website": "https://www.froeling.com/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["froeling.com"], "color": "#C8102E",
        "series": [
            ("PE1 Pellet / PE1c", "holz", ["PE1 Pellet 15", "PE1 Pellet 25", "PE1c Pellet"], []),
            ("S4 Turbo / S3 Turbo", "holz", ["S4 Turbo 22", "S4 Turbo 28", "S3 Turbo"], ["scheitholz"]),
            ("SP Dual / T4e", "holz", ["SP Dual", "T4e"], ["kombikessel", "hackgut"]),
            ("Lambdatronic / froeling-connect", "regelung", ["Lambdatronic P 3200", "Lambdatronic H 3200"], []),
        ],
    },
    {
        "name": "ÖkoFEN", "group": "Holz & Pellets",
        "info": "Pelletheizungen Pellematic.",
        "website": "https://www.oekofen.com/de-de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["oekofen.com"], "color": "#6AB023",
        "series": [
            ("Pellematic Condens / Smart XS", "holz", ["Pellematic Condens", "Pellematic Smart XS", "Pellematic Compact"], []),
            ("Pelletronic Touch", "regelung", ["Pelletronic Touch", "Pelletronic Touch 4"], []),
        ],
    },
    {
        "name": "Windhager", "group": "Holz & Pellets",
        "info": "BioWIN, PuroWIN und LogWIN.",
        "website": "https://www.windhager.com/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["windhager.com"], "color": "#B2001E",
        "series": [
            ("BioWIN 2 / BioWIN XL", "holz", ["BioWIN 2 Touch", "BioWIN XL"], ["pellet"]),
            ("PuroWIN / LogWIN", "holz", ["PuroWIN", "LogWIN Premium"], ["scheitholz"]),
        ],
    },
    {
        "name": "Grundfos", "group": "Pumpen & Armaturen",
        "info": "Umwälz-, Zirkulations- und Druckerhöhungspumpen, Hebeanlagen.",
        "website": "https://www.grundfos.com/de",
        "docPortal": "https://product-selection.grundfos.com/de",
        "docPortalNote": "Im Grundfos Product Center gibt es Datenblätter und Anleitungen zu jedem Pumpentyp.",
        "domains": ["grundfos.com"], "color": "#11497B",
        "series": [
            ("ALPHA1 / ALPHA2 / ALPHA3", "pumpe", ["ALPHA1 L 25-60", "ALPHA2 25-60", "ALPHA3 25-40"], ["heizungspumpe", "hocheffizienz"]),
            ("COMFORT PM / UP", "pumpe", ["UP 15-14 B PM", "COMFORT 15-14 BX PM"], ["zirkulationspumpe"]),
            ("MAGNA1 / MAGNA3 / UPS", "pumpe", ["MAGNA3 32-80", "MAGNA1 25-60", "UPS 25-60"], []),
            ("SCALA2 / CM / CR", "pumpe", ["SCALA2 3-45", "CM 3-5", "CR 5-8"], ["druckerhöhung", "hauswasserwerk"]),
            ("Sololift2 / Unilift / Multilift", "pumpe", ["Sololift2 WC-1", "Sololift2 C-3", "Unilift KP 250", "Multilift MSS"], ["hebeanlage", "schmutzwasser"]),
            ("SQ / SP Brunnenpumpen", "pumpe", ["SQ 3-65", "SP 5A"], ["brunnen"]),
        ],
    },
    {
        "name": "Wilo", "group": "Pumpen & Armaturen",
        "info": "Hocheffizienzpumpen, Zirkulation und Hebeanlagen.",
        "website": "https://wilo.com/de/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["wilo.com"], "color": "#009C82",
        "series": [
            ("Yonos PICO / Para", "pumpe", ["Yonos PICO 25/1-6", "Yonos PICO plus", "Para 25/1-8"], ["heizungspumpe"]),
            ("Stratos MAXO / Stratos PICO", "pumpe", ["Stratos MAXO 30/0,5-8", "Stratos PICO 25/1-6"], []),
            ("Star-Z NOVA / Varios PICO", "pumpe", ["Star-Z NOVA", "Star-Z NOVA C", "Varios PICO-STG"], ["zirkulationspumpe"]),
            ("HiDrainlift / DrainLift", "pumpe", ["HiDrainlift 3-35", "DrainLift S", "DrainLift Con"], ["hebeanlage"]),
            ("Wilo-Medana / Helix", "pumpe", ["Medana CH1-L", "Helix V"], ["druckerhöhung"]),
        ],
    },
    {
        "name": "Oventrop", "group": "Pumpen & Armaturen",
        "info": "Thermostatventile, Strangregulierung, Trinkwasser- und Solarstationen.",
        "website": "https://www.oventrop.com/de-DE",
        "docPortal": None, "docPortalNote": None,
        "domains": ["oventrop.com"], "color": "#E2001A",
        "series": [
            ("Thermostatköpfe Uni / Ventileinsätze", "armatur", ["Uni SH", "Uni LH", "Uni XH", "AV9", "Baureihe AV6"], ["thermostatkopf"]),
            ("Multiflex F / Multiblock T", "armatur", ["Multiflex F", "Multiblock T", "Multiblock TQ"], ["heizkörperanschluss"]),
            ("Hydrocontrol / Cocon", "armatur", ["Hydrocontrol VTR", "Cocon QTZ", "Aquastrom T plus"], ["strangregulierventil", "abgleich"]),
            ("Regusol / Regumaq", "speicher", ["Regusol X-Duo", "Regumaq X-30", "Regumaq XZ-30"], ["solarstation", "frischwasserstation"]),
            ("Multidis / Unibox", "heizflaeche", ["Multidis SF", "Unibox E RTL"], ["fbh-verteiler"]),
        ],
    },
    {
        "name": "Danfoss", "group": "Pumpen & Armaturen",
        "info": "Thermostatventile, Differenzdruckregler und Raumregler.",
        "website": "https://www.danfoss.com/de-de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["danfoss.com"], "color": "#E2000F",
        "series": [
            ("Thermostatventile RA-N / RA-UN / RLV", "armatur", ["RA-N", "RA-UN", "RLV-S", "RAS-C2", "RA 2000"], ["thermostatkopf"]),
            ("AB-QM / ASV-PV", "armatur", ["AB-QM", "ASV-PV", "ASV-BD", "MSV-BD"], ["differenzdruckregler", "abgleich"]),
            ("Danfoss Ally / Icon", "regelung", ["Ally eTRV", "Icon2", "Icon Raumthermostat"], ["smart home", "fußbodenheizung"]),
            ("ECL Comfort", "regelung", ["ECL Comfort 110", "ECL Comfort 210", "ECL Comfort 310"], ["fernwärme"]),
        ],
    },
    {
        "name": "Resideo (Honeywell Home)", "group": "Pumpen & Armaturen",
        "info": "Braukmann-Armaturen, Filter, Druckminderer, evohome.",
        "website": "https://www.resideo.com/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["resideo.com", "homecomfort.resideo.com"], "color": "#1C4E9D",
        "series": [
            ("Druckminderer D06F / D04FM", "armatur", ["D06F", "D04FM", "D05FS"], ["braukmann"]),
            ("Filter FF06 / F76S / FK06", "armatur", ["FF06", "F76S", "FK06", "HS10S"], ["rückspülfilter", "filterkombination"]),
            ("Systemtrenner / Heizungsfüllung", "armatur", ["BA295", "NK300", "VF06"], ["füllkombination"]),
            ("evohome / Lyric", "regelung", ["evohome", "Lyric T6", "HR92"], ["smart home"]),
        ],
    },
    {
        "name": "Geberit", "group": "Sanitär",
        "info": "Vorwand-, Spül- und Rohrleitungssysteme, AquaClean.",
        "website": "https://www.geberit.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["geberit.de", "geberit.com"], "color": "#005CA9",
        "series": [
            ("Duofix / GIS", "sanitaer", ["Duofix WC 112 cm", "Duofix UP320", "GIS"], ["vorwand", "montageelement"]),
            ("Sigma / Omega / Delta Spülkästen", "sanitaer", ["Sigma UP320", "Omega UP300", "Delta UP100", "Sigma01", "Sigma20"], ["betätigungsplatte", "spülkasten"]),
            ("Monolith", "sanitaer", ["Monolith Plus", "Monolith 101 cm"], ["sanitärmodul"]),
            ("AquaClean", "sanitaer", ["AquaClean Mera", "AquaClean Sela", "AquaClean Tuma", "AquaClean Alba"], ["dusch-wc"]),
            ("Mapress / Mepla / PushFit", "sanitaer", ["Mapress Edelstahl", "Mapress C-Stahl", "Mepla", "FlowFit", "PushFit"], ["pressfitting", "rohrsystem"]),
            ("Silent / PE Entwässerung", "sanitaer", ["Silent-db20", "Silent-PP", "Geberit PE"], ["abwasser"]),
        ],
    },
    {
        "name": "Grohe", "group": "Sanitär",
        "info": "Armaturen, Unterputzsysteme Rapido/Rapid SL, Grohe Blue.",
        "website": "https://www.grohe.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["grohe.de", "grohe.com"], "color": "#14365D",
        "series": [
            ("Rapid SL / Rapido SmartBox", "sanitaer", ["Rapid SL 38528", "Rapido SmartBox 35600"], ["unterputz", "vorwand"]),
            ("Grohtherm / SmartControl", "sanitaer", ["Grohtherm 800", "Grohtherm 1000", "Grohtherm SmartControl"], ["thermostat", "dusche"]),
            ("Eurosmart / Essence / Eurostyle", "sanitaer", ["Eurosmart", "Essence", "Eurostyle"], ["waschtisch"]),
            ("GROHE Blue / Red", "sanitaer", ["Blue Home", "Blue Professional", "Red Duo"], ["sprudel", "kochend"]),
            ("Sense Guard", "armatur", ["Sense Guard", "Sense"], ["leckage", "wasserschutz"]),
        ],
    },
    {
        "name": "hansgrohe", "group": "Sanitär",
        "info": "Armaturen, Brausen, iBox universal.",
        "website": "https://www.hansgrohe.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["hansgrohe.de", "hansgrohe.com"], "color": "#000000",
        "series": [
            ("iBox universal / ShowerSelect", "sanitaer", ["iBox universal 2", "ShowerSelect", "ShowerSelect Comfort"], ["unterputz"]),
            ("Raindance / Croma / Pulsify", "sanitaer", ["Raindance Select", "Croma Select", "Pulsify"], ["brause", "showerpipe"]),
            ("Talis / Logis / Focus", "sanitaer", ["Talis E", "Talis S", "Logis", "Focus"], ["waschtisch"]),
        ],
    },
    {
        "name": "Kermi", "group": "Heizkörper & Lüftung",
        "info": "Heizkörper, Flächenheizung, x-change Wärmepumpen, Duschkabinen.",
        "website": "https://www.kermi.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["kermi.de", "kermi.com"], "color": "#E30613",
        "series": [
            ("therm-x2 Profil / Plan", "heizflaeche", ["FK0", "FTV", "PTV", "therm-x2 Profil-V"], ["flachheizkörper"]),
            ("x-net Flächenheizung", "heizflaeche", ["x-net C12", "x-net Verteiler"], ["fußbodenheizung"]),
            ("x-change dynamic", "wp", ["x-change dynamic pro", "x-change dynamic AC"], []),
            ("x-well Lüftung", "lueftung", ["x-well D12", "x-well S150"], []),
            ("x-center x-buffer / x-change", "speicher", ["x-buffer", "x-center"], []),
        ],
    },
    {
        "name": "Zehnder", "group": "Heizkörper & Lüftung",
        "info": "Komfortlüftung ComfoAir, Design-Heizkörper.",
        "website": "https://www.zehnder-systems.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["zehnder-systems.de", "zehnder-systems.com"], "color": "#E2001A",
        "series": [
            ("ComfoAir Q / ComfoAir E / ComfoAir Flex", "lueftung", ["ComfoAir Q350", "ComfoAir Q450", "ComfoAir Q600", "ComfoAir E300", "ComfoAir Flex"], ["kwl"]),
            ("ComfoConnect / ComfoControl", "regelung", ["ComfoConnect LAN C", "ComfoSense C"], []),
            ("Charleston / Yucca / Subway", "heizflaeche", ["Charleston", "Yucca", "Subway"], ["designheizkörper", "badheizkörper"]),
        ],
    },
    # ---- Erweiterung 2 ----
    {
        "name": "ATAG", "group": "Heiztechnik",
        "info": "Gas-Brennwertgeräte i-Serie und Q-Serie.",
        "website": "https://www.atag-heiztechnik.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["atag-heiztechnik.de", "atagheating.com"], "color": "#E30613",
        "series": [
            ("i-Serie", "gas", ["i24C", "i28C", "i36C", "i22S", "i32S"], ["kombitherme"]),
            ("Q-Serie / XL-Serie", "gas", ["Q25S", "Q38S", "Q51S", "XL50", "XL100"], ["gewerbe"]),
            ("ATAG One / Brainz", "regelung", ["ATAG One", "Brainz"], ["raumregler", "app"]),
        ],
    },
    {
        "name": "alpha innotec", "group": "Wärmepumpen & Klima",
        "info": "Luft- und Sole-Wärmepumpen mit Luxtronik-Regelung.",
        "website": "https://www.alpha-innotec.com/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["alpha-innotec.com", "alpha-innotec.de"], "color": "#E2001A",
        "series": [
            ("alira LWAV / LWDV", "wp", ["LWAV 82R1/3", "LWAV 122R3", "LWDV 91-1/3", "LWDV 121-1/3"], ["split", "luft-wasser"]),
            ("LWD / LWCV", "wp", ["LWD 50A", "LWD 70A", "LWCV 82R1/3"], ["monoblock"]),
            ("SWC / WZSV", "wp", ["SWC 62H3", "SWC 102H3", "WZSV 62H3M", "WZSV 92K3M"], ["sole", "kompakt"]),
            ("Luxtronik 2.1", "regelung", ["Luxtronik 2.1", "Luxtronik 2.0"], ["wärmepumpenregler", "heatpump24"]),
        ],
    },
    {
        "name": "iDM", "group": "Wärmepumpen & Klima",
        "info": "Wärmepumpen AERO und TERRA aus Österreich.",
        "website": "https://www.idm-energie.at/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["idm-energie.at", "idm-energie.de"], "color": "#E30613",
        "series": [
            ("AERO SLM / AERO ALM", "wp", ["AERO SLM 3-11", "AERO SLM 6-17", "AERO ALM 4-12"], ["luft-wasser"]),
            ("TERRA SW Max / TERRA SW Complete", "wp", ["TERRA SW 8 Max", "TERRA SW 13 Max", "TERRA SW Complete"], ["sole"]),
            ("Navigator 2.0 / 10.0", "regelung", ["Navigator 2.0", "Navigator 10.0", "myiDM"], []),
        ],
    },
    {
        "name": "Ochsner", "group": "Wärmepumpen & Klima",
        "info": "Wärmepumpen AIR Eagle, AIR Hawk und Erdreich-Wärmepumpen.",
        "website": "https://www.ochsner.com/de-de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["ochsner.com"], "color": "#005A9C",
        "series": [
            ("AIR Eagle / AIR Hawk", "wp", ["AIR EAGLE 314 C11A", "AIR HAWK 518 C11A", "AIR HAWK 208 C11A"], ["luft-wasser"]),
            ("GMSW / Terra", "wp", ["GMSW 10 plus", "GMSW 15 HK"], ["sole"]),
            ("OTE Regelung", "regelung", ["OTE 3", "OTE Web"], []),
        ],
    },
    {
        "name": "Hargassner", "group": "Holz & Pellets",
        "info": "Pellet-, Hackgut- und Scheitholzkessel.",
        "website": "https://www.hargassner.com/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["hargassner.com"], "color": "#CC0000",
        "series": [
            ("Nano-PK / Eco-PK", "holz", ["Nano-PK 6-32", "Eco-PK 45-120"], ["pellet"]),
            ("Neo-HV / HV-Lambda", "holz", ["Neo-HV 20", "Neo-HV 30", "Neo-HV 40"], ["scheitholz"]),
            ("ECO-HK / Magic", "holz", ["ECO-HK 20-60", "Magic HK"], ["hackgut"]),
        ],
    },
    {
        "name": "KWB", "group": "Holz & Pellets",
        "info": "Pellet-, Hackgut- und Kombikessel.",
        "website": "https://www.kwb.net/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["kwb.net"], "color": "#008C45",
        "series": [
            ("easyfire / Pelletfire Plus", "holz", ["easyfire 2", "easyfire 3", "Pelletfire Plus"], ["pellet"]),
            ("multifire / combifire", "holz", ["multifire MF2", "combifire CF2"], ["hackgut", "kombikessel"]),
            ("Comfort 4 Regelung", "regelung", ["Comfort 4", "Comfort Online"], []),
        ],
    },
    {
        "name": "Solvis", "group": "Heiztechnik",
        "info": "Schichtenspeicher-Heizzentralen und Wärmepumpen.",
        "website": "https://www.solvis.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["solvis.de"], "color": "#F39200",
        "series": [
            ("SolvisMax", "speicher", ["SolvisMax Gas", "SolvisMax Öl", "SolvisMax Pur", "SolvisMax Pellet"], ["schichtenspeicher", "heizzentrale"]),
            ("SolvisBen / SolvisLea", "wp", ["SolvisBen", "SolvisLea"], []),
            ("SolvisControl", "regelung", ["SolvisControl 3", "SolvisRemote"], []),
        ],
    },
    {
        "name": "Paradigma", "group": "Heiztechnik",
        "info": "Solarthermie (CPC-Röhrenkollektoren) und Pelletkessel.",
        "website": "https://www.paradigma.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["paradigma.de"], "color": "#E2001A",
        "series": [
            ("AquaSystem / CPC Star", "solar", ["CPC Star azzurro", "AQUA PLASMA", "CPC 45"], ["röhrenkollektor"]),
            ("Pelletti / Peleo", "holz", ["Pelletti III", "Peleo Optima"], ["pellet"]),
            ("SystaComfort", "regelung", ["SystaComfort II", "SystaWeb"], []),
        ],
    },
    {
        "name": "Dimplex", "group": "Wärmepumpen & Klima",
        "info": "Wärmepumpen und Wärmepumpenmanager.",
        "website": "https://dimplex.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["dimplex.de"], "color": "#003D7C",
        "series": [
            ("System M / LA-Serie", "wp", ["System M", "LA 12S-TU", "LA 18S-TU", "LA 6S-TUR"], ["luft-wasser"]),
            ("SI-Serie", "wp", ["SI 8TU", "SI 11TU", "SIK 7TES"], ["sole"]),
            ("Wärmepumpenmanager WPM", "regelung", ["WPM Touch", "WPM EconPlus"], []),
        ],
    },
    {
        "name": "CLAGE", "group": "Wärmepumpen & Klima",
        "info": "Durchlauferhitzer und Kleinspeicher.",
        "website": "https://www.clage.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["clage.de", "clage.com"], "color": "#0072BC",
        "series": [
            ("DSX / DEX / DCX", "elektro", ["DSX Touch", "DEX Next", "DCX Next", "DBX Next"], ["durchlauferhitzer"]),
            ("CEX / MCX", "elektro", ["CEX 9", "MCX 3", "MCX 6"], ["kleindurchlauferhitzer"]),
        ],
    },
    {
        "name": "Viega", "group": "Installationssysteme",
        "info": "Pressverbinder, Rohrleitungssysteme und Vorwandtechnik.",
        "website": "https://www.viega.de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["viega.de", "viega.com"], "color": "#FFCC00",
        "series": [
            ("Profipress / Sanpress / Megapress", "sanitaer", ["Profipress", "Sanpress Inox", "Megapress", "Temponox"], ["pressfitting", "kupfer", "edelstahl"]),
            ("Raxofix / Smartpress", "sanitaer", ["Raxofix", "Smartpress"], ["mehrschichtverbundrohr"]),
            ("Prevista / Prestabo", "sanitaer", ["Prevista Dry", "Prevista Pure", "Prestabo"], ["vorwand", "spülkasten"]),
            ("Visign Betätigungsplatten", "sanitaer", ["Visign for Style 20", "Visign for More 200"], ["betätigungsplatte"]),
            ("Advantix Duschrinnen", "sanitaer", ["Advantix Vario", "Advantix Cleviva"], ["bodenablauf", "duschrinne"]),
            ("Fonterra Flächenheizung", "heizflaeche", ["Fonterra Base", "Fonterra Side 12"], ["fußbodenheizung"]),
        ],
    },
    {
        "name": "Uponor", "group": "Installationssysteme",
        "info": "Verbundrohrsysteme, Flächenheizung und Smatrix-Regelung.",
        "website": "https://www.uponor.com/de-de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["uponor.com"], "color": "#0069B4",
        "series": [
            ("Uni Pipe PLUS / S-Press PLUS", "sanitaer", ["Uni Pipe PLUS", "S-Press PLUS", "RS-Press"], ["mehrschichtverbundrohr"]),
            ("Minitec / Klett / Tacker", "heizflaeche", ["Minitec", "Klett", "Tacker"], ["fußbodenheizung"]),
            ("Smatrix Wave / Base / Pulse", "regelung", ["Smatrix Wave", "Smatrix Base", "Smatrix Pulse"], ["einzelraumregelung"]),
            ("Vario / Verteiler", "heizflaeche", ["Vario PLUS", "Vario S"], ["heizkreisverteiler"]),
        ],
    },
    {
        "name": "REHAU", "group": "Installationssysteme",
        "info": "RAUTITAN, Flächenheizung und Nea Smart.",
        "website": "https://www.rehau.com/de-de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["rehau.com"], "color": "#E1001A",
        "series": [
            ("RAUTITAN", "sanitaer", ["RAUTITAN flex", "RAUTITAN stabil", "RAUTITAN pink+"], ["schiebehülse"]),
            ("RAUTHERM / Flächenheizung", "heizflaeche", ["RAUTHERM S", "RAUTHERM SPEED", "Varionova"], ["fußbodenheizung"]),
            ("Nea Smart 2.0", "regelung", ["Nea Smart 2.0", "Nea Smart R"], ["einzelraumregelung"]),
            ("RAUPIANO", "sanitaer", ["RAUPIANO PLUS", "RAUPIANO LIGHT"], ["abwasser"]),
        ],
    },
    {
        "name": "TECE", "group": "Installationssysteme",
        "info": "Vorwandsysteme, Betätigungsplatten und Duschrinnen.",
        "website": "https://www.tece.com/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["tece.com"], "color": "#00548A",
        "series": [
            ("TECEprofil / TECEbox", "sanitaer", ["TECEprofil", "TECEbox", "TECElux"], ["vorwand", "spülkasten"]),
            ("TECEloop / TECEsquare / TECEnow", "sanitaer", ["TECEloop", "TECEsquare", "TECEnow", "TECEvelvet"], ["betätigungsplatte"]),
            ("TECEdrainline / TECEdrainpoint", "sanitaer", ["TECEdrainline", "TECEdrainpoint S"], ["duschrinne"]),
            ("TECEflex / TECElogo", "sanitaer", ["TECEflex", "TECElogo"], ["rohrsystem"]),
        ],
    },
    {
        "name": "IMI Heimeier", "group": "Pumpen & Armaturen",
        "info": "Thermostatköpfe, Ventile und Strangregulierung.",
        "website": "https://www.imi-hydronic.com/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["imi-hydronic.com"], "color": "#003A70",
        "series": [
            ("Thermostatkopf K / DX / Halo", "armatur", ["Thermostat-Kopf K", "DX", "Halo"], ["thermostatkopf"]),
            ("Eclipse / Calypso / V-exact II", "armatur", ["Eclipse", "Calypso exact", "V-exact II", "Regutec"], ["ventileinsatz", "abgleich"]),
            ("Multilux / Vekolux", "armatur", ["Multilux 4", "Vekolux"], ["heizkörperanschluss"]),
            ("STAD / TA-Scope", "armatur", ["STAD", "STAP", "TA-Scope"], ["strangregulierventil"]),
        ],
    },
    {
        "name": "SYR", "group": "Wasser & Druckhaltung",
        "info": "Filter, Druckminderer, Leckageschutz (Hans Sasserath).",
        "website": "https://www.syr.de/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["syr.de"], "color": "#E30613",
        "series": [
            ("DRUFI / Filter", "wasser", ["DRUFI+", "DRUFI+ FF", "Filter 2315"], ["druckminderer", "rückspülfilter"]),
            ("SafeTech Connect / SafeFloor", "wasser", ["SafeTech Connect", "SafeTech plus", "SafeFloor Connect"], ["leckageschutz"]),
            ("LEX Plus 10 Connect / NeoSoft", "wasser", ["LEX Plus 10 S Connect", "NeoSoft 2500"], ["enthärtung"]),
            ("Systemtrenner BA / HeizungsWasserFüllstation", "wasser", ["BA 6600", "HWF Connect"], ["füllkombination", "heizungswasser"]),
        ],
    },
    {
        "name": "JUDO", "group": "Wasser & Druckhaltung",
        "info": "Enthärtung, Filter und Leckageschutz.",
        "website": "https://judo.eu/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["judo.eu"], "color": "#005BA1",
        "series": [
            ("i-soft / i-soft safe+", "wasser", ["i-soft K SAFE+", "i-soft PRO", "i-soft safe+"], ["enthärtung"]),
            ("PROFIMAT / ZEWA", "wasser", ["PROFIMAT", "ZEWA PLUS", "QuickSwitch Plus"], ["rückspülfilter"]),
            ("ZEWA i-SAFE / PROM-i-SAFE", "wasser", ["ZEWA i-SAFE", "PROM-i-SAFE"], ["leckageschutz"]),
            ("HEIFI / JUDO Heizungswasser", "wasser", ["HEIFI-TOP", "HEIFI-FILL"], ["heizungswasser", "vde 2035"]),
        ],
    },
    {
        "name": "BWT", "group": "Wasser & Druckhaltung",
        "info": "Enthärtungsanlagen, Filter und Heizungswasser.",
        "website": "https://www.bwt.com/de-de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["bwt.com"], "color": "#002F6C",
        "series": [
            ("AQA perla / AQA life", "wasser", ["AQA perla", "AQA perla 20", "AQA life S", "Perla Seta"], ["enthärtung"]),
            ("Infinity / E1 / Bolero", "wasser", ["Infinity M", "E1 Einhebelfilter", "Avanti FR"], ["rückspülfilter"]),
            ("AQA Therm", "wasser", ["AQA Therm HES", "AQA Therm SRC", "AQA Therm HFK"], ["heizungswasser", "vdi 2035"]),
        ],
    },
    {
        "name": "Reflex", "group": "Wasser & Druckhaltung",
        "info": "Ausdehnungsgefäße, Druckhaltung und Entgasung.",
        "website": "https://www.reflex-winkelmann.com/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["reflex-winkelmann.com", "reflex.de"], "color": "#E30613",
        "series": [
            ("Reflex N / NG / S", "druck", ["N 8", "N 18", "N 25", "NG 35", "S 33"], ["membranausdehnungsgefäß"]),
            ("Refix DD / DE", "druck", ["Refix DD 8", "Refix DD 18", "Refix DE 33"], ["trinkwasser"]),
            ("Reflexomat / Variomat", "druck", ["Reflexomat", "Variomat", "Gigamat"], ["druckhaltestation"]),
            ("Servitec / Exvoid", "druck", ["Servitec", "Exvoid", "Exdirt"], ["entgasung", "abscheider"]),
        ],
    },
    {
        "name": "Flamco", "group": "Wasser & Druckhaltung",
        "info": "Ausdehnungsgefäße Flexcon und Abscheider.",
        "website": "https://flamcogroup.com/de",
        "docPortal": None, "docPortalNote": None,
        "domains": ["flamcogroup.com"], "color": "#E2001A",
        "series": [
            ("Flexcon / Airfix", "druck", ["Flexcon 18", "Flexcon 25", "Flexcon R", "Airfix R"], ["membranausdehnungsgefäß"]),
            ("Flamcovent / Clean Smart", "druck", ["Flamcovent", "Flamco Clean Smart", "XStream"], ["entlüfter", "schlammabscheider"]),
        ],
    },
]


def slug(text: str) -> str:
    t = text.lower()
    for a, b in (("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")):
        t = t.replace(a, b)
    t = re.sub(r"[^a-z0-9]+", "-", t).strip("-")
    return t


def main() -> int:
    cat_ids = {c[0] for c in CATEGORIES}
    out_manufacturers = []
    seen = set()
    for m in MANUFACTURERS:
        mid = slug(m["name"])
        series = []
        for name, cat, models, keywords in m["series"]:
            if cat not in cat_ids:
                print(f"Unbekannte Kategorie {cat!r} bei {m['name']} / {name}", file=sys.stderr)
                return 1
            sid = f"{mid}.{slug(name)}"
            if sid in seen:
                print(f"Doppelte ID {sid}", file=sys.stderr)
                return 1
            seen.add(sid)
            series.append({
                "id": sid, "name": name, "category": cat,
                "models": models, "keywords": keywords, "documents": [],
            })
        out_manufacturers.append({
            "id": mid, "name": m["name"], "group": m["group"], "info": m["info"],
            "website": m["website"], "docPortal": m["docPortal"],
            "docPortalNote": m["docPortalNote"], "searchDomains": m["domains"],
            "color": m["color"], "series": series,
        })
    catalog = {
        "version": 1,
        "updated": CATALOG_UPDATED,
        "categories": [
            {"id": i, "name": n, "symbol": s, "synonyms": syn} for i, n, s, syn in CATEGORIES
        ],
        "manufacturers": out_manufacturers,
    }
    OUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    n_series = sum(len(m["series"]) for m in out_manufacturers)
    print(f"{OUT.name}: {len(out_manufacturers)} Hersteller, {n_series} Serien")
    return 0


if __name__ == "__main__":
    sys.exit(main())
