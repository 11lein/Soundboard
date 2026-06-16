# Code-Review: Soundboard

Analyse des Gesamtprojekts (ESP32-Firmware, Flutter-App, Electron-MP3-Sorter)
nach **Performance**, **Sicherheit**, **Coding-Guidelines** und **Linting**,
plus eine Bestandsaufnahme der Code-Kommentierung. Stand: 2026-06.

> Hinweis zur Verifikation: In der Review-/Web-Umgebung waren nur **Node.js +
> npm** verfügbar. Das Electron-Tool ist daher voll getestet (Unit-Tests,
> ESLint, Smoke-Test). **Flutter/Dart** und **PlatformIO** fehlten, d.h.
> Firmware und App konnten hier *nicht* kompiliert werden – Änderungen daran
> wurden bewusst konservativ gehalten und müssen lokal mit `flutter analyze` /
> `flutter test` bzw. `pio run` gegengeprüft werden.

## Gesamteindruck

Der Code ist insgesamt **überdurchschnittlich gepflegt**: durchdachte
Architektur, gute Trennung der drei Komponenten und – anders als oft – bereits
**dichte, sinnvolle Kommentierung** der nicht-offensichtlichen Stellen
(Bank-/Mode-Mathematik, deferred NVS-Write, BT-Overflow-Schutz, Reconnect-Logik,
PDF-Layout). Die wesentlichen Lücken lagen weniger bei „fehlenden Kommentaren"
als bei **fehlendem Linting** (Electron) und einem **inkonsistenten Path-Handling**
(Electron) sowie einer **sehr großen UI-Datei** (`app/lib/home_page.dart`).

| Komponente | Performance | Sicherheit | Guidelines | Linting |
|---|---|---|---|---|
| Firmware (`src/main.cpp`) | gut | gut (per Design) | gut | – (kein C++-Linter eingerichtet) |
| Flutter-App (`app/`) | gut | gut | mittel (Monolith) | flutter_lints (Default) |
| Electron (`tools/mp3-sorter/`) | gut | mittel → **gehärtet** | gut | **fehlte → eingeführt** |

---

## 1. Firmware — `src/main.cpp`

ESP32 / Arduino, ~330 Zeilen, eine `.cpp`. Sehr klar gegliedert und gut
kommentiert.

### Performance
- **Keine blockierenden Delays im `loop()`**; Timing über `millis()`-Stempel.
  Das einzige `delay(1000)` steckt in der DFPlayer-Init-Retry-Schleife in
  `setup()` (einmalig beim Boot) – akzeptabel und kommentiert.
- **Deferred NVS-Write** für die Lautstärke (`volumeDirty` + `VOLUME_SAVE_DELAY_MS`,
  `main.cpp:88`) verhindert Flash-Blockaden bei schnellem +5/−5-Tippen. Sehr gut.
- **Nicht-blockierender BT-Zeilenleser** mit fixem 8-Byte-Puffer (`main.cpp:256`)
  – keine Heap-Fragmentierung, sauberer Overflow-Schutz.

### Sicherheit
- **Kein Bluetooth-Auth** und **Remote-Reset (`9995`)** ohne Bestätigung
  (`main.cpp:305`). Das ist **bewusst so** (vertrauenswürdiges Umfeld, ein
  Carbage-Run-Auto) und in `AGENTS.md` dokumentiert. Threat-Model akzeptiert;
  als Restrisiko vermerkt (ein gekoppeltes Gerät kann Stop/Volume/Reset senden).
- **Eingabevalidierung** ist solide: `atoi` + `if (input > 0)`, Bereichsprüfung
  für Tracks/Volume (`main.cpp:285`, `310`), Overflow-Zeilen werden verworfen
  statt abgeschnitten (`main.cpp:264`, `329`). Nicht existente Tracks lässt der
  DFPlayer still fallen (kein Crash).

### Coding-Guidelines
- `keys`, `rowPins`, `colPins` (`main.cpp:57–65`) sind nicht `const`. **Bewusst
  nicht geändert:** der `Keypad`-Konstruktor nimmt nicht-`const`-Zeiger
  (`char*`, `byte*`), `const`-Pin-Arrays würden ohne Cast die Kompilierung
  brechen. Niedrige Priorität.
