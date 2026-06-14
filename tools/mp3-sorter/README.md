# 🎚️ MP3 Sorter

Plattformübergreifendes Desktop-Tool (Mac / Linux / Windows) zum Sortieren der
Soundboard-MP3s per **Drag & Drop**. Die Dateien werden für das DFPlayer-Schema
`Bank*100 + Position` vorbereitet – Bank 1 = `0101`–`0124`, … Bank 6 =
`0601`–`0624` (6 Bänke × 24 = 144 Slots).

## Features

- 🖱️ **Drag & Drop:** Ordner oder MP3s ins Fenster ziehen zum Laden/Hinzufügen,
  Zeilen ziehen zum Umsortieren.
- 🔢 **Prefix-Sortierung:** Dateien mit gültigem `Bank*100+Pos`-Prefix (z. B.
  `0101_`, `0305_`) landen auf ihrem Slot; Dateien ohne (oder mit altem) Prefix
  werden alphabetisch dahinter einsortiert.
- 🏦 **Ansicht wie das PDF:** **ein** 5×5-Raster (dem Kasten nachempfunden, unten
  links beginnend, oben rechts die nicht belegbare Mode-Taste). Jede Taste zeigt
  **6 Zeilen** – eine je Bank – mit Dateiname (ohne Prefix/Endung) und
  **Play-Knopf** statt Nummer. Zellen sind nach der physischen Tastenfarbe
  eingefärbt.
- 🅿️ **Parkplätze:** Dateien **ohne** gültigen Prefix landen unten in Parkplätzen
  (Reihen aus 5 Boxen × 6 Zeilen, alphabetisch, mit Play). Zieht man eine Datei
  aus dem Raster hierher, wird ihr **Prefix entfernt** (sie wird wieder unsortiert).
- 🎨 **Farb-Kodierung:** Die physische Tastenfarbe (oben Grün, dann Gelb, Weiß,
  Blau, unten Schwarz – 2. von links Rot) liegt als
  [`lib/key-colors.json`](lib/key-colors.json) im Projekt und färbt Raster und PDF.
- ✏️ **Umbenennen (Suchen & Ersetzen):** Button öffnet einen Dialog mit
  Suchen/Ersetzen, **Regex**- und **Groß/Klein**-Checkbox (Default: ignoriert).
  Eine **2-Spalten-Vorschau** zeigt nur die betroffenen Dateien zum Bestätigen.
- 💳 **Auf SD-Karte schieben:** Wechseldatenträger auswählen, optional **vorher
  formatieren** (mit Nachfrage; sofern das OS es unterstützt), dann die geprefixten
  Dateien in den `MP3/`-Ordner der Karte kopieren.
- ▶️ **Vorhören:** Play-Knopf pro Zeile, der während der Wiedergabe zur Pause
  wird. Ein anderer Sound stoppt alle übrigen und setzt sie auf 0 s zurück – nur
  der aktuelle Titel merkt sich seine Pause.
- 🖨️ **PDF-Export & Vorschau (A4 quer):** Erzeugt eine Belegungs-Übersicht als
  5×5-Raster (mit den Tastenfarben als Hintergrund), wobei **jede Tastenzelle
  alle 6 Bänke** untereinander zeigt (Bank-Nummer + Dateiname **ohne**
  Prefix/Endung, einzeilig abgeschnitten, kein Umbruch). Ohne Überschrift, Zellen
  exakt 6 Zeilen hoch (Tabelle nicht seitenfüllend). **👁️ Vorschau** öffnet das
  fertige PDF in einem Fenster, bevor du speicherst.
- 💾 **Zwischenspeichern:** Der aktuelle Stand wird als `.mp3sorter.json` im
  Ordner gespeichert – **ohne** die Dateien anzufassen. Beim erneuten Öffnen
  wird dieser Entwurf wiederhergestellt.
- ✅ **Final speichern:** Erst hier werden die Dateien auf der Festplatte
  umbenannt (4-stelliger Prefix `NNNN_`). Kollisionssicher durch zweiphasiges
  Umbenennen (z. B. bei einem Tausch).

## Starten per Doppelklick

Voraussetzung: **Node.js/npm** ist installiert (https://nodejs.org). Beim ersten
Start werden die Abhängigkeiten automatisch geholt.

| Betriebssystem | Datei doppelklicken |
|----------------|---------------------|
| 🪟 Windows     | `start.bat` |
| 🍎 macOS       | `start.command` |
| 🐧 Linux       | `start.sh` |

> - **macOS:** Beim ersten Mal evtl. Rechtsklick → „Öffnen" (Gatekeeper).
> - **Linux:** Im Dateimanager ggf. „Ausführen erlauben" aktivieren bzw. beim
>   Doppelklick „Run/Ausführen" wählen.

## Start (Entwicklung / Terminal)

```bash
cd tools/mp3-sorter
npm install
npm start
```

> Hinweis Linux: Falls `ELECTRON_RUN_AS_NODE` in der Umgebung gesetzt ist, vorher
> entfernen: `env -u ELECTRON_RUN_AS_NODE npm start` (die Doppelklick-Starter
> erledigen das bereits selbst).

## Tests

```bash
npm test          # Unit-Tests der Sortier-/Namenslogik (node --test)
npm run test:smoke   # Electron-Smoketest: prüft, dass window.api vollständig
                     # bereitsteht und der "Ordner öffnen"-IPC-Pfad funktioniert
```

> Der Smoketest braucht eine Anzeige (DISPLAY) und ein echtes Electron; in
> Umgebungen mit gesetztem `ELECTRON_RUN_AS_NODE` davor entfernen.

## Installer bauen

```bash
npm run dist     # erzeugt dmg (mac) / nsis (win) / AppImage (linux) in dist/
```

## So funktioniert das Umbenennen

`finalName(slot, datei)` entfernt einen vorhandenen `NNNN_`-Prefix und setzt den
neuen `Bank*100+Pos`-Prefix davor – der beschreibende Teil bleibt erhalten:

```
Slot 1  + "0099_clownhorn.mp3"  ->  "0101_clownhorn.mp3"   (Bank 1, Pos 1)
Slot 25 + "airhorn.mp3"          ->  "0201_airhorn.mp3"     (Bank 2, Pos 1)
```

Die eigentliche Sortier-/Namenslogik liegt in [`lib/naming.js`](lib/naming.js)
und ist unabhängig von der GUI testbar.
