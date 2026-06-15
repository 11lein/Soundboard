#include "Arduino.h"
#include <Keypad.h>
#include <DFPlayerMini_Fast.h>
#include "BluetoothSerial.h"
#include <esp_wifi.h>
#include <Preferences.h>

// --- Configuration ---
const char *BT_NAME = "das_11lein";  // Bluetooth device name
const int KEYS_PER_BANK = 24;        // sound keys A..X (Y is the mode button)
const int MAX_VOLUME = 30;           // DFPlayer volume range is 0..30
const int START_VOLUME_PCT = 100;    // boot volume as percent (100% = level 30)
const int HOLD_TIME_MS = 250;        // press duration that selects the 2nd bank
const int BUSY_PIN = 4;              // DFPlayer BUSY pin: LOW while a track plays
const char MODE_KEY = 'Y';           // this key selects the bank group, no sound
const unsigned long MODE_TIMEOUT_MS = 10000; // auto-reset to mode 0 after 10 s

// Mode (selected with the Y key) chooses a pair of banks; the sound key's
// hold then picks one of the pair. 24 keys x 6 banks = 144 tracks.
//   mode 0: banks 1 & 2   (Y not pressed, default)
//   mode 1: banks 3 & 4   (Y tapped)
//   mode 2: banks 5 & 6   (Y held)

const int NUM_BANKS = 6; // 6 banks of 24 keys = 144 tracks

// Track numbering encodes bank + position: track = bank*100 + key (1..24).
//   bank 1: 101..124   bank 2: 201..224   ...   bank 6: 601..624
// Files on the SD card are named accordingly (0101_*.mp3 ... 0624_*.mp3).

// Bluetooth protocol:
//   101..624   -> play that track directly (bank is encoded in the number)
//   7000..7100 -> set volume to (input-7000) percent (0..100%)
//   9995..9999 -> commands below (above any track number, descending)
const int CMD_VOLUME_SET_BASE = 7000; // 7000+pct sets volume to pct (0..100)
const int CMD_STOP = 9999;       // stop playback
const int CMD_VOLUME_LOW = 9998; // set volume to ~33% (compat: old "10")
const int CMD_VOLUME_MID = 9997; // set volume to ~67% (compat: old "20")
const int CMD_VOLUME_HIGH = 9996; // set volume to 100% (compat: old "30")
const int CMD_RESET = 9995;      // restart the ESP32

BluetoothSerial SerialBT;

// Persistent storage for the last-used volume (survives reboots).
Preferences prefs;
int currentVolumePct = START_VOLUME_PCT; // active volume as percent (0..100)
volatile bool btClientConnected = false; // set by the SPP callback on connect

// SPP event callback: flag a fresh connection so loop() can greet the client.
void btEventCallback(esp_spp_cb_event_t event, esp_spp_cb_param_t *param)
{
  if (event == ESP_SPP_SRV_OPEN_EVT)
    btClientConnected = true;
}

const byte ROWS = 5; // five rows
const byte COLS = 5; // five columns
char keys[ROWS][COLS] = {
    {'A', 'B', 'C', 'D', 'E'},
    {'F', 'G', 'H', 'I', 'J'},
    {'K', 'L', 'M', 'N', 'O'},
    {'P', 'Q', 'R', 'S', 'T'},
    {'U', 'V', 'W', 'X', 'Y'},
};
byte rowPins[ROWS] = {19, 18, 5, 17, 16};  // connect to the row pinouts of the keypad
byte colPins[COLS] = {32, 33, 25, 26, 27}; // connect to the column pinouts of the keypad

Keypad keypad = Keypad(makeKeymap(keys), rowPins, colPins, ROWS, COLS);
bool hold = false;
char lastKey = 0;

byte modeLevel = 0;             // 0,1,2 -> bank pairs (1&2, 3&4, 5&6)
bool yHold = false;            // true while the Y press is a long hold
unsigned long modeSetTime = 0; // millis() when the mode was last changed

HardwareSerial mySerial(2); // UART2, RX=22 TX=23

DFPlayerMini_Fast myDFPlayer;

// Read playback state from the BUSY pin (instant) instead of a serial query.
// BUSY is LOW while a track is playing, HIGH when idle.
bool isPlaying()
{
  return digitalRead(BUSY_PIN) == LOW;
}