- Leichte Duplizierung bei den Kompat-Volume-Befehlen (`main.cpp:290–303`) –
  vertretbar, gut lesbar; kein Umbau nötig.
- Naming `mySerial` / `myDFPlayer` ist Arduino-üblich; rein kosmetisch.

### Umgesetzt (Kommentare, null Verhaltensänderung)
- `isPlaying()`: Unzuverlässigkeit des BUSY-Pins explizit dokumentiert und warum
  er nur für den Stop-Toggle taugt.
- Erläutert, warum `lastKey` nach einem Stop genullt wird.

---

## 2. Flutter-App — `app/`

Sauberes `ChangeNotifier`-Modell. `soundboard_controller.dart` (BT-State,
Protokoll, Reconnect-Watchdog) ist **vorbildlich kommentiert**. Native SPP-Anbindung
in Kotlin (`MainActivity.kt`) mit korrektem Threading und Exception-Handling.

### Performance
- `ListenableBuilder` auf `[controller, AppSettings]` (`home_page.dart`), Tabs via
  `KeepAlive`/`AutomaticKeepAliveClientMixin` am Leben gehalten – gut.
- **Watchdog 700 ms** (`soundboard_controller.dart:125`) mit 3-s-Throttle für
  stille Reconnects – vernünftig. *Empfehlung:* exponentielles Backoff, falls das
  Gerät dauerhaft aus ist (Akku).
- `wrapKeyTitle()` lief bisher pro Tile/Frame. Durch Auslagern als reine Funktion
  ist es jetzt **cachebar** (Empfehlung: Ergebnis pro `TrackEntry` memoisieren).

### Sicherheit
- Laufzeit-Berechtigungen (`Permission.bluetoothConnect`) inkl. „dauerhaft
  abgelehnt"-Pfad sauber behandelt (`soundboard_controller.dart:317`).
- Nur **gekoppelte** Geräte, fixe SPP-UUID; keine Secrets in `SharedPreferences`.
- *Empfehlung (Kotlin):* `s.connect()` ohne Timeout (`MainActivity.kt`) kann den
  Connect-Thread bis zum OS-Timeout (~20 s) hängen lassen → `withTimeoutOrNull`.

### Coding-Guidelines
- **Hauptbefund:** `home_page.dart` war mit **1193 Zeilen** ein Monolith
  (Grid, Controls, Dialoge, Suche, Menüs in einem `State`).
- Vereinzelt stille `catch (_)` ohne Begründung.

### Linting
- `analysis_options.yaml` nutzte nur das Default-`flutter_lints` ohne eigene
  Regeln.

### Umgesetzt
- **`home_page.dart` verschlankt:** die drei sicher und mechanisch
  extrahierbaren Teile nach `lib/widgets/` ausgelagert – `wrapKeyTitle()`
  (`key_title.dart`, jetzt unit-getestet), `KeepAlive`, `PlayPulse`.
  Verhaltensneutral (Verbatim-Move + Referenz-Rename).
- **Test** `test/key_title_test.dart` für die Umbruch-Invarianten.
- **Lint-Regeln** in `analysis_options.yaml` aktiviert (single quotes, const,
  final locals, no print, …) – stilkonform.
- Begründungs-Kommentare an den verbleibenden `catch (_)` im Controller.

### Offene Empfehlung (Follow-up mit Compiler)
Der tiefere Split der **zustandsbehafteten** Builder-Methoden
(`_grid`/`_key`/`_controls`/`_bankSelector`) in eigene `StatelessWidget`s wurde
**bewusst nicht** in dieser Umgebung gemacht: er erfordert das Durchreichen von
`controller` und etlichen Callbacks und ist ohne `flutter analyze`/Gerätetest
nicht verifizierbar (zu hohes Regressionsrisiko für eine reine Android-App).

---

## 3. Electron-MP3-Sorter — `tools/mp3-sorter/`

`main.js` (IPC/Dateioperationen), `preload.js` (contextBridge), `renderer/`
(UI), `lib/naming.js` (geteilte, gut getestete Namenslogik).

