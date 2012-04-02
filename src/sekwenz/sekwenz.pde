/*
	Sekwenz
	
	0.5.2
		- 3 pattern storage slots
		- fewer global variables
	
	0.5.1
		- improved control pattern (no more need for simultanious presses)
		- bugfixes
		- some refactoring for efficiency
		- 2 bytes for storing note on/off (replaces 17 element array)
		- preparations for multiple storage slots
	
	0.5.0
		- consistent controls:
			- encoder is used for selection
			- enter button used for navigating to child and 'activating' menu items 
			- exit button used for navigating to ancestor
	
	0.4.0
		- added pattern storage on EEPROM
	
	0.3.0
		- added menu: octave selection
	
	0.2.1
		- refactoring for efficiency

	0.2.0
		- added playmode: randomize
		
	0.1.0
		- code refactoring for efficiency and readability
		- updated for use with Arduino 1.0
	    - based on simplenZAR v 0.8.16 (http://www.roebbeling.de/wordpress/?p=85)
		
*/

#include <EEPROM.h>

#define FIRST 0
#define PROPERTY_ON 0
#define PROPERTY_PITCH 1
#define PROPERTY_VELOCITY 2
#define PROPERTY_NONE 3
#define NUMBER_OF_PROPERTIES 3
#define MENU_TEMPO 0
#define MENU_PLAYMODE 1
#define MENU_MIDI_OCTAVE 2
#define MENU_LOAD 3
#define MENU_SAVE 4
#define NUMBER_OF_MENUS 5
#define MODE_8 0
#define MODE_16 1
#define MODE_MODULATE 2
#define MODE_RANDOMIZE 3
#define NUMBER_OF_MODES 4
#define STATE_SELECTING_MENU 0
#define STATE_EDITING_MENU 1
#define STATE_SELECTING_STEP 2
#define STATE_SELECTING_PROPERTY 3
#define STATE_EDITING_PROPERTY 4
#define MIDI_NOTE_ON 0x90
#define MIDI_NOTE_OFF 0x80
#define MIDI_BASE_NOTE 24
#define NUMBER_OF_MIDI_OCTAVES 5
#define NUMBER_OF_SLOTS 3

byte selectedOctave = FIRST;
byte selectedProperty = PROPERTY_NONE;
byte selectedMenuItem = MENU_TEMPO;
byte selectedStep = FIRST;
byte selectedSlot = 0;
byte playMode = MODE_8;
byte playPosition = FIRST;
byte modulationPosition = FIRST;
byte state = STATE_SELECTING_STEP;

byte beat = 90;
byte lowNoteByte = 0;
byte highNoteByte = 0;

byte pitch[16];
byte velocity[16];
byte modulate[8];

byte button1 = A0;
byte button2 = A1;
byte encoder = A2;

