# 🚗 Soundboard für den Carbage Run

## 🎯 Motivation

Beim **Carbage Run** – einer Rallye mit Schrottautos – haben viele Teilnehmer Fanfaren, Megafone oder lustige Sounds abgespielt.  
Wir hatten zwar bereits ein Megafon mit Line-In und Bluetooth, aber:

> 🎛️ "Wenn ich hupen will, will ich auf einen Knopf hauen – nicht erst das Handy entsperren!"

Deshalb: ein eigenständiges Soundboard mit 25 Tasten, SD-Karte und Sofortreaktion.

---

## 📸 Vorschau

### Gehäuse (3D-gedruckt)

![Soundboard Gehäuse](docu/20240531_110053.jpg)
![Soundboard Gehäuse](docu/20240531_110109.jpg)
![Soundboard Gehäuse](docu/20230827_103529.jpg)
![Soundboard Gehäuse](docu/20230720_205834.jpg)
![Soundboard Gehäuse](docu/20230727_214800.jpg)
![Soundboard Gehäuse](docu/Screenshot_20230727-233512_Onshape.jpg)
![Soundboard Gehäuse](docu/Screenshot_20230727-233618_Onshape.jpg)

### Innenleben
![Soundboard Elektronik](docu/20230720_202601.jpg)
![Soundboard Elektronik](docu/20230720_220237.jpg)

### Tastenmatrix in Aktion
![Tastenmatrix](docu/Schaltung.jpg)

> Alle Bilder findest du im Ordner `docu/`

---

## ⚙️ Features

- 🎵 **24 Soundtasten** (A–X) in 5×5 Matrix für direkte Soundauswahl
- 🔁 **Sechsfachbelegung:** `Y` = Mode-Taste + Halten → **144 Sounds** (6 Bänke)
- 💾 **DFPlayer Mini** spielt MP3s direkt von SD-Karte
- 📡 **Bluetooth**-Steuerung per Smartphone-App oder Terminal (alle 144 Tracks)
- 🧠 **ESP32** mit frei programmierbarer Logik
- 🧰 [**3D-gedrucktes Gehäuse**](https://cad.onshape.com/documents/51f835b686c64aa4e062ca5b/w/735ce97b22fc647d3e8dc544/e/93c6d67ebc2946beec692255?renderMode=0&uiState=6890fba874e54c0f2372ca89)

---

## 🧠 Schaltung

Erstellt in [Wokwi](https://wokwi.com) (Virtueller Schaltplan: `wokwi_project.json`)

### 🔘 Tastenanschlüsse

| Zeile (row) | ESP32 Pin |
|-------------|-----------|
| R1          | D19       |
| R2          | D18       |
| R3          | D5        |
| R4          | D17       |
| R5          | D16       |

| Spalte (col) | ESP32 Pin |
|--------------|-----------|
| C1           | D32       |
| C2           | D33       |
| C3           | D25       |
| C4           | D26       |
| C5           | D27       |

### 🎧 DFPlayer Mini Anschluss 
Für die korrekte Verkabelung siehe
[DFPlayer Mini Dokumentation](https://www.elektronik-kompendium.de/sites/praxis/bauteil_dfplayer-mini.htm)

| DFPlayer Pin | ESP32 Pin |
|--------------|-----------|
| TX           | GPIO22    |
| RX           | GPIO23    |
| BUSY         | GPIO4     |
| VCC          | 5V        |
| GND          | GND       |
|----| **Endstufe**|
| SPK1     | Left Audio  |
| GND      | GND Audio   |
| SPK2     | Right Audio |


💾 SD-Karte:  
MP3-Dateien im MP3-Verzeichnis, benannt nach `Bank*100 + Position`:
Bank 1 = `0101`–`0124`, Bank 2 = `0201`–`0224`, … Bank 6 = `0601`–`0624` (24 pro Bank).

---

## 🎮 Bedienung

### Tasten (A–X) + Mode-Taste `Y`

`Y` spielt keinen Sound, sondern wählt die Bank-Gruppe. Eine Soundtaste **kurz** drücken oder **halten** wählt innerhalb der Gruppe die Bank:

| `Y`-Status | Soundtaste kurz | Soundtaste halten |
|------------|-----------------|-------------------|
| – (Standard)   | Bank 1 (`0101`–`0124`) | Bank 2 (`0201`–`0224`) |
| `Y` kurz tippen | Bank 3 (`0301`–`0324`) | Bank 4 (`0401`–`0424`) |
| `Y` halten      | Bank 5 (`0501`–`0524`) | Bank 6 (`0601`–`0624`) |

- Tracknummer = **Bank × 100 + Position**. Taste **A** = Position 1, … **X** = Position 24.
- Der gewählte Mode gilt **für den nächsten Sound** und springt danach sofort auf Standard (Bank 1 & 2) zurück. Ohne Tastendruck resettet er automatisch **nach 10 s**; erneutes `Y` schaltet ebenfalls zurück.
- Dieselbe Taste während der Wiedergabe erneut drücken = **Stop**.

### 📡 Bluetooth-Befehle

Zahl (mit `\n`) an das Gerät `das_11lein` senden. Die Tracknummer enthält die Bank direkt – einfach die Nummer senden.

| Eingabe | Aktion |
|---------|--------|
| `101`–`624` | Track direkt abspielen (z. B. `305` = Bank 3, Taste E) |
| `9999` | Stop |
| `9998` | Lautstärke 10 |
| `9997` | Lautstärke 20 |
| `9996` | Lautstärke 30 (max) |
| `9995` | Neustart |

> Die Befehlscodes liegen bei `9999` absteigend – weit über jeder Tracknummer, daher keine Kollision.

Die zuletzt gesetzte Lautstärke wird im Flash (NVS) gespeichert und beim Booten
wiederhergestellt. Beim Verbinden sendet der ESP einmal `READY vol=<n>`, damit die
App den aktuellen Stand kennt. WiFi ist deaktiviert (das Gerät nutzt nur Bluetooth).


---

## 📂 Projektstruktur

```text
/
├── src/
│   ├── MP3/                # Arduino-Quellcode
│   └── main.cpp
├── printfiles/         # STL-Dateien für 3D-Druck
├── docu/               # Fotos, Schaltpläne, Screenshots
└── README.md