### Sicherheit (Electron-spezifisch)
**Solide Grundlage:** `contextIsolation: true`, `nodeIntegration: false`
(`main.js:91`), restriktive **CSP** (`renderer/index.html`), kein Remote-Content,
`execFile` mit Array-Args (keine Shell-Injection), Preload als enge Whitelist.

**Befund – inkonsistentes Path-Handling (behoben):** `copy-into` nutzte bereits
`path.basename`, aber `delete-files`, `apply-renames`, `copy-to-card`, `mp3-info`
und `file-url` verketteten den vom Renderer gelieferten Namen direkt mit dem
Ordner. In der Praxis kommen die Namen aus dem Verzeichnis-Listing (harmlos),
aber der Main-Prozess sollte dem Renderer nicht blind vertrauen → **Defense in
Depth**.

### Performance
- Dateioperationen durchweg **async** (`fs/promises`), kein Sync-I/O.
- `render()` baut das DOM komplett neu (144 Slots) – bei dieser festen Größe
  unkritisch; dokumentiert.
- `htmlToPdf()` startet pro Aufruf ein Offscreen-Fenster – selten/aktiv
  ausgelöst, Pooling wäre Overkill (jetzt als Kommentar begründet).

### Coding-Guidelines
- Gut benannte IPC-Handler, `lib/naming.js` isoliert und 100 % testabgedeckt.
- **Duplizierung:** vier nahezu identische Overlay-/Dialog-Blöcke im Renderer.

### Linting
- **Es gab kein ESLint-Setup** – die explizit angefragte Lücke.

### Umgesetzt (vollständig verifiziert)
- **`lib/safe-path.js` (`safeJoin`)** eingeführt und in *allen* betroffenen
  IPC-Handlern angewandt; erzwingt, dass jede Dateioperation im gewählten Ordner
  bleibt. Mit Unit-Test `test/safe-path.test.js`.
- **ESLint Flat-Config** (`eslint.config.js`) für die drei Scopes (Node, UMD,
  Browser), `npm run lint`-Script und Dev-Deps; einzigen Verstoß behoben
  (ungenutzter `naming`-Import in `main.js`).
- **`renderer/dialog.js` (`showDialog`)** extrahiert; Export-/Import-/Diff-/
  Format-Prompts darauf umgestellt (Dedup ~80 Zeilen, konsistentes Markup).
- Perf-Kommentar an `htmlToPdf()`.

**Verifikation:** `npm test` → **16/16 grün** · `npm run lint` → **sauber** ·
`npm run test:smoke` (xvfb) → **alle Checks grün**, inkl. „no preload/renderer
errors" und PDF-Vorschau (bestätigt, dass `dialog.js` korrekt eingebunden ist).

---

## Zusammenfassung der umgesetzten Änderungen

| Bereich | Änderung | Verifiziert? |
|---|---|---|
| Electron | `safeJoin` Path-Hardening + Test | ✅ Unit-Test |
| Electron | ESLint Flat-Config + `lint`-Script | ✅ `npm run lint` |
| Electron | `showDialog`-Dedup | ✅ Smoke-Test |
| Flutter | `home_page.dart` → `widgets/` (wrapKeyTitle/KeepAlive/PlayPulse) | ⚠️ lokal `flutter test`/`analyze` |
| Flutter | Lint-Regeln + Controller-Kommentare | ⚠️ lokal `flutter analyze` |
| Firmware | Kommentare (BUSY-Pin, Stop-Toggle) | ⚠️ lokal `pio run` |

## Empfohlene Follow-ups (nicht umgesetzt)
1. **Flutter:** `home_page.dart` weiter aufteilen (Grid/Controls als eigene
   Widgets) – mit Compiler/Gerätetest.
2. **Flutter:** `wrapKeyTitle`-Ergebnis pro `TrackEntry` cachen; Reconnect-Backoff;
   Connect-Timeout im Kotlin-Channel.
3. **Firmware:** optional ESP-seitig die Befehls-Annahme härten (z.B. Reset nur
   nach Bestätigungs-Sequenz), falls das Threat-Model strenger wird.
4. **CI:** GitHub-Action, die zumindest `npm test` + `npm run lint` (Electron)
   und – mit Flutter-Setup – `flutter analyze`/`flutter test` fährt.
