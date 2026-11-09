# TikTok-Fakten – täglicher Workflow

Jeden Tag ein ~30-sekündiges Hochkant-Video (1080x1920) mit einem überraschenden Fakt,
animiert, mit deutscher KI-Stimme (Piper „Thorsten high“), Musik und Soundeffekten.

## Ein neues Video machen

1. `./setup.sh` (installiert Piper, lädt Stimme + Twemoji-Grafiken nach `assets/`)
2. Neues Skript `scripts/JJJJ-MM-TT-slug.json` anlegen (Vorlage: ein vorhandenes Skript)
3. `python3 render.py scripts/JJJJ-MM-TT-slug.json`
4. Ergebnis in `videos/`: `.mp4` (Video), `.png` (Cover), `.txt` (Caption + Hashtags)
5. Thema in `THEMEN.md` eintragen (damit sich nichts wiederholt)

## Regeln für Skripte

- **Nur Fakten, die nachweislich stimmen.** Keine Mythen („Wir nutzen nur 10 % des Gehirns“ usw.).
  Bei Zahlen lieber vorsichtig runden („rund“, „etwa“).
- Erste Szene = Hook: der verblüffende Fakt in einem Satz, sofort.
- 6–8 Szenen, insgesamt 25–40 Sekunden. Letzte Szene: Call-to-Action („Folge mir …“).
- Pro Szene: `text` (Untertitel), optional `say` (Aussprache, Zahlen ausgeschrieben!),
  `emoji` (ein Twemoji), `highlight` (Wörter in Akzentfarbe),
  optional `number` `{ "value": 243, "suffix": "TAGE" }` für animierten Zähler.
- `id` = laufende Fakt-Nummer, `accent`/`bg` = Farben (pro Video abwechseln).
- Themen abwechseln: Weltraum, Tiere, Körper, Geschichte, Technik, Natur, Essen, Psychologie …
