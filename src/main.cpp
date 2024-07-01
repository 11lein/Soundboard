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
bool secondSound = false;
char lastKey;

#if !defined(UBRR1H)
#include <SoftwareSerial.h>
SoftwareSerial mySerial(22, 23); // RX, TX
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
// #if !defined(UBRR1H)
  mySerial.begin(9600);

// #else
//   Serial1.begin(9600);
//   myMP3.begin(Serial1, true);
// #endif
  Serial.begin(115200);
  myDFPlayer.begin(mySerial);

  if(!SerialBT.begin("das_11lein")){
    Serial.println("An error occurred initializing Bluetooth");
  }

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

  myDFPlayer.volume(30); // Set volume value. From 0 to 30

  // Serial.println(F("Files on SD " + myDFPlayer.readFileCounts())); // read all file counts in SD card

  // Serial.println(myDFPlayer.readCurrentFileNumber()); //read current play file number
}

void loop()
{
  char key = keypad.getKey();

  if (SerialBT.available())
  {
    int input = SerialBT.readStringUntil('\n').toInt();

    Serial.print("input: ");
    Serial.println(input);

    if (input > 0)
    {
      if (input == 99)
      {
        SerialBT.println("set 2nd");
        secondSound = true;
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
        Serial.println("input: " + input);
        Serial.println("secondSound: " + String(secondSound));
        int track = input;
        if (secondSound == true)
        {
          track = track + 25;
          secondSound = false;
        }
        Serial.println("Playing track: " + String(track));
        SerialBT.println("Playing track: " + String(track));
        playTrack(track);
      }
    }
  }

  delay(20);

}