void setup() {
    for (int pin = 3; pin <= 13; pin++) pinMode(pin, OUTPUT);

    pinMode(button1, INPUT);
    pinMode(button2, INPUT);
    pinMode(encoder, INPUT);

    for (int step = 1; step <= 16; step++) {
        pitch[step] = 0;
        velocity[step] = 60;
		if(step <= 9) modulate[step] = 0;
    }

	lowNoteByte = 1;
    pitch[1] = 0;
    velocity[1] = 55;

    Serial.begin(31250);
}
void updateLedDisplay(byte playPosition, byte selectedStep) {
	static boolean blink = false;
	
	for (int i = 3; i <= 13; i++) digitalWrite(i, LOW);
  
	if (state == STATE_EDITING_MENU || state == STATE_SELECTING_MENU) {
		if (++selectedProperty > NUMBER_OF_PROPERTIES) selectedProperty = FIRST;
		digitalWrite(3 + selectedProperty, HIGH);
		digitalWrite(6 + selectedMenuItem, HIGH);
		if (selectedMenuItem == MENU_MIDI_OCTAVE) {
			digitalWrite(13 - NUMBER_OF_MIDI_OCTAVES + selectedOctave, HIGH);
		} else if (selectedMenuItem == MENU_PLAYMODE) {
			digitalWrite(13 - NUMBER_OF_MODES + playMode, HIGH);
		}	 else if (selectedMenuItem == MENU_SAVE || selectedMenuItem == MENU_LOAD) {
			digitalWrite(13 - NUMBER_OF_SLOTS + selectedSlot, HIGH);
		}		
	} else {
		boolean hi8 = selectedStep > 7;
		
		if ((playPosition > 7 && hi8) || (playPosition < 8 && !hi8)) {
			if(playPosition > 7) playPosition -= 8;
			digitalWrite(6 + playPosition, HIGH);
		}

		if (hi8) {
			if (playMode == MODE_MODULATE) digitalWrite(6 + modulationPosition, HIGH);
			selectedStep -= 8;
		}

		digitalWrite(6 + selectedStep, HIGH);
		
		blink = !blink;
		if (state != STATE_EDITING_PROPERTY || blink) {
			if ((selectedProperty == PROPERTY_ON && !hi8) || (selectedProperty == PROPERTY_PITCH && hi8) || ( selectedProperty == PROPERTY_VELOCITY && hi8)) digitalWrite(5, HIGH);
			if ((selectedProperty == PROPERTY_PITCH && !hi8) || (selectedProperty == PROPERTY_ON && hi8) || ( selectedProperty == PROPERTY_VELOCITY && hi8)) digitalWrite(4, HIGH);
			if ((selectedProperty == PROPERTY_VELOCITY && !hi8) || (selectedProperty == PROPERTY_ON && hi8) || ( selectedProperty == PROPERTY_PITCH && hi8)) digitalWrite(3, HIGH);
		}
		if (selectedProperty == PROPERTY_NONE && hi8) {
			for (int pin = 3; pin <= 5; pin++) digitalWrite(pin, HIGH);
		}
		
	}
}
void updateMIDI() {
	static byte currentNote = 0;
	
	sendMIDI(MIDI_NOTE_OFF, currentNote, 0);

	byte baseNote = MIDI_BASE_NOTE + (selectedOctave * 12);

	if (playMode == MODE_RANDOMIZE) {
		playPosition = rand() % 7;
	} else {
		if (++playPosition > getNumberOfSteps()) {
			playPosition = FIRST;
			if (++modulationPosition > 7) modulationPosition = FIRST;
		}
		if (playMode == MODE_MODULATE) baseNote += modulate[modulationPosition];
	}
	
	byte pos = playPosition;
	byte B = lowNoteByte;
	
	if(pos > 7) {
		pos -= 8;
		B = highNoteByte;
	} 
		
	if(bitRead(B, pos) == 1) {
		currentNote = baseNote + pitch[playPosition];
		sendMIDI(MIDI_NOTE_ON, currentNote, velocity[playPosition]);
	}
}

