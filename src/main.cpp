#include "Arduino.h"
#include <Keypad.h>
#include <DFPlayerMini_Fast.h>
#include "BluetoothSerial.h"

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
bool secondSound = false;
char lastKey = 0;

HardwareSerial mySerial(2); // UART2, RX=22 TX=23

DFPlayerMini_Fast myDFPlayer;

void playTrack(int track)
{
  Serial.print(F("Track: "));
  Serial.println(track);
  myDFPlayer.playFromMP3Folder(track);
}

void keypadEvent(KeypadEvent key)
{
  int track = key - 'A' + 1;
  KeyState state = keypad.getState();

  switch (state)
  {
  case HOLD:
    hold = true;
    break;

  case RELEASED:
    if (hold) track += 25;
    hold = false;

    if (myDFPlayer.isPlaying() && lastKey == key)
    { // same key pressed again → stop (toggle)
      myDFPlayer.stop();
      lastKey = 0;
    }
    else
    {
      lastKey = key;
      playTrack(track);
    }
    break;

  default:
    break;
  }
}

void setup()
{
  Serial.begin(115200);
  mySerial.begin(9600, SERIAL_8N1, 22, 23);

  if (!myDFPlayer.begin(mySerial))
  {
    Serial.println(F("DFPlayer not found - check connection and SD card"));
    while (true) delay(1);
  }

  if (!SerialBT.begin("das_11lein"))
  {
    Serial.println(F("Bluetooth init failed"));
  }

  keypad.addEventListener(keypadEvent); // Add an event listener for this keypad
  keypad.setHoldTime(500);

  Serial.println(F("DFPlayer Mini online."));
  myDFPlayer.volume(30); // Set volume value. From 0 to 30
}

void loop()
{
  keypad.getKey();

  // Non-blocking BT line reader
  static String btBuffer = "";
  while (SerialBT.available())
  {
    char c = SerialBT.read();
    if (c == '\n')
    {
      int input = btBuffer.toInt();
      btBuffer = "";

      Serial.print(F("BT input: "));
      Serial.println(input);

      if (input > 0)
      {
        if (input == 99)
        {
          secondSound = true;
          SerialBT.println("set 2nd");
        }
        else if (input == 98)
        {
          myDFPlayer.stop();
          SerialBT.println("Stopped");
        }
        else if (input == 97)
        {
          myDFPlayer.volume(20);
          SerialBT.println("Volume 20");
        }
        else if (input == 96)
        {
          myDFPlayer.volume(10);
          SerialBT.println("Volume 10");
        }
        else if (input == 95)
        {
          SerialBT.println("reset");
          ESP.restart();
        }
        else
        {
          int track = input;
          if (secondSound)
          {
            track += 25;
            secondSound = false;
          }
          Serial.println("Playing track: " + String(track));
          SerialBT.println("Playing track: " + String(track));
          playTrack(track);
        }
      }
    }
    else if (c != '\r')
    {
      btBuffer += c;
    }
  }
}
