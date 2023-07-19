#include "Arduino.h"
#include <Keypad.h>
#include "DFRobotDFPlayerMini.h"

const byte ROWS = 5; //five rows
const byte COLS = 5; //five columns
char keys[ROWS][COLS] = {
  {'A', 'B', 'C', 'D', 'E'},
  {'F', 'G', 'H', 'I', 'J'},
  {'K', 'L', 'M', 'N', 'O'},
  {'P', 'Q', 'R', 'S', 'T'},
  {'U', 'V', 'W', 'X', 'Y'},
};
byte rowPins[ROWS] = {32, 33, 25, 26, 27}; //connect to the row pinouts of the keypad
byte colPins[COLS] = {19, 18, 5, 17, 16}; //connect to the column pinouts of the keypad

Keypad keypad = Keypad( makeKeymap(keys), rowPins, colPins, ROWS, COLS );


#define FPSerial Serial1


DFRobotDFPlayerMini myDFPlayer;
void printDetail(uint8_t type, int value);

void setup()
{

  FPSerial.begin(9600, SERIAL_8N1, /*rx =*/22, /*tx =*/23);

  Serial.begin(115200);

  Serial.println();
  Serial.println(F("DFRobot DFPlayer Mini Demo"));
  Serial.println(F("Initializing DFPlayer ... (May take 3~5 seconds)"));
  
  if (!myDFPlayer.begin(FPSerial, /*isACK = */true, /*doReset = */true)) {  //Use serial to communicate with mp3.
    Serial.println(F("Unable to begin:"));
    Serial.println(F("1.Please recheck the connection!"));
    Serial.println(F("2.Please insert the SD card!"));
    while(true){
      delay(0); // Code to compatible with ESP8266 watch dog.
    }
  }
  Serial.println(F("DFPlayer Mini online."));
  
  myDFPlayer.volume(20);  //Set volume value. From 0 to 30
  //myDFPlayer.play(1);  //Play the first mp3
  //Serial.println(myDFPlayer.readFileCountsInFolder(1));
  //Serial.println(myDFPlayer.readFileCountsInFolder(0));
  //Serial.println(myDFPlayer.readFileCountsInFolder(01));

  Serial.println(F("Files on SD " + myDFPlayer.readFileCounts())); //read all file counts in SD card


  // Serial.println(myDFPlayer.readCurrentFileNumber()); //read current play file number
 
}

  
void loop(){
  char key = keypad.getKey();
  int track;
  
  
  if (key){
    Serial.println(key);
    int track = key - 'A' + 1;
    //myDFPlayer.playMp3Folder(key);  //Play the first mp3
    // myDFPlayer.next();

    myDFPlayer.playMp3Folder(track);

    delay(500);
    //Serial.println(myDFPlayer.readCurrentFileNumber()); //read current play file number
    //Serial.println(F("readCurrentFileNumber"));
  }


  // static unsigned long timer = millis();
  
  // if (millis() - timer > 3000) {
  //   timer = millis();
  //   myDFPlayer.next();  //Play next mp3 every 3 second.
  // }
  
  if (myDFPlayer.available()) {
    printDetail(myDFPlayer.readType(), myDFPlayer.read()); //Print the detail message from DFPlayer to handle different errors and states.
  }
}

void printDetail(uint8_t type, int value){
  switch (type) {
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
      switch (value) {
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