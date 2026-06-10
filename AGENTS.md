# Soundboard — Project Analysis

## Overview

An ESP32-based hardware soundboard built for a "Carbage Run" (Schrottauto-Rallye). The device lets you trigger meme sounds and funny horns via a physical 5×5 button matrix or remotely over Bluetooth, feeding audio into a pre-existing car amplifier.

---

## Hardware

| Component | Detail |
|---|---|
| MCU | ESP32 DOIT DevKit V1 |
| Input | 5×5 matrix keypad (25 buttons, keys A–Y) |
| Audio module | DFPlayer Mini (SoftwareSerial, RX=22 TX=23, 9600 baud) |
| Wireless | ESP32 built-in Bluetooth Classic (`BluetoothSerial`, device name `das_11lein`) |
| Output | Line-out → pre-installed car amplifier (BT / Line-In capable) |

**Pin mapping:**
- Row pins: 19, 18, 5, 17, 16
- Column pins: 32, 33, 25, 26, 27

---

## Firmware

- **Platform:** PlatformIO, Arduino framework
- **Libraries:** `Keypad` 3.1.1, `DFPlayerMini_Fast` 1.2.4, `EspSoftwareSerial` 8.1.0
- **Serial monitor:** 115200 baud

### Sound Bank

50 MP3 files stored on the DFPlayer's SD card in a `MP3/` folder, numbered `0001`–`0050`. Reference copies live in `src/MP3_org1/`.

### Keypad Logic

| Event | Behaviour |
|---|---|
| RELEASED (normal) | Play track `key − 'A' + 1` (tracks 1–25) |
| HOLD → RELEASED | Play track `+25` offset (tracks 26–50, second sound bank) |
| Same key released while already playing | Stop playback |

### Bluetooth Commands

Send a number string (terminated with `\n`) to the device over BT Serial:

| Value | Action |
|---|---|
| 1–94 | Play that track number (optionally shifted +25 if `secondSound` flag is set) |
| 99 | Set `secondSound = true` (next track request plays +25) |
| 98 | Stop playback |
| 97 | Set volume to 20 |
| 96 | Set volume to 10 |
| 95 | `ESP.restart()` |

Default volume on boot: **30** (maximum).

---

## Sound Library

The two CSV files (`list_5x5_1.csv`, `list_5x5_2.csv`) describe the intended 5×5 keypad layout for each sound bank. Both files are currently identical.

Notable discrepancies between the CSVs and the actual MP3 files in `MP3_org1/` — some tracks were renamed or replaced between versions (e.g. `0021_Cantina Band` in the folder vs. `0021_tv-total` in the CSV; `0023_STEPHAN_1` vs. `0023_nicht-so-tief-rudiger`). The SD card content is what the device actually plays.

---

## Known Issues / Observations

1. **String concatenation bug** ([src/main.cpp:169](src/main.cpp#L169)):
   ```cpp
   Serial.println("input: " + input);  // pointer arithmetic, not string concat
   ```
   Should be `Serial.println("input: " + String(input));` (same pattern used correctly a few lines later).

2. **`secondSound` (BT) vs. HOLD (keypad) are asymmetric:** The physical HOLD flag is reset after every key release. The BT `secondSound` flag persists until the next track is played, which is consistent but worth documenting.

3. **Commented-out startup guard:** The block that halts the MCU if the DFPlayer fails to initialise is disabled. If the SD card is missing, the device silently does nothing.

4. **CSV files are identical** — `list_5x5_1.csv` and `list_5x5_2.csv` have the same content. Likely intended to describe separate sound banks but never diverged.

5. **No BT authentication** — any device can connect to `das_11lein` and trigger or stop sounds.

---

## File Structure

```
.
├── platformio.ini          # Build config (ESP32, Arduino, lib deps)
├── src/
│   ├── main.cpp            # All firmware logic (~190 lines)
│   ├── list_5x5_1.csv      # Keypad layout / track list (bank 1)
│   ├── list_5x5_2.csv      # Keypad layout / track list (bank 2, currently identical)
│   └── MP3_org1/           # Reference copies of 50 MP3 files (0001–0050)
├── include/                # (empty, PlatformIO default)
├── lib/                    # (empty, PlatformIO default)
└── test/                   # (empty, PlatformIO default)
```
