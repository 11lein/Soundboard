#include "Arduino.h"
#include <Keypad.h>
#include "DFRobotDFPlayerMini.h"

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

DFRobotDFPlayerMini myDFPlayer;
void printDetail(uint8_t type, int value);

void playTrack(int track)
{
  Serial.print(F("Track: "));
  Serial.println(track);
  myDFPlayer.playMp3Folder(track);
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
    if (myDFPlayer.readState() == 1 && lastKey == key)
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

  if (!myDFPlayer.begin(FPSerial, /*isACK = */ true, /*doReset = */ true))
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

  Serial.println(F("Files on SD " + myDFPlayer.readFileCounts())); // read all file counts in SD card

  // Serial.println(myDFPlayer.readCurrentFileNumber()); //read current play file number
}

void loop()
{
  char key = keypad.getKey();

  // if (key) {
  //   Serial.println(key - 'A' + 1);
  // }

  // if (myDFPlayer.available())
  // {
  //   printDetail(myDFPlayer.readType(), myDFPlayer.read()); // Print the detail message from DFPlayer to handle different errors and states.
  // }
}

// Taking care of some special events.

//   KeyState state = keypad.getState();
//   int track;

//   if (key){
//     Serial.println(key);
//     track = key - 'A' + 1;

//     Serial.print("State: ");
//     Serial.println(state);

//     if (state == HOLD) {
//       track = track + 25;
//     }

//     Serial.print(F("Track: "));
//     Serial.println(track);

//     myDFPlayer.playMp3Folder(track);

//     delay(500);
//     //Serial.println(myDFPlayer.readCurrentFileNumber()); //read current play file number
//     //Serial.println(F("readCurrentFileNumber"));
//   }

//   // static unsigned long timer = millis();

//   // if (millis() - timer > 3000) {
//   //   timer = millis();
//   //   myDFPlayer.next();  //Play next mp3 every 3 second.
//   // }

//   if (myDFPlayer.available()) {
//     printDetail(myDFPlayer.readType(), myDFPlayer.read()); //Print the detail message from DFPlayer to handle different errors and states.
//   }
// }

void printDetail(uint8_t type, int value)
{
  switch (type)
  {
  case TimeOut:
    Serial.println(F("Time Out!"));
    break;
  case WrongStack:
    Serial.println(F("Stack Wrong!"));
    break;
  case DFPlayerCardInserted:
    Serial.println(F("Card Inserted!"));
    break;
  case DFPlayerCardRemoved:
    Serial.println(F("Card Removed!"));
    break;
  case DFPlayerCardOnline:
    Serial.println(F("Card Online!"));
    break;
  case DFPlayerUSBInserted:
    Serial.println("USB Inserted!");
    break;
  case DFPlayerUSBRemoved:
    Serial.println("USB Removed!");
    break;
  case DFPlayerPlayFinished:
    Serial.print(F("Number:"));
    Serial.print(value);
    Serial.println(F(" Play Finished!"));
    break;
  case DFPlayerError:
    Serial.print(F("DFPlayerError:"));
    switch (value)
    {
    case Busy:
      Serial.println(F("Card not found"));
      break;
    case Sleeping:
      Serial.println(F("Sleeping"));
      break;
    case SerialWrongStack:
      Serial.println(F("Get Wrong Stack"));
      break;
    case CheckSumNotMatch:
      Serial.println(F("Check Sum Not Match"));
      break;
    case FileIndexOut:
      Serial.println(F("File Index Out of Bound"));
      break;
    case FileMismatch:
      Serial.println(F("Cannot Find File"));
      break;
    case Advertise:
      Serial.println(F("In Advertise"));
      break;
    default:
      break;
    }
    break;
  default:
    break;
  }
}