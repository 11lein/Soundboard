#include "Arduino.h"
#include <Keypad.h>
#include <DFPlayerMini_Fast.h>

const byte ROWS = 5; // five rows
const byte COLS = 5; // five columns
char keys[ROWS][COLS] = {
    {'A', 'B', 'C', 'D', 'E'},
    {'F', 'G', 'H', 'I', 'J'},
    {'K', 'L', 'M', 'N', 'O'},
    {'P', 'Q', 'R', 'S', 'T'},
    {'U', 'V', 'W', 'X', 'Y'},
};
byte rowPins[ROWS] = {19, 18, 5, 17, 16};   // connect to the row pinouts of the keypad
byte colPins[COLS] = {32, 33, 25, 26, 27}; // connect to the column pinouts of the keypad

Keypad keypad = Keypad(makeKeymap(keys), rowPins, colPins, ROWS, COLS);
bool hold = false;
char lastKey;

#define FPSerial Serial1

DFPlayerMini_Fast myDFPlayer;

void playTrack(int track)
{
  Serial.print(F("Track: "));
  Serial.println(track);
  myDFPlayer.playFromMP3Folder(track);
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

      if (hold)
      {
        track = track + 25;
      };

      playTrack(track);
    }
    hold = false;

    break;
  }
}

void setup()
{

  FPSerial.begin(9600, SERIAL_8N1, /*rx =*/22, /*tx =*/23);

  Serial.begin(115200);

  keypad.addEventListener(keypadEvent); // Add an event listener for this keypad
  Serial.println();
  Serial.println(F("DFRobot DFPlayer Mini Demo"));
  Serial.println(F("Initializing DFPlayer ... (May take 3~5 seconds)"));

  if (!myDFPlayer.begin(FPSerial, /*debug = */ true))
  { // Use serial to communicate with mp3.
    Serial.println(F("Unable to begin:"));
    Serial.println(F("1.Please recheck the connection!"));
    Serial.println(F("2.Please insert the SD card!"));
    while (true)
    {
      delay(0); // Code to compatible with ESP8266 watch dog.
    }
  }
  Serial.println(F("DFPlayer Mini online."));

  myDFPlayer.volume(20); // Set volume value. From 0 to 30

  Serial.println(F("Files on SD " + myDFPlayer.numSdTracks())); // read all file counts in SD card

  // Serial.println(myDFPlayer.readCurrentFileNumber()); //read current play file number
}

void loop()
{
  char key = keypad.getKey();

  // if (key) {
  //   Serial.println(key - 'A' + 1);
  // }

}