// Pending NVS save for the volume. Flash writes block ~10-20 ms, so we don't
// write on every +5/-5 step; loop() persists the value once it has settled.
bool volumeDirty = false;
unsigned long volumeChangedAt = 0;
const unsigned long VOLUME_SAVE_DELAY_MS = 1500;

// Apply a volume given in percent (0..100), map it to the DFPlayer's 0..30
// range, and mark it for a deferred NVS save (so rapid changes don't block).
void applyVolumePct(int pct)
{
  if (pct < 0) pct = 0;
  if (pct > 100) pct = 100;
  currentVolumePct = pct;
  int vol = (pct * MAX_VOLUME + 50) / 100; // percent -> 0..30 (rounded)
  myDFPlayer.volume(vol);
  volumeDirty = true;
  volumeChangedAt = millis();
}

void playTrack(int track)
{
  Serial.print(F("Track: "));
  Serial.println(track);
  myDFPlayer.playFromMP3Folder(track);
}

void setMode(byte level)
{
  modeLevel = level;
  modeSetTime = millis();
  Serial.print(F("Mode: "));
  Serial.println(modeLevel); // 0=banks 1&2, 1=banks 3&4, 2=banks 5&6
}

void keypadEvent(KeypadEvent key)
{
  KeyState state = keypad.getState();

  // --- Y is the mode button (no sound). Tap -> mode 1, hold -> mode 2.
  //     Pressing it again toggles back to mode 0 (also auto-resets after 10s).
  if (key == MODE_KEY)
  {
    switch (state)
    {
    case HOLD:
      yHold = true;
      break;
    case RELEASED:
      if (yHold)
        setMode(modeLevel == 2 ? 0 : 2); // Y held -> banks 5 & 6
      else
        setMode(modeLevel == 1 ? 0 : 1); // Y tapped -> banks 3 & 4
      yHold = false;
      break;
    default:
      break;
    }
    return;
  }

  // --- Sound keys A..X ---
  // Play on PRESS for minimal latency: a tap immediately plays bank A of the
  // current group. If the key is then held past HOLD_TIME_MS, switch to bank B.
  // (No same-key stop toggle here: at press time we cannot tell a "stop" from a
  // "hold for bank B", and it relied on the unreliable BUSY pin anyway. Stop is
  // done from the app; pressing the same key again simply restarts the sound.)
  const int pos = key - 'A' + 1; // 1..24
  switch (state)
  {
  case PRESSED:
  { // default tap → bank A of the current group, right away
    hold = false;
    lastKey = key;
    playTrack((modeLevel * 2 + 1) * 100 + pos); // bank A
    break;
  }

  case HOLD:
  { // held long enough → switch from bank A to bank B
    if (lastKey == key)
    {
      hold = true;
      playTrack((modeLevel * 2 + 2) * 100 + pos); // bank B
    }
    break;
  }

  case RELEASED:
  { // sound already started on press/hold; reset the mode after a played sound
    if (lastKey == key && modeLevel != 0)
      setMode(0); // back to banks 1 & 2 after every played sound
    break;
  }

  default:
    break;
  }
}

void setup()
{
  Serial.begin(115200);

  // WiFi is unused. The sketch never calls WiFi.begin(), so the radio is never
  // brought up, but we stop+deinit the driver explicitly to guarantee it draws
  // no power and to document the intent. These are harmless no-ops returning
  // ESP_ERR_WIFI_NOT_INIT if WiFi was never started. (Using the ESP-IDF calls
  // directly avoids linking the heavy Arduino <WiFi.h> library.)
  esp_wifi_stop();
  esp_wifi_deinit();

  mySerial.begin(9600, SERIAL_8N1, 22, 23);
  pinMode(BUSY_PIN, INPUT_PULLUP);

  // Try to bring up the DFPlayer; reboot after a few failed attempts rather
  // than hanging forever on a transient SD-card or power glitch at cold boot.
  byte attempts = 0;
  while (!myDFPlayer.begin(mySerial))
  {
    Serial.println(F("DFPlayer not found - check connection and SD card"));
    if (++attempts >= 5)
    {
      Serial.println(F("DFPlayer init failed, restarting..."));
      ESP.restart();
    }
    delay(1000);
  }

  SerialBT.register_callback(btEventCallback); // greet clients on connect
  if (!SerialBT.begin(BT_NAME))
  {
    Serial.println(F("Bluetooth init failed"));
  }

  keypad.addEventListener(keypadEvent); // Add an event listener for this keypad
  keypad.setHoldTime(HOLD_TIME_MS);

  Serial.println(F("DFPlayer Mini online."));

  // Restore the last-used volume from NVS (default START_VOLUME_PCT on 1st boot).
  prefs.begin("soundboard", false);
  applyVolumePct(prefs.getInt("volpct", START_VOLUME_PCT));
  volumeDirty = false; // just restored – nothing to write back
}

