# Soundboard — Project Analysis

## Overview

An ESP32-based hardware soundboard built for a "Carbage Run" (Schrottauto-Rallye). The device lets you trigger meme sounds and funny horns via a physical 5×5 button matrix or remotely over Bluetooth, feeding audio into a pre-existing car amplifier.

---

## Hardware

| Component | Detail |
|---|---|
| MCU | ESP32 DOIT DevKit V1 |
| Input | 5×5 matrix keypad — 24 sound keys (A–X) + `Y` as mode button |
| Audio module | DFPlayer Mini (HardwareSerial UART2, RX=22 TX=23, 9600 baud) |
| Play state | DFPlayer BUSY pin → GPIO4 (LOW while playing, read instead of a serial query) |
| Wireless | ESP32 built-in Bluetooth Classic (`BluetoothSerial`, device name `das_11lein`) |
| Output | Line-out → pre-installed car amplifier (BT / Line-In capable) |

**Pin mapping:**
- Row pins: 19, 18, 5, 17, 16
- Column pins: 32, 33, 25, 26, 27
- DFPlayer: TX→GPIO22, RX→GPIO23, BUSY→GPIO4

---

## Firmware

- **Platform:** PlatformIO, Arduino framework, `espressif32@^7.0.1` (Arduino-ESP32 core 3.x)
- **Libraries:** `Keypad` 3.1.1, `DFPlayerMini_Fast` 1.2.4
- **Serial monitor:** 115200 baud
- **Build:** `~/.platformio/penv/bin/pio run` (the new esptool needs the `intelhex` Python module in the pio env)

### Sound Bank

144 MP3 files on the DFPlayer's SD card in a `MP3/` folder. Track numbering encodes the bank: `bank*100 + position`, so bank 1 = `0101`–`0124`, bank 2 = `0201`–`0224`, … bank 6 = `0601`–`0624` (**6 banks of 24**). Reference copies live in `src/MP3_org1/`.

### Keypad Logic

`Y` selects the active bank group (it plays no sound). A sound key tapped vs. held picks one of the pair. The mode resets to default after every played sound, after 10 s of inactivity, or on pressing `Y` again.

| `Y` status | sound key tap | sound key hold |
|---|---|---|
| – (default) | Bank 1 (`0101`–`0124`) | Bank 2 (`0201`–`0224`) |
| `Y` tapped  | Bank 3 (`0301`–`0324`) | Bank 4 (`0401`–`0424`) |
| `Y` held    | Bank 5 (`0501`–`0524`) | Bank 6 (`0601`–`0624`) |

Track = `(bankIndex + 1) * 100 + (key − 'A' + 1)`, where `bankIndex = modeLevel*2 + hold` (0..5).
Pressing the same key again while it is playing stops playback (BUSY-pin toggle).

### Bluetooth Commands

Send a number string (terminated with `\n`). The track number encodes the bank, so it is sent directly.

| Value | Action |
|---|---|
| 101–624 | Play that track directly (e.g. 305 = bank 3, key E) |
| 9999 | Stop playback |
| 9998 | Volume 10 |
| 9997 | Volume 20 |
| 9996 | Volume 30 (max) |
| 9995 | `ESP.restart()` |

Default volume on boot: **30** (maximum). Command codes sit at 9999 and descend — far above any track number, so they never collide.

---

## Sound Library

The two CSV files (`list_5x5_1.csv`, `list_5x5_2.csv`) describe an older 5×5 / 50-track layout and predate the 6-bank (144-track) scheme — treat them as historical. The SD card content is what the device actually plays.

---

## Notes / Observations

- **No BT authentication** — any device can connect to `das_11lein` and trigger or stop sounds.
- **No mode feedback** — there is no LED; the current bank group is only visible on the serial monitor (`Mode: n`). Deliberately omitted (see history) to avoid extra wiring.
- **CSV files are stale** — `list_5x5_1.csv` / `list_5x5_2.csv` reflect the old 25-key layout, not the current 144-track banks.
- **SD card must match the bank layout** — 24 tracks per bank, named `bank*100+pos` (`0101`–`0624`), or keys play the wrong sound.

---

## File Structure

```
.
├── platformio.ini          # Build config (ESP32, Arduino, lib deps)
├── src/
│   ├── main.cpp            # All firmware logic
│   ├── list_5x5_1.csv      # Legacy 25-key track list (historical)
│   ├── list_5x5_2.csv      # Legacy 25-key track list (historical)
│   └── MP3_org1/           # Reference copies of the MP3 files
├── include/                # (empty, PlatformIO default)
├── lib/                    # (empty, PlatformIO default)
└── test/                   # (empty, PlatformIO default)
```
