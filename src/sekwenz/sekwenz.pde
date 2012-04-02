/*
	Sekwenz
	
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

#define FIRST 1
#define PROPERTY_ON 1
#define PROPERTY_PITCH 2
#define PROPERTY_VELOCITY 3
#define PROPERTY_NONE 4
#define NUMBER_OF_PROPERTIES 3
#define MENU_TEMPO 1
#define MENU_PLAYMODE 2
#define MENU_MIDI_OCTAVE 3
#define MENU_LOAD 4
#define MENU_SAVE 5
#define NUMBER_OF_MENUS 5
#define MODE_8 1
#define MODE_16 2
#define MODE_MODULATE 3
#define MODE_RANDOMIZE 4
#define NUMBER_OF_MODES 4
#define STATE_SELECTING_MENU 1
#define STATE_EDITING_MENU 2
#define STATE_SELECTING_STEP 3
#define STATE_SELECTING_PROPERTY 4
#define STATE_EDITING_PROPERTY 5
#define MIDI_NOTE_ON 0x90
#define MIDI_NOTE_OFF 0x80
#define MIDI_BASE_NOTE 24
#define NUMBER_OF_MIDI_OCTAVES 5

byte midiOctave = FIRST;
byte selectedProperty = PROPERTY_NONE;
byte selectedMenuItem = MENU_TEMPO;
byte selectedStep = FIRST;
byte playMode = MODE_8;
byte playPosition = FIRST;
byte state = STATE_SELECTING_STEP;
byte modulationPosition = FIRST;

byte beat = 90;
byte lowNoteByte = 0;
byte highNoteByte = 0;

byte pitch[17];
byte velocity[17];
byte modulate[9];
byte currentNote = 0;
byte button1 = A0;
byte button2 = A1;
byte encoder = A2;

boolean button1Down = false;
boolean button2Down = false;
boolean exitPressed = false;
boolean enterPressed = false;
boolean blink = false;

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
	for (int i = 3; i <= 13; i++) digitalWrite(i, LOW);
  
	if (state == STATE_EDITING_MENU || state == STATE_SELECTING_MENU) {
		if (++selectedProperty > NUMBER_OF_PROPERTIES) selectedProperty = FIRST;
		digitalWrite(2 + selectedProperty, HIGH);
		digitalWrite(5 + selectedMenuItem, HIGH);
		if (selectedMenuItem == MENU_MIDI_OCTAVE) {
			digitalWrite(13 - NUMBER_OF_MIDI_OCTAVES + midiOctave, HIGH);
		} else if (selectedMenuItem == MENU_PLAYMODE) {
			digitalWrite(13 - NUMBER_OF_MODES + playMode, HIGH);
		}		
	} else {
		boolean hi8 = selectedStep > 8;
		
		if ((playPosition > 8 && hi8) || (playPosition < 9 && !hi8)) {
			if(playPosition > 8) playPosition -= 8;
			digitalWrite(5 + playPosition, HIGH);
		}

		if (hi8) {
			if (playMode == MODE_MODULATE) digitalWrite(5 + modulationPosition, HIGH);
			selectedStep -= 8;
		}

		digitalWrite(5 + selectedStep, HIGH);
		
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
	sendMIDI(MIDI_NOTE_OFF, currentNote, 0);

	byte baseNote = MIDI_BASE_NOTE + (midiOctave * 12);

	if (playMode == MODE_RANDOMIZE) {
		playPosition = rand() % 8 + 1;
	} else {
		if (++playPosition > getNumberOfSteps()) {
			playPosition = FIRST;
			if (++modulationPosition > 8) modulationPosition = FIRST;
		}
		if (playMode == MODE_MODULATE) baseNote += modulate[modulationPosition];
	}
	
	byte pos = playPosition - 1;
	byte B = lowNoteByte;
	
	if(pos >= 8) {
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
	boolean A = digitalRead(button1);
	boolean B = digitalRead(button2);	
	exitPressed = A && !button1Down;
	enterPressed = B && !button2Down;		
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
			if (selectedMenuItem == MENU_SAVE) {
				save(0);
			} else if (selectedMenuItem == MENU_LOAD) {
				load(0);
			} else {
				state = STATE_EDITING_MENU;
			}
		} else if (state == STATE_SELECTING_STEP) {  
			state = STATE_SELECTING_PROPERTY;
		} else if (state == STATE_SELECTING_PROPERTY) {
			state = STATE_EDITING_PROPERTY;
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
			selectedStep = getEncoderPosition(16);  
		}
	} else if (state == STATE_EDITING_PROPERTY) {
		if(selectedProperty == PROPERTY_ON) {
			if (selectedStep <= getNumberOfSteps()) {
				byte pos = selectedStep - 1;
				if(pos >= 8) {
					pos -= 8;
					bitWrite(highNoteByte, selectedStep - 1, getEncoderPosition(2) - 1);
				} else {
					bitWrite(lowNoteByte, selectedStep - 1, getEncoderPosition(2) - 1);
				}
			} else {
				modulate[selectedStep - 8] = getEncoderPosition(36) - 1;
			}
		} else if(selectedProperty == PROPERTY_PITCH) {
			pitch[selectedStep] = getEncoderPosition(36) - 1;
		} else if(selectedProperty == PROPERTY_VELOCITY) {
			velocity[selectedStep] = getEncoderPosition(128) - 1;
		}
	} else if (state == STATE_EDITING_MENU) {
		if(selectedMenuItem == MENU_TEMPO) {
			beat = 90 + (30 * getEncoderPosition(3) - 1);
		} else if(selectedMenuItem == MENU_PLAYMODE) {
			playMode = getEncoderPosition(NUMBER_OF_MODES);
		} else if(selectedMenuItem == MENU_MIDI_OCTAVE) {
			midiOctave = getEncoderPosition(NUMBER_OF_MIDI_OCTAVES);
		}
	}
}

int getEncoderPosition(int segments) {
	int encoderValue = analogRead(encoder);
	int x = 1024 / segments;
	for(int i = 1; i <= segments; i++) {
		if(encoderValue <= (i * x) && encoderValue >= ((i - 1) * x)) return i;
	}
	return segments;
}
int getNumberOfSteps() {
	return (playMode == MODE_16) ? 16 : 8;
}

void save(byte slot) {
	int base = slot * 43;
	int address = base + 1;
	
	do {
		if(address <= base + 17) {
			EEPROM.write(address, pitch[address - base]);
		} else if(address <= base + 34) {
			EEPROM.write(address, velocity[address - base - 17]);
		} else if(address <= base + 43) {
			EEPROM.write(address, modulate[address - base - 34]);
		} 
	} while(++address <= base + 43);
	
	EEPROM.write(base + 44, lowNoteByte);
	EEPROM.write(base + 45, highNoteByte);
	EEPROM.write(base + 46, beat);
	EEPROM.write(base + 47, playMode);
}
void load(byte slot) {
	int base = slot * 43;
	int address = base + 1;
	
	do {
		if(address <= base + 17) {
			pitch[address - base] = EEPROM.read(address);
		} else if(address <= base + 34) {
			velocity[address - base - 17] = EEPROM.read(address);
		} else if(address <= base + 43) {
			modulate[address - base - 34] = EEPROM.read(address);
		}
	} while(++address <= base + 43);
	
	lowNoteByte = EEPROM.read(base + 44);
	highNoteByte = EEPROM.read(base + 45);
	beat = EEPROM.read(base + 46);
	playMode = EEPROM.read(base + 47);
	
	playPosition = FIRST;	
}

void loop() {
	updateMIDI();
	procesUserInput();
	updateLedDisplay(playPosition, selectedStep);
	delay(beat);
}