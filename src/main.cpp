#include "Arduino.h"
#include <Keypad.h>
#include <DFPlayerMini_Fast.h>
#include "BluetoothSerial.h"
#include <esp_wifi.h>

// --- Configuration ---
const char *BT_NAME = "das_11lein";  // Bluetooth device name
const int KEYS_PER_BANK = 24;        // sound keys A..X (Y is the mode button)
const int MAX_VOLUME = 30;           // DFPlayer volume range is 0..30
const int START_VOLUME = 30;         // volume set on boot
const int HOLD_TIME_MS = 500;        // press duration that selects the 2nd bank
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
//   101..624 -> play that track directly (bank is encoded in the number)
//   9995..9999 -> commands below (above any track number, descending)
const int CMD_STOP = 9999;       // stop playback
const int CMD_VOLUME_LOW = 9998; // set volume to 10
const int CMD_VOLUME_MID = 9997; // set volume to 20
const int CMD_VOLUME_HIGH = 9996; // set volume to 30 (max)
const int CMD_RESET = 9995;      // restart the ESP32

BluetoothSerial SerialBT;

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
  switch (state)
  {
  case HOLD:
    hold = true;
    break;

  case RELEASED:
  {
    byte bankIndex = modeLevel * 2 + (hold ? 1 : 0);    // 0..5
    hold = false;
    int track = (bankIndex + 1) * 100 + (key - 'A' + 1); // 101..624

    if (isPlaying() && lastKey == key)
    { // same key pressed again → stop (toggle)
      myDFPlayer.stop();
      lastKey = 0;
    }
    else
    {
      lastKey = key;
      playTrack(track);
      if (modeLevel != 0)
        setMode(0); // back to banks 1 & 2 after every played sound
    }
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

  if (!SerialBT.begin(BT_NAME))
  {
    Serial.println(F("Bluetooth init failed"));
  }

  keypad.addEventListener(keypadEvent); // Add an event listener for this keypad
  keypad.setHoldTime(HOLD_TIME_MS);

  Serial.println(F("DFPlayer Mini online."));
  myDFPlayer.volume(START_VOLUME); // Set volume value. From 0 to MAX_VOLUME
}

void loop()
{
  keypad.getKey();

  // Auto-reset the mode to default (banks 1 & 2) 10 s after it was selected.
  if (modeLevel != 0 && millis() - modeSetTime > MODE_TIMEOUT_MS)
    setMode(0);

  // Non-blocking BT line reader (fixed buffer, no heap fragmentation)
  static char btBuffer[8];
  static byte btLen = 0;
  while (SerialBT.available())
  {
    char c = SerialBT.read();
    if (c == '\n')
    {
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
        else if (input == CMD_VOLUME_LOW)
        {
          myDFPlayer.volume(10);
          SerialBT.println("Volume 10");
        }
        else if (input == CMD_VOLUME_MID)
        {
          myDFPlayer.volume(20);
          SerialBT.println("Volume 20");
        }
        else if (input == CMD_VOLUME_HIGH)
        {
          myDFPlayer.volume(MAX_VOLUME);
          SerialBT.println("Volume 30");
        }
        else if (input == CMD_RESET)
        {
          SerialBT.println("reset");
          ESP.restart();
        }
        else if (input / 100 >= 1 && input / 100 <= NUM_BANKS &&
                 input % 100 >= 1 && input % 100 <= KEYS_PER_BANK)
        { // valid track: bank*100 + key, e.g. 101..124, 201..224, ... 601..624
          Serial.println("Playing track: " + String(input));
          SerialBT.println("Playing track: " + String(input));
          playTrack(input);
        }
        else
        {
          SerialBT.println("Unknown: " + String(input));
        }
      }
    }
    else if (c != '\r' && btLen < sizeof(btBuffer) - 1)
    {
      btBuffer[btLen++] = c;
    }
  }
}
