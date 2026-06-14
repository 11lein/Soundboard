# 📱 Soundboard Remote (Flutter, Android)

Flutter-App zur **Fernsteuerung des ESP32-Soundboards über Bluetooth Classic (SPP)**.
Spiegelt das physische Gerät: 6 Bänke, je ein 5×5-Raster mit den echten Tastenfarben.

<p align="center">
  <img src="docs/screenshot.png" alt="Soundboard Remote – Bank 1 (Tracks 101–124)" width="300">
</p>

## Funktion

- 🔵 **Verbinden** mit dem gekoppelten Gerät `das_11lein` (gekoppelte Geräte werden
  gelistet – vorher einmal in den Android-Bluetooth-Einstellungen koppeln).
- 🎛️ **6 Bänke** wählbar; pro Bank ein 5×5-Raster (Position unten links beginnend,
  oben rechts = Mode-Taste, nicht belegbar), eingefärbt nach der physischen
  Tastenfarbe.
- ▶️ Tippen sendet die Tracknummer **`Bank*100 + Position`** (`101`–`624`).
- 🔈 **Lautstärke** 10/20/30, ⏹ **Stop**, ↻ **Neustart** – als Befehle `9999`
  absteigend (siehe Firmware-Protokoll).

## Architektur

- `lib/soundboard_controller.dart` – Verbindungs-/Sende-Logik (`ChangeNotifier`),
  spricht über den Platform-Channel `soundboard/bt`.
- `lib/home_page.dart` – UI (Verbindungsleiste, Bank-Auswahl, Raster, Steuerung).
- `android/.../MainActivity.kt` – nativer **SPP-Channel** (BluetoothSocket via
  RFCOMM-UUID `00001101-…`). Bewusst kein Drittanbieter-BT-Plugin, damit der
  Build mit aktuellem AGP/Gradle sauber durchläuft.
- `assets/key-colors.json` – Tastenfarben (Kopie aus dem `mp3-sorter`-Tool).

Berechtigung: `BLUETOOTH_CONNECT` (Android 12+) wird zur Laufzeit über
`permission_handler` angefragt; nur gekoppelte Geräte, kein Scan/Location nötig.

## App installieren

### Android – APK direkt (empfohlen, kein Google Play nötig)

Eine fertig gebaute APK liegt im Repo unter `app/soundboard-remote.apk`.

1. APK auf das Telefon übertragen (USB-Kabel, Bluetooth-Dateiübertragung oder
   Cloud-Dienst deiner Wahl).
2. Auf dem Telefon: **Einstellungen → Apps → Sonderrechte → Unbekannte Quellen**
   (auf manchen Geräten: *Unbekannte Apps installieren*) für den Datei-Manager oder
   Browser aktivieren, mit dem du die APK öffnest.
3. Die APK antippen → installieren.
4. Nach der Installation einmal den Bluetooth-Namen `das_11lein` in den
   Android-Bluetooth-Einstellungen koppeln, dann die App öffnen.

> Android-Hilfe: [support.google.com – Apps aus anderen Quellen installieren](https://support.google.com/android/answer/7680439)

### iPhone / iOS – nicht direkt unterstützt

Bluetooth Classic (SPP/RFCOMM) wird von iOS **nicht unterstützt** – Apple erlaubt
App-seitig nur Bluetooth Low Energy (BLE) sowie proprietäre MFi-Protokolle.
Der ESP32 nutzt klassisches SPP, das auf iPhone grundsätzlich nicht aus Apps
heraus erreichbar ist (weder über den App Store noch per Sideload).

Optionen, falls du doch ein iOS-Gerät nutzen möchtest:

- **ESP32 auf BLE umrüsten**: Die Firmware auf BLE-UART (z. B. Nordic UART Service)
  umstellen; dann kann eine angepasste Flutter-App über `flutter_blue_plus` sprechen.
  Aufwand: mittlerer Firmware-Umbau.
- **Webbrowser-Steuerung**: ESP32 als WLAN-Access-Point mit einer kleinen
  Web-Seite; dann reicht Safari auf dem iPhone. Kein Bluetooth nötig.

> iOS-Referenz zu Bluetooth-Einschränkungen: [developer.apple.com – Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)

---

## Selbst bauen & Installieren

> ⚠️ **Wichtig:** Android-/Gradle-Builds scheitern an Leerzeichen/Klammern im Pfad.
> Dieses Repo liegt unter `…/Soundboard (Kopie)/`, daher **nicht hier direkt
> bauen**. Projekt an einen Pfad **ohne Leerzeichen** kopieren (z. B.
> `~/soundboard_remote`) und dort bauen.

Voraussetzungen: Flutter SDK, Android SDK (`platforms;android-35`,
`build-tools;35.0.0`), **JDK 17** (eine JRE reicht nicht – `javac` nötig).

```bash
cp -r app ~/soundboard_remote && cd ~/soundboard_remote
export JAVA_HOME=/pfad/zur/jdk-17
flutter pub get
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
# auf ein angeschlossenes Telefon:
flutter install                    # oder: adb install -r app-release.apk
```

## Protokoll (muss zur Firmware passen)

| Senden | Wirkung |
|--------|---------|
| `101`–`624` | Track abspielen (`Bank*100 + Position`) |
| `9999` | Stop |
| `9998` / `9997` / `9996` | Lautstärke 10 / 20 / 30 |
| `9995` | Neustart |

Jeweils als ASCII-Zahl mit abschließendem `\n`.