void sendMIDI(byte cmd, byte pitch, byte velocity) {
	Serial.write(cmd);
	Serial.write(pitch);
	Serial.write(velocity);
}
void procesUserInput() {
	static boolean button1Down = false;
	static boolean button2Down = false;
	
	boolean A = digitalRead(button1);
	boolean B = digitalRead(button2);	
	boolean exitPressed = A && !button1Down;
	boolean enterPressed = B && !button2Down;
	button1Down = A;
	button2Down = B;
	
	if (exitPressed) {
		if(state == STATE_SELECTING_STEP) selectedMenuItem = FIRST;
		
		if (state == STATE_SELECTING_MENU || state == STATE_SELECTING_PROPERTY) {
			state = STATE_SELECTING_STEP;
		} else if (state == STATE_EDITING_MENU || state == STATE_SELECTING_STEP) {
			state = STATE_SELECTING_MENU;
		} else if (state == STATE_EDITING_PROPERTY) {
			state = STATE_SELECTING_PROPERTY;
		}
		
		if(state == STATE_SELECTING_STEP || state == STATE_SELECTING_MENU) selectedProperty = PROPERTY_NONE;
	} else if (enterPressed) {		
		if (state == STATE_SELECTING_MENU) {
			state = STATE_EDITING_MENU;
		} else if (state == STATE_SELECTING_STEP) {  
			state = STATE_SELECTING_PROPERTY;
		} else if (state == STATE_SELECTING_PROPERTY) {
			state = STATE_EDITING_PROPERTY;
		} else if (state == STATE_EDITING_MENU) {
			if (selectedMenuItem == MENU_SAVE) {
				save(selectedSlot);
			} else if (selectedMenuItem == MENU_LOAD) {
				load(selectedSlot);
			}
		}
	}
	
	if (state == STATE_SELECTING_PROPERTY) {
		selectedProperty = getEncoderPosition(NUMBER_OF_PROPERTIES);
	} else if (state == STATE_SELECTING_MENU) {
		selectedMenuItem = getEncoderPosition(NUMBER_OF_MENUS); 
	} else if (state == STATE_SELECTING_STEP) {
		if (playMode != MODE_MODULATE) {
			selectedStep = getEncoderPosition(getNumberOfSteps());  
		} else {
			selectedStep = getEncoderPosition(15);  
		}
	} else if (state == STATE_EDITING_PROPERTY) {
		if(selectedProperty == PROPERTY_ON) {
			if (selectedStep <= getNumberOfSteps()) {
				byte pos = selectedStep;
				if(pos > 7) {
					pos -= 8;
					bitWrite(highNoteByte, pos, getEncoderPosition(2));
				} else {
					bitWrite(lowNoteByte, pos, getEncoderPosition(2));
				}
			} else {
				modulate[selectedStep - 7] = getEncoderPosition(36);
			}
		} else if(selectedProperty == PROPERTY_PITCH) {
			pitch[selectedStep] = getEncoderPosition(36);
		} else if(selectedProperty == PROPERTY_VELOCITY) {
			velocity[selectedStep] = getEncoderPosition(128);
		}
	} else if (state == STATE_EDITING_MENU) {
		if(selectedMenuItem == MENU_TEMPO) {
			beat = 90 + (30 * getEncoderPosition(3));
		} else if(selectedMenuItem == MENU_PLAYMODE) {
			playMode = getEncoderPosition(NUMBER_OF_MODES);
		} else if(selectedMenuItem == MENU_MIDI_OCTAVE) {
			selectedOctave = getEncoderPosition(NUMBER_OF_MIDI_OCTAVES);
		} else if(selectedMenuItem == MENU_SAVE || selectedMenuItem == MENU_LOAD) {
			selectedSlot = getEncoderPosition(NUMBER_OF_SLOTS);
		}
	}
}

int getEncoderPosition(int segments) {
	int encoderValue = analogRead(encoder);
	int x = 1024 / segments;
	for(int i = 0; i <= segments; i++) {
		if(encoderValue <= (i + 1) * x && encoderValue >= i * x) return i;
	}
	return segments;
}
int getNumberOfSteps() {
	return (playMode == MODE_16) ? 16 : 8;
}

void save(byte slot) {
	int base = slot * 48;
	int address = base;
	
	do {
		if(address <= base + 16) {
			EEPROM.write(address, pitch[address - base]);
		} else if(address <= base + 32) {
			EEPROM.write(address, velocity[address - base - 16]);
		} else if(address <= base + 40) {
			EEPROM.write(address, modulate[address - base - 32]);
		} 
	} while(++address <= base + 40);
	
	EEPROM.write(base + 41, lowNoteByte);
	EEPROM.write(base + 42, highNoteByte);
	EEPROM.write(base + 43, beat);
	EEPROM.write(base + 44, playMode);
}
void load(byte slot) {
	int base = slot * 48;
	int address = base;
	
	do {
		if(address <= base + 16) {
			pitch[address - base] = EEPROM.read(address);
		} else if(address <= base + 32) {
			velocity[address - base - 16] = EEPROM.read(address);
		} else if(address <= base + 40) {
			modulate[address - base - 32] = EEPROM.read(address);
		}
	} while(++address <= base + 40);
	
	lowNoteByte = EEPROM.read(base + 41);
	highNoteByte = EEPROM.read(base + 42);
	beat = EEPROM.read(base + 43);
	playMode = EEPROM.read(base + 44);
	
	playPosition = FIRST;	
}

void loop() {
	updateMIDI();
	procesUserInput();
	updateLedDisplay(playPosition, selectedStep);
	delay(beat);
}