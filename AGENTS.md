# Soundboard — Project Analysis

## Overview

An ESP32-based hardware soundboard built for a "Carbage Run" (Schrottauto-Rallye).
It triggers meme sounds / horns via a physical 5×5 button matrix **or** remotely
over Bluetooth, feeding audio into a car amplifier.

The repo has **three components**:

| Component | Path | Stack |
|---|---|---|
| Firmware | `src/main.cpp` | PlatformIO / Arduino-ESP32 |
| Phone app | `app/` | Flutter (Android) |
| MP3 sorter tool | `tools/mp3-sorter/` | Electron (desktop) |

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

**Pin mapping** (rows `19,18,5,17,16`, cols `32,33,25,26,27`):
- DFPlayer: TX→GPIO22, RX→GPIO23 **(via 1 kΩ in series)**, BUSY→GPIO4, VCC→5V, GND→GND, SPK1/SPK2→speaker.
- Current wiring diagram: **`docu/wiring_diagram.png`** (source `docu/wiring_diagram.svg`, regenerate with `python3 docu/gen_wiring.py`). The old Wokwi sketch in `docu/wokwi/` used an SD-card module as a placeholder and is outdated.

---

## Firmware (`src/main.cpp`)

- **Platform:** PlatformIO, Arduino framework, `espressif32@^7.0.1` (Arduino-ESP32 3.x)
- **Libraries:** `Keypad` 3.1.1, `DFPlayerMini_Fast` 1.2.4, `Preferences`
- **Build:** `~/.platformio/penv/bin/pio run` · **Flash:** `pio run -t upload --upload-port /dev/ttyUSB0` · **Monitor:** 115200 baud
- **WiFi is disabled** at boot (`esp_wifi_stop()/deinit()`) — saves power and avoids 2.4 GHz contention with BT. (We intentionally do *not* `#include <WiFi.h>`; it would blow the flash partition.)

### Sound banks

144 MP3 files in the SD card's `MP3/` folder. Track number encodes the bank:
`bank*100 + position` → bank 1 = `0101`–`0124` … bank 6 = `0601`–`0624` (**6 banks × 24**).
"App-only" extra tracks (parked files in the sorter) are numbered **`0700`+** and are
playable from the app's list but not reachable from the keypad.

### Keypad logic (play on **release**)

`Y` selects the active bank group (plays no sound). A sound key **tap** = bank A of
the group, **hold (≥500 ms)** = bank B. The mode resets after every played sound,
after 10 s, or on pressing `Y` again. Pressing the same key again while it plays
**stops** it (BUSY-pin toggle). Track = `(modeLevel*2 + hold + 1)*100 + (key−'A'+1)`.

| `Y` status | tap | hold |
|---|---|---|
| – (default) | Bank 1 | Bank 2 |
| `Y` tapped  | Bank 3 | Bank 4 |
| `Y` held    | Bank 5 | Bank 6 |

> A "play on press" variant was tried for lower latency but reverted: at press time
> you can't tell "stop"/"hold-for-bank-B" apart, and it relied on the unreliable BUSY pin.

### Bluetooth protocol (ASCII number + `\n`)

| Value | Action |
|---|---|
| `101`–`624` | Play bank track (e.g. `305` = bank 3, key E) |
| `700`–`6999` | Play an app-only / parked track (file `0700`…) |
| `7000`–`7100` | Set volume to `(n−7000)` percent (0–100 %) |
| `9999` | Stop |
| `9998` / `9997` / `9996` | Volume 33 / 67 / 100 % (legacy/compat) |
| `9995` | `ESP.restart()` |

- **Volume is a percentage (0–100 %)**, mapped to the DFPlayer's 0–30 internally.
  Persisted in NVS (`Preferences`), **deferred** (written ~1.5 s after the last change
  to avoid blocking flash writes during rapid +5/−5 tapping). Default **100 %**.
- On connect the ESP sends `READY vol=<pct>` once (the app currently ignores it).
- No BT authentication — any paired device can connect to `das_11lein`.

---

## Phone app (`app/`, Flutter / Android)

