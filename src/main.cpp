#include "Arduino.h"
#include <Keypad.h>
#include <DFPlayerMini_Fast.h>

#include "BluetoothSerial.h"

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
char lastKey;

#if !defined(CONFIG_BT_ENABLED) || !defined(CONFIG_BLUEDROID_ENABLED)
#error Bluetooth is not enabled! Please run `make menuconfig` to and enable it
#endif

#if !defined(UBRR1H)
#include <SoftwareSerial.h>
SoftwareSerial mySerial;
// (22, 23); // RX, TX
#endif

// DFRobotDFPlayerMini myDFPlayer;
void printDetail(uint8_t type, int value);

void playTrack(int track)
{
  Serial.print(F("Track: "));
  Serial.println(track);
  // myDFPlayer.playMp3Folder(track);

  delay(500);
}

void keypadEvent(KeypadEvent key)
{
  int track;

  track = key - 'A' + 1;
  KeyState state = keypad.getState();

  switch (state)
  {
  case HOLD:
    // Serial.println("state hold");
    hold = true;
    break;
  case PRESSED:
    // Serial.println("state pressed");
    // playTrack(track);

    break;

  case RELEASED:
    // Serial.println("state released");
    // Serial.print("State: ");
    // Serial.println(myDFPlayer.readState());
    if (myDFPlayer.isPlaying() && lastKey == key)
    { // Busy
      Serial.println("Busy & Stopping");
      myDFPlayer.stop();
    }
    else
    {
      lastKey = key;
    }

    if (hold)
    {
      track = track + 25;
    };

    playTrack(track);
    // }
    hold = false;

    break;
  }
}

void setup()
{
#if !defined(UBRR1H)
  mySerial.begin(9600);
  myDFPlayer.begin(mySerial, true);
#else
  Serial1.begin(9600);
  myMP3.begin(Serial1, true);
#endif
  Serial.begin(115200);

  keypad.addEventListener(keypadEvent); // Add an event listener for this keypad
  Serial.println();
  Serial.println(F("DFRobot DFPlayer Mini Demo"));
  Serial.println(F("Initializing DFPlayer ... (May take 3~5 seconds)"));

  // if (!myDFPlayer.begin(FPSerial, /*isACK = */ true, /*doReset = */ true))
  // { // Use serial to communicate with mp3.
  //   Serial.println(F("Unable to begin:"));
  //   Serial.println(F("1.Please recheck the connection!"));
  //   Serial.println(F("2.Please insert the SD card!"));
  //   while (true)
  //   {
  //     delay(0); // Code to compatible with ESP8266 watch dog.
  //   }
  // }
  Serial.println(F("DFPlayer Mini online."));

  // myDFPlayer.volume(20); // Set volume value. From 0 to 30

  // Serial.println(F("Files on SD " + myDFPlayer.readFileCounts())); // read all file counts in SD card

  // Serial.println(myDFPlayer.readCurrentFileNumber()); //read current play file number
}

void loop()
{
  char key = keypad.getKey();

  if (SerialBT.available())
  {
    String input = SerialBT.readStringUntil('\n');

    if (input)
    {

      if (input == "hold")
      {
        hold = true;
      }
      else if (input == "stop")
      {
        Serial.println("input: " + input);

        // myDFPlayer.stop();
      }
      else if (input == "+")
      {
        Serial.println("input: " + input);

        // myDFPlayer.volumeUp();
      }
      else if (input == "-")
      {
        Serial.println("input: " + input);

        // myDFPlayer.volumeDown();
      }
      else if (input == "reset")
      {
        Serial.println("input: " + input);

        ESP.restart();
      }
      else if (input.toInt())
      {
        Serial.println("input: " + input);
        int track = input.toInt();
        if (hold == true)
        {
          track = track + 25;
          hold = false;
        }
        Serial.println("Playing track: " + String(track));
        playTrack(track);
      }
    }
  }

  delay(20);

  // if (key) {
  //   Serial.println(key - 'A' + 1);
  // }
}
