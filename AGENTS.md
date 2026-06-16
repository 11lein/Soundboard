# Soundboard — Project guide

ESP32 hardware soundboard for a "Carbage Run" (Schrottauto-Rallye): triggers meme
sounds / horns via a physical 5×5 button matrix **or** remotely over Bluetooth,
feeding a car amplifier.

**Three components:**

| Component | Path | Stack |
|---|---|---|
| Firmware | `src/main.cpp` | PlatformIO / Arduino-ESP32 |
| Phone app | `app/` | Flutter (Android) |
| MP3 sorter | `tools/mp3-sorter/` | Electron (desktop) |

---

## Build & deploy

Neither tool is on `PATH`: `pio` = `~/.platformio/penv/bin/pio`, `flutter` = `~/flutter/bin/flutter`.

**ESP32 firmware** (from repo root) — flash over USB, no OTA:
- Build: `~/.platformio/penv/bin/pio run`
- Flash: `~/.platformio/penv/bin/pio run -t upload --upload-port /dev/ttyUSB0`
- Serial monitor: 115200 baud.

**Phone app** (from `app/`) — builds fine directly from this repo path:
1. Reachable? `adb devices`. Test phone **SM S938B** at `192.168.178.21:41321`.
   If absent: `adb connect 192.168.178.21:41321` (Phone → Dev options → Wireless
   debugging; `adb mdns services` finds the ip:port, pair once if needed).