void loop()
{
  keypad.getKey();

  // Auto-reset the mode to default (banks 1 & 2) 10 s after it was selected.
  if (modeLevel != 0 && millis() - modeSetTime > MODE_TIMEOUT_MS)
    setMode(0);

  // Greet a freshly connected client with the current state so the app can
  // show the real volume instead of guessing. Set by the SPP callback.
  if (btClientConnected)
  {
    btClientConnected = false;
    SerialBT.println("READY vol=" + String(currentVolumePct));
  }

  // Persist a settled volume change to NVS (deferred to avoid blocking flash
  // writes during rapid +5/-5 tapping).
  if (volumeDirty && millis() - volumeChangedAt > VOLUME_SAVE_DELAY_MS)
  {
    prefs.putInt("volpct", currentVolumePct);
    volumeDirty = false;
  }

  // Non-blocking BT line reader (fixed buffer, no heap fragmentation).
  // overflow=true marks a line longer than the buffer: we keep discarding its
  // bytes until the next '\n' so a too-long line is dropped instead of being
  // truncated and misinterpreted as a valid (but wrong) number.
  static char btBuffer[8];
  static byte btLen = 0;
  static bool overflow = false;
  while (SerialBT.available())
  {
    char c = SerialBT.read();
    if (c == '\n')
    {
      if (overflow)
      {
        SerialBT.println("Ignored (too long)");
        overflow = false;
        btLen = 0;
        continue;
      }
      btBuffer[btLen] = '\0';
      int input = atoi(btBuffer);
      btLen = 0;

      Serial.print(F("BT input: "));
      Serial.println(input);

      if (input > 0)
      {
        if (input == CMD_STOP)
        {
          myDFPlayer.stop();
          SerialBT.println("Stopped");
        }
        else if (input >= CMD_VOLUME_SET_BASE && input <= CMD_VOLUME_SET_BASE + 100)
        { // set volume to an exact percentage (0..100%)
          applyVolumePct(input - CMD_VOLUME_SET_BASE);
          SerialBT.println("Volume " + String(currentVolumePct) + "%");
        }
        else if (input == CMD_VOLUME_LOW)
        {
          applyVolumePct(33);
          SerialBT.println("Volume 33%");
        }
        else if (input == CMD_VOLUME_MID)
        {
          applyVolumePct(67);
          SerialBT.println("Volume 67%");
        }
        else if (input == CMD_VOLUME_HIGH)
        {
          applyVolumePct(100);
          SerialBT.println("Volume 100%");
        }
        else if (input == CMD_RESET)
        {
          SerialBT.println("reset");
          ESP.restart();
        }
        else if ((input / 100 >= 1 && input / 100 <= NUM_BANKS &&
                  input % 100 >= 1 && input % 100 <= KEYS_PER_BANK) ||
                 (input >= 700 && input < CMD_VOLUME_SET_BASE))
        { // bank track (101..624) OR an app-only extra/parked track (>=700,
          // not reachable from the keypad; played from the app's list view)
          Serial.println("Playing track: " + String(input));
          playTrack(input); // sends "PLAY <n>" to the app itself
        }
        else
        {
          SerialBT.println("Unknown: " + String(input));
        }
      }
    }
    else if (c != '\r')
    {
      if (btLen < sizeof(btBuffer) - 1)
        btBuffer[btLen++] = c;
      else
        overflow = true; // line exceeds the buffer → discard until newline
    }
  }
}