Remote control over **Bluetooth Classic (SPP)** via a custom Kotlin platform channel
(`soundboard/bt`) — no third-party BT plugin, so it builds with current AGP/Gradle.

- **IDs:** namespace `de._11lein.soundboard_remote`, applicationId `de.lein11.soundboard_remote`.
- **Build gotchas:** path must be **space-free** → build a copy at `~/soundboard_remote`
  (the repo path `Soundboard (Kopie)` breaks Gradle). Needs **JDK 17** (`JAVA_HOME`),
  Android SDK with **compileSdk 36** (forced for all modules; required by a transitive
  `file_picker` plugin). Build: `flutter build apk --release`.
- **Wireless install (no cable):** `adb mdns services` → `adb connect <ip:port>` →
  `adb install -r app-release.apk`. (Phone: Developer options → Wireless debugging on.)
  A prebuilt APK is committed at `app/soundboard-remote.apk`.
- **Deps:** `permission_handler`, `file_picker`, `shared_preferences`, `vibration`, `wakelock_plus`.

### App features

- **Tasten tab:** 6-bank 5×5 grid, **swipe** horizontally to change bank (PageView);
  square tiles shrink to fit (no scrolling). Tap plays `bank*100+pos`; **long-press a
  key** opens a sheet with all six bank assignments (titles if a list is imported;
  long-press a row there to edit its title). The hardware `Y` cell is a **🎲 random**
  button. Controls: status line (now-playing, 3 s) + red **STOP** + volume **−5 % /
  {pct} % (tap = 100 %) / +5 %**.
- **Liste tab:** searchable title list with a red STOP next to the search; tap to play,
  long-press to edit a title. Import/Export/summary live on a separate **Titelliste**
  page (overflow menu).
- **AppBar:** Bluetooth state icon (tap reconnects to the last device) + ⋮ menu
  (connect/disconnect, forget device, ESP restart, Titelliste, Einstellungen).
- **Connection:** watchdog polls every 0.7 s; auto-reconnects to the **last** device only;
  errors shown as a toast, not a shifting status bar.
- **Settings:** real vibration (on/off, intensity, duration via `vibration`), "titles on
  keys" (off by default), "keep screen on" (off by default, `wakelock_plus`).
- **Track list JSON** (`{exported,count,tracks:[{n,title}]}`) is the interchange format
  with the sorter; can be edited in the app and re-exported for renaming there.

See `app/README.md` for install/build details (incl. why iOS isn't supported: BT Classic/SPP).

---

## MP3 sorter (`tools/mp3-sorter/`, Electron)

Drag-and-drop tool to name/arrange the SD-card MP3s into the `bank*100+pos` scheme.
`main.js` (IPC) / `preload.js` (contextIsolation bridge) / `renderer/` (UI); shared
naming logic in `lib/naming.js`. Run: `npm start`. Tests: `npm test` (unit) and
`npm run test:smoke` (Electron, needs a display).

- 5×5 PDF-style grid (6 bank lines per cell) + **parking** rows for unprefixed files;
  a **trash** tile deletes on final save; per-file **rename** + quick inline rename;
  hover shows MP3 duration/bitrate.
- **PDF** export/preview (A4 landscape), **track-list export** (`📋 Liste`) and
  **import** (`📥 Liste importieren`, applies edited titles for renaming).
- **SD-card export** copies slotted files as `0101_…` and parked files as `0700_…`.
- **Remembers the last opened folder** (config in Electron `userData`) and reopens it
  on start; **🔄 Aktualisieren** re-reads the folder keeping the current arrangement.

---

## Notes / gotchas

- **SD card must match the bank layout** (24/bank, `0101`–`0624`, parked `0700`+) or keys play the wrong sound.
- **No mode LED** — current bank group is only on the serial monitor (`Mode: n`); deliberate (no extra wiring).
- The CSVs (`docu/list_5x5_*.csv`) reflect the old 25-key layout — historical.
- The DFPlayer **BUSY pin is unreliable** as a "still playing" signal (reads idle ~1 s into a track and flickers); only used for the momentary same-key stop toggle.

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