2. Build: `~/flutter/bin/flutter build apk --release`
3. **Update in place:** `adb -s 192.168.178.21:41321 install -r build/app/outputs/flutter-apk/app-release.apk`
   — `-r` keeps app data. **Do NOT use `flutter install`**: it uninstalls first ("Uninstalling
   old version…") and wipes app data.

Needs JDK 17 (`JAVA_HOME`) + Android SDK **compileSdk 36** (forced for all modules;
transitive `file_picker` requirement). Committed prebuilt APK: `app/soundboard-remote.apk`.

**Sorter:** `cd tools/mp3-sorter && npm start`. Tests: `npm test` (unit), `npm run test:smoke` (Electron, needs a display).

---

## Hardware

| Component | Detail |
|---|---|
| MCU | ESP32 DOIT DevKit V1 |
| Input | 5×5 matrix keypad — 24 sound keys (A–X) + `Y` as mode button |
| Audio module | DFPlayer Mini (HardwareSerial UART2, RX=22 TX=23, 9600 baud) |
| Play state | DFPlayer BUSY pin → GPIO4 (LOW while playing) |
| Wireless | ESP32 Bluetooth Classic (`BluetoothSerial`, device name `das_11lein`) |
| Output | Line/SPK-out → car amplifier |

**Pins** (rows `19,18,5,17,16`, cols `32,33,25,26,27`): DFPlayer TX→GPIO22,
RX→GPIO23 **(via 1 kΩ in series)**, BUSY→GPIO4, VCC→5V, GND→GND, SPK1/SPK2→speaker.
Wiring diagram: `docu/wiring_diagram.png` (source `.svg`, regen `python3 docu/gen_wiring.py`).
The Wokwi sketch in `docu/wokwi/` is outdated (used an SD module as placeholder).

---

## Firmware (`src/main.cpp`)

- **Platform:** PlatformIO, Arduino, `espressif32@^7.0.1` (Arduino-ESP32 3.x).
  **Libs:** `Keypad` 3.1.1, `DFPlayerMini_Fast` 1.2.4, `Preferences`.
- **WiFi disabled** at boot (`esp_wifi_stop()/deinit()`) — saves power, avoids 2.4 GHz
  contention with BT. Do *not* `#include <WiFi.h>` (would blow the flash partition).

### Sound banks

144 MP3s in the SD card's `MP3/` folder; track number encodes the bank:
`bank*100 + position` → bank 1 = `0101`–`0124` … bank 6 = `0601`–`0624` (**6 banks × 24**).
"App-only" extras (parked files in the sorter) are `0700`+ — playable from the app list,
not from the keypad.

### Keypad logic (play on **release**)

`Y` selects the active bank group (no sound). A sound key **tap** = bank A, **hold (≥500 ms)**
= bank B. Mode resets after each played sound, after 10 s, or on pressing `Y` again. Pressing
the same key while playing **stops** it (BUSY-pin toggle).
Track = `(modeLevel*2 + hold + 1)*100 + (key−'A'+1)`.

| `Y` status | tap | hold |
|---|---|---|
| – (default) | Bank 1 | Bank 2 |
| `Y` tapped  | Bank 3 | Bank 4 |
| `Y` held    | Bank 5 | Bank 6 |

> A "play on press" variant was reverted: at press time you can't tell "stop" vs
> "hold-for-bank-B" apart, and it relied on the unreliable BUSY pin.

### Bluetooth protocol (ASCII number + `\n`)

| Value | Action |
|---|---|
| `101`–`624` | Play bank track (`305` = bank 3, key E) |
| `700`–`6999` | Play an app-only / parked track (file `0700`…) |
| `7000`–`7100` | Set volume to `(n−7000)` % (0–100) |
| `9999` | Stop |
| `9998` / `9997` / `9996` | Volume 33 / 67 / 100 % (legacy) |
| `9995` | `ESP.restart()` |

- Volume is a **percentage (0–100 %)**, mapped to DFPlayer 0–30 internally. Persisted in
  NVS (`Preferences`), **deferred** ~1.5 s after the last change (avoids flash-write stalls
  on rapid +5/−5). Default **100 %**.
- On connect the ESP sends `READY vol=<pct>` once (app ignores it).
- No BT auth — any paired device can connect to `das_11lein`.

---

## Phone app (`app/`, Flutter / Android)

Remote over **Bluetooth Classic (SPP)** via a custom Kotlin platform channel
(`soundboard/bt`) — no third-party BT plugin, so it builds with current AGP/Gradle.
**IDs:** namespace `de._11lein.soundboard_remote`, applicationId `de.lein11.soundboard_remote`.
**Deps:** `permission_handler`, `file_picker`, `shared_preferences`, `vibration`, `wakelock_plus`.
iOS unsupported (BT Classic/SPP); see `app/README.md`.

### Features

- **Tasten tab:** 6-bank 5×5 grid, swipe horizontally to change bank (PageView, 6 banks +
  1 extras page for `0700`+); tiles shrink to fit, no scrolling. Tap plays `bank*100+pos`;
  **long-press a key** opens a sheet with all six bank assignments (titles if a list is
  imported; long-press a row to edit its title). `Y` cell = **🎲 random**. Controls: status
  line (3 s) + red **STOP** + volume **−5 % / {pct} (tap = 100 %) / +5 %**. Swiping right
  past the last bank page hands off to the Liste tab (overscroll → `_tabController.animateTo(1)`).
- **Liste tab:** searchable title list + red STOP; tap plays, long-press edits a title.
  Import/Export/summary on a separate **Titelliste** page (⋮ menu).
- **AppBar ⋮ menu:** connect/disconnect, forget device, ESP restart, checkable toggles
  **„Titel statt Nummern"** + **„Bildschirm anlassen"** (display toggles live here, off by
  default, `wakelock_plus`), Titelliste, Einstellungen.
- **Settings page:** vibration only (on/off, intensity, duration via `vibration`).
- **Connection:** watchdog polls every 0.7 s, auto-reconnects to the **last** device only;
  errors shown as a toast.
- **Track-list JSON** `{exported,count,tracks:[{n,title}]}` is the interchange format with
  the sorter; editable in-app and re-exportable for renaming.

---

## MP3 sorter (`tools/mp3-sorter/`, Electron)

Drag-and-drop tool to name/arrange the SD-card MP3s into the `bank*100+pos` scheme.
`main.js` (IPC) / `preload.js` (contextIsolation bridge) / `renderer/` (UI); naming logic
in `lib/naming.js`.

- 5×5 PDF-style grid (6 bank lines/cell) + **parking** rows for unprefixed files; **trash**
  tile deletes on save; per-file rename + inline rename; hover shows duration/bitrate.
- **PDF** export/preview (A4 landscape); **track-list export** (`📋 Liste`) / **import**
  (`📥 Liste importieren`, applies edited titles for renaming).
- **SD-card export** copies slotted files as `0101_…`, parked as `0700_…`.
- Remembers + reopens the last folder; **🔄 Aktualisieren** re-reads it keeping the arrangement.

---

## Gotchas

- **SD card must match the bank layout** (24/bank, `0101`–`0624`, parked `0700`+) or keys play the wrong sound.
- **No mode LED** — current bank group only on the serial monitor (`Mode: n`); deliberate.
- The DFPlayer **BUSY pin is unreliable** (reads idle ~1 s into a track, flickers); only used for the same-key stop toggle.
- The CSVs (`docu/list_5x5_*.csv`) reflect the old 25-key layout — historical.

---

## File structure

```
.
├── platformio.ini              # ESP32 / Arduino build config
├── src/main.cpp                # Firmware
├── docu/                       # Photos, wiring_diagram.{png,svg}, gen_wiring.py, legacy CSV/PDF
├── app/                        # Flutter Android remote (README.md, soundboard-remote.apk)
│   ├── lib/                    # home_page, soundboard_controller, list_page, settings_page, haptics, app_settings
│   └── android/                # Kotlin SPP channel (de/_11lein/soundboard_remote/MainActivity.kt)
└── tools/mp3-sorter/           # Electron sorter (main/preload/renderer, lib/naming.js, test/)
```
