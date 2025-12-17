/*
 *==============================================================================
 * MULTI-CORE RETRO COMPUTER SYSTEM - ESP32 Controller Firmware v4.0
 *==============================================================================
 *
 * Tesi di Laurea in Ingegneria Gestionale
 * Materia: Informatica
 *
 * Titolo: Multi-Core Retro Computer System
 *
 * Autore:   Angelo Arato
 * Ateneo:   Università Telematica Mercatorum
 * Corso:    Ingegneria Gestionale
 *
 *==============================================================================
 * DESCRIZIONE:
 * Controller ESP32 per sistema multi-core di emulazione computer vintage su FPGA.
 * Gestisce l'interfaccia utente touch, comunicazione UART con FPGA, caricamento
 * ROM da SD card e WebApp per controllo remoto.
 *
 * FUNZIONALITÀ v4.0:
 *   - Supporto LOAD_REQ: caricamento programmi dal C64 con comando LOAD nativo
 *   - Ricerca automatica file PRG diretti e in immagini D64
 *   - Supporto wildcard (*) per caricamento primo programma
 *   - Caricamento file .BAS tramite WebApp
 *
 * CORE SUPPORTATI:
 *   0 - Test Pattern (diagnostica video FPGA)
 *   1 - Commodore 64 (1982) - CPU 6502, VIC-II, SID audio
 *   2 - ZX Spectrum 48K (1982) - CPU Z80, ULA video
 *   3 - VIC-20 (1980) - CPU 6502, VIC-I video
 *   4 - Apple I (1976) - CPU 6502, Woz Monitor ROM integrato
 *
 * HARDWARE:
 *   - ESP32-2.8" Display Module (E32R28T) con touchscreen resistivo
 *   - Intel MAX 10 FPGA (DE10-Lite board)
 *   - SD Card per storage ROM e programmi
 *   - LED RGB per indicazione stato
 *
 * PROTOCOLLO UART FPGA (115200 baud):
 *   - PING/PONG: Test connessione
 *   - SELECT_CORE n: Seleziona core attivo (0-4)
 *   - ROM_START id size / ROM_END checksum: Caricamento ROM
 *   - KEY_CHAR c: Invio carattere tastiera
 *   - RESET: Reset core corrente
 *   - LOAD_REQ filename device secondary: Richiesta caricamento dal C64
 *
 * CONNESSIONI UART:
 *   - ESP32 GPIO26 (TX) → FPGA PIN_W10 (RX)
 *   - ESP32 GPIO27 (RX) ← FPGA PIN_V10 (TX)
 *   - GND comune
 *
 *==============================================================================
 */

#include <TFT_eSPI.h>
#include <TFT_Touch.h>
#include <SD.h>
#include <SPI.h>
#include <Preferences.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include "icons.h"  // Icone in PROGMEM

// ===== PINOUT DISPLAY =====
#define TFT_BL    21
#define RTP_DOUT  39
#define RTP_DIN   32
#define RTP_SCK   25
#define RTP_CS    33
#define RTP_IRQ   36

// ===== PINOUT SD CARD =====
#define SD_CS     5
#define SD_SCK    18
#define SD_MISO   19
#define SD_MOSI   23

// ===== PINOUT LED RGB =====
#define LED_RED   22
#define LED_GREEN 16
#define LED_BLUE  17

// ===== PINOUT UART FPGA =====
#define FPGA_TX_PIN  26
#define FPGA_RX_PIN  27

// ===== WiFi Configuration =====
#define AP_SSID_PREFIX "RetroPC_"        // Prefisso nome Access Point (+ ultimi 6 char MAC)
#define AP_PASSWORD    "retro2025"       // Password Access Point
#define WIFI_CONNECT_TIMEOUT 15000       // Timeout connessione WiFi (ms)

// Variabili WiFi
char ap_ssid[32];                        // SSID generato dinamicamente
char sta_ssid[64] = "";                  // SSID rete salvata
char sta_password[64] = "";              // Password rete salvata
bool wifiClientMode = false;             // true = connesso a rete esterna
bool wifiConfigured = false;             // true = credenziali salvate

// Forward declarations WiFi functions
void generateAPSSID();
void loadWiFiCredentials();
void saveWiFiCredentials(const char* ssid, const char* password);
void clearWiFiCredentials();
void blinkWiFiLED(int times, int delayMs);
bool connectToWiFi();
void startAccessPoint();
void initWiFi();
String getCurrentIP();

// ===== OGGETTI =====
TFT_eSPI tft = TFT_eSPI();
TFT_Touch touch = TFT_Touch(RTP_CS, RTP_SCK, RTP_DIN, RTP_DOUT);
SPIClass sdSPI(HSPI);
Preferences preferences;
AsyncWebServer server(80);
HardwareSerial FPGASerial(2);

// ===== FILE BAS =====
#define MAX_BAS_FILES 20
struct BASFileInfo {
    char name[64];
    char path[128];
};
BASFileInfo basFileList[MAX_BAS_FILES];
int basFileCount = 0;

// ===== COLORI =====
#define COLOR_BG       0x0000
#define COLOR_HEADER   0x001F
#define COLOR_TEXT     0xFFFF
#define COLOR_CARD     0x2104
#define COLOR_ACTIVE   0x07E0
#define COLOR_BUTTON   0x07E0
#define COLOR_ERROR    0xF800
#define COLOR_WARNING  0xFFE0
#define COLOR_PROGRESS 0x07E0

// ===== STRUTTURA SISTEMA =====
struct SystemInfo {
    const char* id;
    const char* name;
    const char* romPath;
    uint8_t fpgaCoreIndex;
    uint16_t color;
    int year;
    int romCount;
    const char* romFiles[3];
    const char* programExt;
};

SystemInfo systems[] = {
    {"test",     "Test Pattern", "",                0, 0x7BEF, 2025, 0, {"", "", ""}, ""},  // Schermata iniziale per verificare il funzionamento dell'FPGA e dell'uscita VGA
    {"c64",      "C64",          "/roms/c64",       1, 0x001F, 1982, 3, {"basic.901226-01.bin", "kernal.901227-03.bin", "characters.901225-01.bin"}, ".prg"},
    // {"c64",      "C64",          "/roms/c64",       1, 0x001F, 1982, 3, {"basic_generic.rom", "kernal_generic.rom", "chargen_openroms.rom"}, ".prg"},
    {"spectrum", "ZX Spectrum",  "/roms/spectrum",  2, 0xF800, 1982, 1, {"opense.rom", "", ""}, ".z80"},  // Supporta anche .tap, .bas
    {"vic20",    "VIC-20",       "/roms/vic20",     3, 0x07E0, 1980, 3, {"basic.901486-01.bin", "kernal.901486-07.bin", "characters.901460-03.bin"}, ".prg"},
    {"apple1",   "Apple I",      "/roms/apple1",    4, 0x00F0, 1976, 2, {"wozmon.bin", "basic.bin", ""}, ".bin"},  
};
const int NUM_SYSTEMS = 5;  // Test Pattern, C64, ZX Spectrum, VIC-20, Apple I

// ===== PROGRAMMI =====
#define MAX_PROGRAMS 50
struct ProgramInfo {
    char name[64];   // Aumentato da 32
    char path[128];  // Aumentato da 64
    uint32_t size;
};
ProgramInfo programList[MAX_PROGRAMS];
int programCount = 0;

// ===== D64 DISK IMAGE SUPPORT =====
#define D64_PATH "/floppy"  // Cartella per immagini D64
#define D64_TRACKS 35
#define D64_SIZE 174848     // 35 tracce standard

// Offset dei settori per ogni traccia (D64 ha settori di dimensione variabile)
const uint16_t d64_track_offset[] = {
    0,      // Track 0 non esiste
    0,      // Track 1: 21 sectors
    21,     // Track 2
    42,     // Track 3
    63,     // Track 4
    84,     // Track 5
    105,    // Track 6
    126,    // Track 7
    147,    // Track 8
    168,    // Track 9
    189,    // Track 10
    210,    // Track 11
    231,    // Track 12
    252,    // Track 13
    273,    // Track 14
    294,    // Track 15
    315,    // Track 16
    336,    // Track 17
    357,    // Track 18 (directory)
    376,    // Track 19
    395,    // Track 20
    414,    // Track 21
    433,    // Track 22
    452,    // Track 23
    471,    // Track 24
    490,    // Track 25 (19 sectors)
    508,    // Track 26
    526,    // Track 27
    544,    // Track 28
    562,    // Track 29
    580,    // Track 30
    598,    // Track 31 (17 sectors)
    615,    // Track 32
    632,    // Track 33
    649,    // Track 34
    666     // Track 35
};

// Entry directory D64
struct D64DirEntry {
    char filename[17];  // 16 chars + null
    uint8_t fileType;   // PRG, SEQ, REL, USR
    uint8_t startTrack;
    uint8_t startSector;
    uint16_t blockSize;
    bool valid;
};

#define MAX_D64_ENTRIES 144  // Max entries in D64 directory
D64DirEntry d64Directory[MAX_D64_ENTRIES];
int d64EntryCount = 0;
char currentD64Path[128] = "";
File currentD64File;
bool d64Mounted = false;

// ===== ZX SPECTRUM TAP/BAS SUPPORT =====
// TAP block info structure
struct TAPBlock {
    uint8_t flag;        // 0x00=header, 0xFF=data
    uint8_t type;        // 0=Program, 3=Code (only for headers)
    char filename[11];   // 10 chars + null
    uint16_t dataLen;    // Length of associated data
    uint16_t param1;     // Start address (Code) or autostart line (Program)
    uint16_t param2;     // 32768 (Code) or program length (Program)
    uint32_t dataOffset; // Offset in file where data block starts
    uint32_t blockLen;   // Total block length in file
};

#define MAX_TAP_BLOCKS 32
// Variables defined in TAP/BAS implementation section
extern TAPBlock tapBlocks[];
extern int tapBlockCount;

// Forward declarations for TAP/BAS functions
int parseTAPFile(File& f);
bool loadTAPBlock(File& f, int blockIndex);
bool loadBASFile(File& f);

// ===== STATE =====
int currentCore = 0;
int selectedIndex = -1;
bool sdCardReady = false;
bool fpgaReady = false;
bool romLoaded = false;
bool keyboardMode = false;
unsigned long lastTouch = 0;
String lastStatus = "";

// ===== CARICAMENTO DIFFERITO (per WebApp) =====
// Evita watchdog reset eseguendo loadSystemROMs() nel loop() invece che nella callback HTTP
volatile bool webLoadPending = false;      // Flag: richiesta caricamento pendente
volatile int webLoadSystemIndex = -1;      // Indice sistema da caricare
volatile bool webLoadComplete = false;     // Flag: caricamento completato
volatile bool webLoadSuccess = false;      // Risultato caricamento

// Caricamento differito BAS
volatile bool basLoadPending = false;      // Flag: richiesta caricamento BAS
volatile int basLoadIndex = -1;            // Indice file BAS da caricare
volatile bool basLoadComplete = false;     // Flag: caricamento BAS completato
volatile bool basLoadSuccess = false;      // Risultato caricamento BAS

// Invio tastiera differito
volatile bool keyboardPending = false;     // Flag: richiesta invio tastiera
String keyboardBuffer = "";                // Buffer testo da inviare
volatile bool keyboardComplete = false;    // Flag: invio completato

// Type BASIC program (invio diretto codice BASIC)
volatile bool typePending = false;         // Flag: richiesta typing programma
String typeCodeBuffer = "";                // Buffer codice BASIC da digitare
volatile bool typeComplete = false;        // Flag: typing completato
volatile bool typeSuccess = false;         // Risultato typing
volatile int typeCurrentLine = 0;          // Riga corrente
volatile int typeTotalLines = 0;           // Righe totali
String typeStatusMsg = "";                 // Messaggio stato

// Joystick state
struct JoystickState {
    bool up, down, left, right;
    bool fire1, fire2;
};
JoystickState joystick = {false, false, false, false, false, false};

// ===== LED =====
void setLED(bool red, bool green, bool blue) {
    digitalWrite(LED_RED,   red   ? LOW : HIGH);
    digitalWrite(LED_GREEN, green ? LOW : HIGH);
    digitalWrite(LED_BLUE,  blue  ? LOW : HIGH);
}

//==============================================================================
// UART FPGA
//==============================================================================
void sendToFPGA(const char* cmd) {
    while (FPGASerial.available()) FPGASerial.read();
    delay(5);
    FPGASerial.print(cmd);
    FPGASerial.print("\n");
    FPGASerial.flush();
    Serial.print("[FPGA TX] ");
    Serial.println(cmd);
}

bool waitResponse(const char* expected, unsigned long timeout) {
    unsigned long start = millis();
    String buf = "";
    
    while (millis() - start < timeout) {
        if (FPGASerial.available()) {
            char c = FPGASerial.read();
            if (c == '\n' || c == '\r') {
                Serial.print("[FPGA RX] ");
                Serial.println(buf);
                if (buf.indexOf(expected) != -1) return true;
                if (buf.indexOf("NAK") != -1 || buf.indexOf("ERROR") != -1) return false;
                buf = "";
            } else {
                buf += c;
            }
        }
        yield();
    }
    return false;
}

String getResponse(unsigned long timeout) {
    unsigned long start = millis();
    String buf = "";
    
    while (millis() - start < timeout) {
        if (FPGASerial.available()) {
            char c = FPGASerial.read();
            if (c == '\n' || c == '\r') {
                if (buf.length() > 0) {
                    Serial.print("[FPGA RX] ");
                    Serial.println(buf);
                    return buf;
                }
            } else {
                buf += c;
            }
        }
        yield();
    }
    return "";
}

bool testFPGA() {
    Serial.println("[TEST] Verifica FPGA...");
    sendToFPGA("PING");
    String resp = getResponse(2000);
    if (resp.indexOf("PONG") >= 0) {
        Serial.println("[OK] FPGA connessa!");
        fpgaReady = true;
        return true;
    }
    Serial.println("[WARN] FPGA non risponde");
    fpgaReady = false;
    return false;
}

// ============================================================================
// ZX SPECTRUM TOKEN CONVERSION
// Converte parole chiave BASIC in token (1 byte ciascuno)
// ============================================================================

struct ZXToken {
    const char* keyword;
    uint8_t token;
};

// Tabella token ZX Spectrum 48K - CORRETTA
// Ordinata per lunghezza decrescente per matching corretto
const ZXToken zxTokens[] = {
    // 9 caratteri
    {"RANDOMIZE", 0xF9},
    // 8 caratteri
    {"CONTINUE", 0xE8},
    // 7 caratteri
    {"RESTORE", 0xE5},
    // 6 caratteri
    {"RETURN", 0xFE},
    {"VERIFY", 0xD6},
    {"CIRCLE", 0xD8},
    {"BORDER", 0xE7},
    {"BRIGHT", 0xDC},
    {"LPRINT", 0xE0},
    // 5 caratteri
    {"PRINT", 0xF5},
    {"PAUSE", 0xF2},
    {"INPUT", 0xEE},
    {"MERGE", 0xD5},
    {"CLEAR", 0xFD},
    {"FLASH", 0xDB},
    {"PAPER", 0xDA},
    {"LLIST", 0xE1},
    {"ERASE", 0xD2},
    {"POINT", 0xA9},
    {"GO TO", 0xEC},
    {"GOSUB", 0xED},
    // 4 caratteri
    {"STEP", 0xCD},
    {"THEN", 0xCB},
    {"PLOT", 0xF6},
    {"DRAW", 0xFC},
    {"OVER", 0xDE},
    {"MOVE", 0xD1},
    {"OPEN", 0xD3},
    {"SAVE", 0xF8},
    {"LOAD", 0xEF},
    {"LIST", 0xF0},
    {"COPY", 0xFF},
    {"NEXT", 0xF3},
    {"POKE", 0xF4},
    {"PEEK", 0xBE},
    {"READ", 0xE3},
    {"DATA", 0xE4},
    {"BEEP", 0xD7},
    {"STOP", 0xE2},
    {"LINE", 0xCA},
    {"ATTR", 0xAB},
    {"CODE", 0xAF},
    {"STR$", 0xC1},
    {"CHR$", 0xC2},
    {"VAL$", 0xAE},
    {"GOTO", 0xEC},
    // 3 caratteri
    {"DIM", 0xE9},
    {"NEW", 0xE6},
    {"RUN", 0xF7},
    {"LET", 0xF1},
    {"FOR", 0xEB},
    {"REM", 0xEA},
    {"OUT", 0xDF},
    {"CLS", 0xFB},
    {"INK", 0xD9},
    {"VAL", 0xB0},
    {"LEN", 0xB1},
    {"SIN", 0xB2},
    {"COS", 0xB3},
    {"TAN", 0xB4},
    {"ASN", 0xB5},
    {"ACS", 0xB6},
    {"ATN", 0xB7},
    {"EXP", 0xB9},
    {"INT", 0xBA},
    {"SQR", 0xBB},
    {"SGN", 0xBC},
    {"ABS", 0xBD},
    {"USR", 0xC0},
    {"NOT", 0xC3},
    {"BIN", 0xC4},
    {"AND", 0xC6},
    {"TAB", 0xAD},
    {"CAT", 0xCF},
    {"RND", 0xA5},
    // 2 caratteri
    {"AT", 0xAC},
    {"OR", 0xC5},
    {"TO", 0xCC},
    {"IF", 0xFA},
    {"IN", 0xBF},
    {"PI", 0xA7},
    {"LN", 0xB8},
    {"FN", 0xA8},
    {"<>", 0xC9},
    {"<=", 0xC7},
    {">=", 0xC8},
    {NULL, 0}
};

// Converte una riga BASIC ZX Spectrum in token
String convertZXLine(const String& line) {
    String result = "";
    int i = 0;
    
    // Prima estrai il numero di riga (lascialo come cifre)
    while (i < line.length() && (line.charAt(i) == ' ' || (line.charAt(i) >= '0' && line.charAt(i) <= '9'))) {
        result += line.charAt(i);
        i++;
    }
    
    // Poi processa il resto cercando parole chiave
    while (i < line.length()) {
        bool found = false;
        
        // Cerca match con token (case insensitive)
        for (int t = 0; zxTokens[t].keyword != NULL; t++) {
            int kwLen = strlen(zxTokens[t].keyword);
            if (i + kwLen <= line.length()) {
                String sub = line.substring(i, i + kwLen);
                sub.toUpperCase();
                if (sub.equals(zxTokens[t].keyword)) {
                    result += (char)zxTokens[t].token;
                    i += kwLen;
                    found = true;
                    break;
                }
            }
        }
        
        if (!found) {
            // Carattere normale
            char c = line.charAt(i);
            // Converti in maiuscolo
            if (c >= 'a' && c <= 'z') c -= 32;
            result += c;
            i++;
        }
    }
    
    return result;
}

// ============================================================================
// ZX SPECTRUM BASIC LOADER - Carica programma direttamente in RAM
// ============================================================================
// Formato linea ZX BASIC in RAM:
// [next_hi][next_lo][line_hi][line_lo][content...][0x0D]
//
// PROG = 23635 (0x5C53) - punta all'inizio programma
// VARS = 23627 (0x5C4B) - punta alla fine programma
// Programma inizia a 23755 (0x5CCB)

bool loadZXBasicProgram(const String& program) {
    Serial.println("[ZX] Loading BASIC program directly to RAM...");
    Serial.printf("[ZX] Program text length: %d\n", program.length());
    
    const uint16_t PROG_START_ADDR = 23755;  // 0x5CCB - inizio programma
    const uint16_t PROG_PTR = 23635;    // 0x5C53
    const uint16_t VARS_PTR = 23627;    // 0x5C4B
    const uint16_t E_LINE_PTR = 23641;  // 0x5C59 - edit line pointer
    
    // Buffer per il programma tokenizzato
    uint8_t* ramBuffer = (uint8_t*)malloc(16384);  // Max 16KB
    if (!ramBuffer) {
        Serial.println("[ZX] ERROR: Cannot allocate buffer");
        return false;
    }
    
    uint16_t ramPos = 0;
    
    // Parsa ogni riga
    int pos = 0;
    while (pos < program.length()) {
        // Trova la fine della riga
        int eol = program.indexOf('\n', pos);
        if (eol < 0) eol = program.length();
        
        String line = program.substring(pos, eol);
        line.trim();
        
        if (line.length() > 0) {
            // Estrai numero linea
            int lineNum = 0;
            int i = 0;
            while (i < line.length() && line.charAt(i) >= '0' && line.charAt(i) <= '9') {
                lineNum = lineNum * 10 + (line.charAt(i) - '0');
                i++;
            }
            
            // Salta spazi dopo numero
            while (i < line.length() && line.charAt(i) == ' ') i++;
            
            // Tokenizza il resto
            String content = line.substring(i);
            String tokenized = "";
            
            int j = 0;
            while (j < content.length()) {
                bool found = false;
                
                // Cerca keyword
                for (int t = 0; zxTokens[t].keyword != NULL; t++) {
                    int kwLen = strlen(zxTokens[t].keyword);
                    if (j + kwLen <= content.length()) {
                        String sub = content.substring(j, j + kwLen);
                        sub.toUpperCase();
                        if (sub.equals(zxTokens[t].keyword)) {
                            tokenized += (char)zxTokens[t].token;
                            j += kwLen;
                            found = true;
                            break;
                        }
                    }
                }
                
                if (!found) {
                    char c = content.charAt(j);
                    if (c >= 'a' && c <= 'z') c -= 32;
                    tokenized += c;
                    j++;
                }
            }
            
            // Calcola lunghezza (contenuto + ENTER)
            uint16_t lineLen = tokenized.length() + 1;
            
            // Formato linea ZX BASIC in RAM:
            // [line_hi][line_lo] [len_lo][len_hi] [content...] [0x0D]
            
            // Numero linea (big-endian)
            ramBuffer[ramPos++] = (lineNum >> 8) & 0xFF;  // MSB
            ramBuffer[ramPos++] = lineNum & 0xFF;         // LSB
            
            // Lunghezza (little-endian)
            ramBuffer[ramPos++] = lineLen & 0xFF;         // LSB
            ramBuffer[ramPos++] = (lineLen >> 8) & 0xFF;  // MSB
            
            // Contenuto tokenizzato
            for (int k = 0; k < tokenized.length(); k++) {
                ramBuffer[ramPos++] = (uint8_t)tokenized.charAt(k);
            }
            
            // ENTER
            ramBuffer[ramPos++] = 0x0D;
            
            Serial.printf("[ZX] Line %d: %d bytes tokenized\n", lineNum, lineLen);
        }
        
        pos = eol + 1;
    }
    
    // Fine del programma BASIC = dove inizieranno le variabili
    uint16_t varsStart = PROG_START_ADDR + ramPos;
    
    // Aggiungi marker fine variabili (0x80) - richiesto dallo ZX Spectrum
    ramBuffer[ramPos++] = 0x80;
    
    // E_LINE punta al byte dopo il marker 0x80
    uint16_t eLine = PROG_START_ADDR + ramPos;
    
    Serial.printf("[ZX] Program size: %d bytes, VARS at 0x%04X, E_LINE at 0x%04X\n", 
                  ramPos, varsStart, eLine);
    
    // Carica programma in RAM via PROG_START
    char cmd[32];
    sprintf(cmd, "PROG_START %04X %04X", PROG_START_ADDR, ramPos);
    Serial.printf("[ZX] Sending: %s\n", cmd);
    FPGASerial.print(cmd);
    FPGASerial.print("\n");
    FPGASerial.flush();
    delay(50);
    
    // Invia i dati
    Serial.printf("[ZX] Sending %d bytes of program data...\n", ramPos);
    for (int i = 0; i < ramPos; i++) {
        FPGASerial.write(ramBuffer[i]);
        if ((i % 256) == 255) {
            FPGASerial.flush();
            delay(10);
            yield();
        }
    }
    FPGASerial.flush();
    delay(100);
    
    FPGASerial.print("PROG_END\n");
    FPGASerial.flush();
    delay(50);
    
    // Aggiorna PROG pointer (23635-23636) = PROG_START_ADDR (little-endian)
    sprintf(cmd, "PROG_START %04X 0002", PROG_PTR);
    Serial.printf("[ZX] Setting PROG ptr to 0x%04X\n", PROG_START_ADDR);
    FPGASerial.print(cmd);
    FPGASerial.print("\n");
    FPGASerial.flush();
    delay(20);
    FPGASerial.write(PROG_START_ADDR & 0xFF);         // LSB
    FPGASerial.write((PROG_START_ADDR >> 8) & 0xFF);  // MSB
    FPGASerial.flush();
    delay(20);
    FPGASerial.print("PROG_END\n");
    FPGASerial.flush();
    delay(20);
    
    // Aggiorna VARS pointer (23627-23628) = inizio variabili (little-endian)
    sprintf(cmd, "PROG_START %04X 0002", VARS_PTR);
    FPGASerial.print(cmd);
    FPGASerial.print("\n");
    FPGASerial.flush();
    delay(20);
    FPGASerial.write(varsStart & 0xFF);         // LSB
    FPGASerial.write((varsStart >> 8) & 0xFF);  // MSB
    FPGASerial.flush();
    delay(20);
    FPGASerial.print("PROG_END\n");
    FPGASerial.flush();
    delay(20);
    
    // Aggiorna E_LINE pointer (23641-23642) = subito dopo VARS marker
    sprintf(cmd, "PROG_START %04X 0002", E_LINE_PTR);
    FPGASerial.print(cmd);
    FPGASerial.print("\n");
    FPGASerial.flush();
    delay(20);
    FPGASerial.write(eLine & 0xFF);         // LSB
    FPGASerial.write((eLine >> 8) & 0xFF);  // MSB
    FPGASerial.flush();
    delay(20);
    FPGASerial.print("PROG_END\n");
    FPGASerial.flush();
    
    free(ramBuffer);
    
    Serial.println("[ZX] BASIC program loaded!");
    return true;
}


void sendKeyToFPGA(uint8_t c) {
    // Converti LF in CR (importante per Apple I!)
    if (c == 0x0A) c = 0x0D;
    
    // Per RETURN (0x0D), usa comando dedicato KEY_RET
    // perché il byte 0x0D verrebbe interpretato come fine comando dal parser FPGA
    if (c == 0x0D) {
        FPGASerial.print("KEY_RET\n");
        FPGASerial.flush();
        Serial.printf("[KEY] Sent RETURN to core %d\n", currentCore);
        delay(50);
    } else {
        // Caratteri normali
        FPGASerial.print("KEY_CHAR ");
        FPGASerial.write(c);
        FPGASerial.print("\n");
        FPGASerial.flush();
        if (c >= 32 && c < 127) {
            Serial.printf("[KEY] Sent '%c' to core %d\n", c, currentCore);
        } else {
            Serial.printf("[KEY] Sent (0x%02X) to core %d\n", c, currentCore);
        }
        delay(50);
    }
}

void sendJoystickToFPGA() {
    uint8_t bits = 0;
    if (joystick.up)    bits |= 0x01;
    if (joystick.down)  bits |= 0x02;
    if (joystick.left)  bits |= 0x04;
    if (joystick.right) bits |= 0x08;
    if (joystick.fire1) bits |= 0x10;
    if (joystick.fire2) bits |= 0x20;
    
    char cmd[16];
    sprintf(cmd, "JOY %02X", bits);
    FPGASerial.print(cmd);
    FPGASerial.print("\n");
    FPGASerial.flush();
}

//==============================================================================
// SD CARD & ROMs
//==============================================================================

bool initSDCard() {
    Serial.println("[SD] Init...");
    pinMode(SD_CS, OUTPUT);
    digitalWrite(SD_CS, HIGH);
    sdSPI.begin(SD_SCK, SD_MISO, SD_MOSI, SD_CS);
    
    if (!SD.begin(SD_CS, sdSPI)) {
        Serial.println("[SD] FAIL");
        return false;
    }
    Serial.println("[SD] OK");
    return true;
}

void scanROMs() {
    Serial.println("\n[SCAN] ROM folders...");
    for (int i = 0; i < NUM_SYSTEMS; i++) {
        if (strlen(systems[i].romPath) == 0) {
            systems[i].romCount = 0;
            continue;
        }
        
        File dir = SD.open(systems[i].romPath);
        if (!dir) {
            systems[i].romCount = 0;
            continue;
        }
        
        int count = 0;
        while (File f = dir.openNextFile()) {
            String name = f.name();
            if (!f.isDirectory() && !name.startsWith(".") && !name.startsWith("_") &&
                (name.endsWith(".bin") || name.endsWith(".rom"))) {
                count++;
            }
            f.close();
        }
        dir.close();
        systems[i].romCount = count;
        Serial.printf("  %s: %d ROM\n", systems[i].id, count);
    }
}

bool loadROM(const char* path, int romId, const char* label) {
    File f = SD.open(path);
    if (!f) {
        Serial.printf("[ROM] %s: NOT FOUND\n", path);
        return false;
    }
    
    uint32_t size = f.size();
    Serial.printf("[ROM] %s: %s (%d bytes)\n", label, path, size);
    
    // Svuota buffer UART
    while (FPGASerial.available()) FPGASerial.read();
    
    char cmd[32];
    sprintf(cmd, "ROM_START %d %d", romId, size);
    sendToFPGA(cmd);
    delay(100);  // Aumentato
    
    // Aspetta ACK da ROM_START
    String resp = getResponse(2000);
    Serial.printf("[ROM] ROM_START resp: %s\n", resp.c_str());
    
    uint8_t buffer[256];
    uint32_t sent = 0;
    uint8_t checksum = 0;
    
    while (f.available()) {
        int bytesRead = f.read(buffer, sizeof(buffer));
        for (int i = 0; i < bytesRead; i++) checksum ^= buffer[i];
        FPGASerial.write(buffer, bytesRead);
        sent += bytesRead;
        
        // Progress ogni 2KB
        if (sent % 2048 == 0) {
            Serial.printf("[ROM] Sent %d/%d bytes\n", sent, size);
        }
        delay(10);  // Aumentato per dare tempo all'FPGA
    }
    
    f.close();
    Serial.printf("[ROM] Transfer complete: %d bytes, checksum=%02X\n", sent, checksum);
    delay(100);
    
    sprintf(cmd, "ROM_END %02X", checksum);
    sendToFPGA(cmd);
    
    // Timeout più lungo per ROM_END
    resp = getResponse(5000);
    bool ok = (resp.indexOf("OK") >= 0);
    Serial.printf("[ROM] %s: %s (resp: %s)\n", label, ok ? "OK" : "FAIL", resp.c_str());
    return ok;
}

bool loadSystemROMs(int sysIndex) {
    if (sysIndex < 0 || sysIndex >= NUM_SYSTEMS) return false;
    SystemInfo& sys = systems[sysIndex];
    
    unsigned long totalStartTime = millis();  // Tempo totale
    
    Serial.printf("\n=== Loading %s (core %d) ===\n", sys.name, sys.fpgaCoreIndex);
    char cmd[32];
    sprintf(cmd, "SELECT_CORE %d", sys.fpgaCoreIndex);
    sendToFPGA(cmd);
    if (!waitResponse("OK", 2000)) {
        Serial.println("Core selection failed!");
        return false;
    }
    
    // RESETTA LA RAM/CORE APPENA SELEZIONATO
    delay(50);
    sendToFPGA("RESET");
    delay(100);
    
    currentCore = sysIndex;
    
    if (sysIndex == 0 || strlen(sys.romPath) == 0) {
        Serial.println("[OK] Core selected (no ROM)");
        scanPrograms(sysIndex);
        scanBASFiles(sysIndex);
        return true;
    }
    
    char path[64];
    bool ok = true;
    const char* romNames[] = {"ROM 1", "ROM 2", "CHAR"};
    
    int bankOffset = 0;
    if (strcmp(sys.id, "spectrum") == 0) {
        bankOffset = 3;
    }
    
    for (int i = 0; i < 3 && ok; i++) {
        if (strlen(sys.romFiles[i]) > 0) {
            sprintf(path, "%s/%s", sys.romPath, sys.romFiles[i]);
            
            unsigned long romStartTime = millis();  // Tempo singola ROM
            ok = loadROM(path, i + bankOffset, romNames[i]);
            unsigned long romElapsed = millis() - romStartTime;
            
            if (ok) {
                Serial.printf("  -> %s loaded in %lu ms\n", sys.romFiles[i], romElapsed);
            } else {
                Serial.printf("  -> %s FAILED after %lu ms\n", sys.romFiles[i], romElapsed);
            }
        }
    }
    
    unsigned long totalElapsed = millis() - totalStartTime;
    
    if (ok) {
        sendToFPGA("BOOT");
        romLoaded = true;
        preferences.putInt("core", currentCore);
        Serial.printf("=== ROM Loaded! Total time: %lu ms ===\n\n", totalElapsed);
    } else {
        Serial.printf("=== ROM Load FAILED after %lu ms ===\n\n", totalElapsed);
    }
    
    scanPrograms(sysIndex);
    scanBASFiles(sysIndex);
    return ok;
}
//==============================================================================
// PROGRAMMI/GIOCHI
//==============================================================================

int scanPrograms(int systemIndex) {
    programCount = 0;
    
    if (systemIndex < 0 || systemIndex >= NUM_SYSTEMS) return 0;
    if (strlen(systems[systemIndex].romPath) == 0) return 0;
    
    String programPath = String(systems[systemIndex].romPath) + "/programs";
    
    File dir = SD.open(programPath);
    if (!dir) {
        Serial.printf("[PROG] No programs folder: %s\n", programPath.c_str());
        return 0;
    }
    
    Serial.printf("[PROG] Scanning: %s\n", programPath.c_str());
    
    const char* ext = systems[systemIndex].programExt;
    bool isSpectrum = (systemIndex == 2);  // ZX Spectrum

    while (File f = dir.openNextFile()) {
        if (programCount >= MAX_PROGRAMS) break;

        String name = f.name();
        if (!f.isDirectory() && !name.startsWith(".")) {
            bool validExt = (strlen(ext) == 0);
            if (!validExt) {
                validExt = name.endsWith(ext) ||
                           name.endsWith(".bin") ||
                           name.endsWith(".rom");
                // ZX Spectrum: accetta anche .tap e .bas
                if (isSpectrum) {
                    validExt = validExt ||
                               name.endsWith(".tap") || name.endsWith(".TAP") ||
                               name.endsWith(".bas") || name.endsWith(".BAS") ||
                               name.endsWith(".sna") || name.endsWith(".SNA");
                }
            }
            
            if (validExt) {
                strncpy(programList[programCount].name, name.c_str(), 63);
                programList[programCount].name[63] = '\0';
                
                String fullPath = programPath + "/" + name;
                strncpy(programList[programCount].path, fullPath.c_str(), 127);
                programList[programCount].path[127] = '\0';
                
                programList[programCount].size = f.size();
                
                Serial.printf("  [%d] %s (%d bytes)\n", 
                              programCount, 
                              programList[programCount].name,
                              programList[programCount].size);
                
                programCount++;
            }
        }
        f.close();
    }
    dir.close();
    
    Serial.printf("[PROG] Found %d programs\n", programCount);
    return programCount;
}

void listPrograms() {
    Serial.println("\n=== PROGRAMMI DISPONIBILI ===\n");
    
    if (programCount == 0) {
        scanPrograms(currentCore);
    }
    
    if (programCount == 0) {
        Serial.println("Nessun programma trovato.");
        Serial.printf("Crea la cartella: %s/programs/\n", systems[currentCore].romPath);
        return;
    }
    
    for (int i = 0; i < programCount; i++) {
        Serial.printf("[%2d] %-24s %6d bytes\n", 
                      i, 
                      programList[i].name,
                      programList[i].size);
    }
    Serial.println("\nUsa 'l <numero>' per caricare\n");
}

//==============================================================================
// FILE BAS - Scansione e caricamento programmi BASIC in formato testo
//==============================================================================

/**
 * Scansiona i file .BAS disponibili per il sistema corrente
 * Cerca nelle cartelle /bas e /programs
 * @param systemIndex Indice del sistema
 * @return Numero di file BAS trovati
 */
int scanBASFiles(int systemIndex) {
    basFileCount = 0;
    
    if (systemIndex < 0 || systemIndex >= NUM_SYSTEMS) return 0;
    if (strlen(systems[systemIndex].romPath) == 0) return 0;
    
    // Cerca in /bas e /programs
    String paths[] = {
        String(systems[systemIndex].romPath) + "/bas",
        String(systems[systemIndex].romPath) + "/programs"
    };
    
    for (int p = 0; p < 2; p++) {
        File dir = SD.open(paths[p]);
        if (!dir) continue;
        
        Serial.printf("[BAS] Scanning: %s\n", paths[p].c_str());
        
        while (File f = dir.openNextFile()) {
            if (basFileCount >= MAX_BAS_FILES) break;
            
            String name = f.name();
            if (!f.isDirectory() && !name.startsWith(".") &&
                (name.endsWith(".bas") || name.endsWith(".BAS"))) {
                
                strncpy(basFileList[basFileCount].name, name.c_str(), 63);
                basFileList[basFileCount].name[63] = '\0';
                
                String fullPath = paths[p] + "/" + name;
                strncpy(basFileList[basFileCount].path, fullPath.c_str(), 127);
                basFileList[basFileCount].path[127] = '\0';
                
                Serial.printf("  [BAS %d] %s\n", basFileCount, basFileList[basFileCount].name);
                basFileCount++;
            }
            f.close();
        }
        dir.close();
    }
    
    Serial.printf("[BAS] Found %d BAS files\n", basFileCount);
    return basFileCount;
}

/**
 * Carica ed esegue un file BASIC (.bas)
 * Il file viene letto riga per riga e inviato come input tastiera
 * @param path Percorso del file BAS
 * @return true se caricamento riuscito
 */
bool loadAndRunBASFile(const char* path) {
    File f = SD.open(path);
    if (!f) {
        Serial.printf("[BAS] File not found: %s\n", path);
        return false;
    }
    
    Serial.printf("[BAS] Loading: %s (%d bytes)\n", path, f.size());
    
    // Determina il delay in base al core
    int charDelay = 50;   // Default per C64/VIC-20
    int lineDelay = 500;
    
    if (currentCore == 2) {  // ZX Spectrum - più lento
        charDelay = 100;
        lineDelay = 1000;
    } else if (currentCore == 4) {  // Apple I
        charDelay = 120;
        lineDelay = 500;
    }
    
    int lineCount = 0;
    
    // Leggi e invia ogni riga
    while (f.available()) {
        String line = f.readStringUntil('\n');
        line.trim();
        
        if (line.length() == 0) continue;  // Salta righe vuote
        
        Serial.printf("[BAS] Line %d: %s\n", lineCount + 1, line.c_str());
        
        // Invia ogni carattere della riga
        for (int i = 0; i < line.length(); i++) {
            char ch = line[i];
            // Converti in maiuscolo per sistemi 8-bit
            if (currentCore >= 1 && currentCore <= 4) {
                if (ch >= 'a' && ch <= 'z') ch -= 32;
            }
            sendKeyToFPGA(ch);
            delay(charDelay);
        }
        
        // Invia RETURN
        sendKeyToFPGA(13);
        delay(lineDelay);
        
        lineCount++;
        yield();  // Evita watchdog timeout
    }
    
    f.close();
    Serial.printf("[BAS] Sent %d lines\n", lineCount);
    return true;
}

bool loadProgram(int index) {
    if (index < 0 || index >= programCount) {
        Serial.println("[!] Indice programma non valido");
        return false;
    }

    Serial.printf("[LOAD] Caricamento: %s\n", programList[index].name);
    Serial.printf("[LOAD] Path: '%s'\n", programList[index].path);

    String filename = programList[index].name;

    // ZX Spectrum: gestione file TAP e BAS
    if (currentCore == 2) {
        if (filename.endsWith(".tap") || filename.endsWith(".TAP")) {
            File f = SD.open(programList[index].path);
            if (!f) {
                Serial.println("[!] Impossibile aprire file TAP");
                return false;
            }

            // Parse TAP file
            int blocks = parseTAPFile(f);
            if (blocks == 0) {
                Serial.println("[!] Nessun blocco caricabile nel TAP");
                f.close();
                return false;
            }

            // Carica il primo blocco Program o Code
            bool loaded = false;
            for (int i = 0; i < tapBlockCount; i++) {
                if (tapBlocks[i].type == 0 || tapBlocks[i].type == 3) {
                    loaded = loadTAPBlock(f, i);
                    break;
                }
            }

            f.close();
            return loaded;
        }
        else if (filename.endsWith(".bas") || filename.endsWith(".BAS")) {
            File f = SD.open(programList[index].path);
            if (!f) {
                Serial.println("[!] Impossibile aprire file BAS");
                return false;
            }

            bool loaded = loadBASFile(f);
            f.close();
            return loaded;
        }
        // .z80 e .sna continuano con il caricamento standard sotto
    }

    File f = SD.open(programList[index].path);
    if (!f) {
        Serial.println("[!] Impossibile aprire file");
        return false;
    }

    uint32_t size = f.size();
    Serial.printf("[LOAD] Dimensione: %d bytes\n", size);

    uint16_t loadAddr = 0x0801;  // Default C64 BASIC start

    // Leggi indirizzo di caricamento dai primi 2 bytes (little-endian)
    if (size >= 2) {
        uint8_t lo = f.read();
        uint8_t hi = f.read();
        loadAddr = lo | (hi << 8);
        size -= 2;
        Serial.printf("[LOAD] PRG Load address: $%04X\n", loadAddr);
    }
    
    // Determina se è programma BASIC in base al core e indirizzo
    // C64: $0801, VIC-20: $1001
    bool isBasic = false;
    if (currentCore == 1 && loadAddr == 0x0801) isBasic = true;       // C64
    else if (currentCore == 3 && loadAddr == 0x1001) isBasic = true;  // VIC-20
    Serial.printf("[LOAD] Tipo: %s\n", isBasic ? "BASIC" : "Machine Code");
    
    // Invia comando PROG_START AAAA SSSS (hex)
    char cmd[32];
    sprintf(cmd, "PROG_START %04X %04X", loadAddr, size);
    sendToFPGA(cmd);
    
    // Aspetta risposta PRG_OK
    if (!waitResponse("PRG_OK", 2000)) {
        Serial.println("[!] FPGA non ha accettato PROG_START");
        f.close();
        return false;
    }
    
    // Piccola pausa prima di inviare dati
    delay(10);
    
    // Invia dati binari con timing controllato
    unsigned long startTime = millis();
    uint32_t sent = 0;
    
    while (f.available() && sent < size) {
        uint8_t byte = f.read();
        FPGASerial.write(byte);
        sent++;
        
        // Progress ogni 1KB
        if (sent % 1024 == 0) {
            Serial.printf("[LOAD] %d/%d bytes\n", sent, size);
        }
        
        // IMPORTANTE: delay più lungo per non perdere byte
        // A 115200 baud, 1 byte = ~87us, ma l'FPGA ha bisogno di tempo
        // per processare e scrivere in RAM
        if (sent % 16 == 0) {
            delayMicroseconds(200);  // 200us ogni 16 byte
        }
    }
    
    unsigned long elapsed = millis() - startTime;
    
    f.close();
    
    // Aspetta che FPGA finisca di ricevere
    delay(100);
    
    // Invia PROG_END
    sendToFPGA("PROG_END");
    
    if (waitResponse("PRG_DONE", 2000)) {
        Serial.printf("[LOAD] Completato: %d bytes @ $%04X in %lu ms\n", sent, loadAddr, elapsed);
        
        // Calcola fine programma
        uint16_t endAddr = loadAddr + sent;
        
        // Delay più lungo per permettere al BASIC di stabilizzarsi
        delay(1000);
        
        // ZX Spectrum: i file .Z80 sono snapshot, non servono comandi
        if (currentCore == 2) {
            Serial.println("[LOAD] ZX Spectrum snapshot caricato");
            Serial.println("[LOAD] Nota: I file .Z80 richiedono un loader speciale");
            Serial.println("[LOAD] Prova con file .SNA o .TAP");
            return true;
        }
        
        // VIC-20: simile a C64 ma con puntatori diversi
        if (currentCore == 3) {
            if (isBasic) {
                // Aggiorna puntatori BASIC VIC-20 ($2D-$2E = VARTAB)
                Serial.println("[LOAD] VIC-20 BASIC - Setting pointers...");
                char pokeCmd[40];
                sprintf(pokeCmd, "POKE45,%d:POKE46,%d", endAddr & 0xFF, (endAddr >> 8) & 0xFF);
                for (int i = 0; pokeCmd[i]; i++) {
                    sendKeyToFPGA(pokeCmd[i]);
                }
                sendKeyToFPGA(13);
                delay(300);
                
                // CLR e RUN
                Serial.println("[LOAD] VIC-20 BASIC - Invio CLR e RUN...");
                sendKeyToFPGA('C');
                sendKeyToFPGA('L');
                sendKeyToFPGA('R');
                sendKeyToFPGA(13);
                delay(300);
                
                sendKeyToFPGA('R');
                sendKeyToFPGA('U');
                sendKeyToFPGA('N');
                sendKeyToFPGA(13);
            } else {
                Serial.printf("[LOAD] VIC-20 ML - Invio SYS %d...\n", loadAddr);
                char sysCmd[20];
                sprintf(sysCmd, "SYS %d", loadAddr);
                for (int i = 0; sysCmd[i]; i++) {
                    sendKeyToFPGA(sysCmd[i]);
                }
                sendKeyToFPGA(13);
            }
            return true;
        }
        
        // C64: gestione standard
        if (isBasic) {
            // Programma BASIC - dobbiamo aggiornare i puntatori
            Serial.println("[LOAD] Setting BASIC pointers...");
            
            char pokeCmd[40];
            sprintf(pokeCmd, "POKE45,%d:POKE46,%d", endAddr & 0xFF, (endAddr >> 8) & 0xFF);
            for (int i = 0; pokeCmd[i]; i++) {
                sendKeyToFPGA(pokeCmd[i]);
            }
            sendKeyToFPGA(13);
            delay(300);
            
            // CLR per reinizializzare variabili
            Serial.println("[LOAD] Sending CLR...");
            sendKeyToFPGA('C');
            sendKeyToFPGA('L');
            sendKeyToFPGA('R');
            sendKeyToFPGA(13);
            delay(300);
            
            // RUN
            Serial.println("[LOAD] Invio RUN...");
            sendKeyToFPGA('R');
            sendKeyToFPGA('U');
            sendKeyToFPGA('N');
            sendKeyToFPGA(13);
        } else {
            // Programma in linguaggio macchina
            Serial.printf("[LOAD] Invio SYS %d...\n", loadAddr);
            char sysCmd[20];
            sprintf(sysCmd, "SYS %d", loadAddr);
            for (int i = 0; sysCmd[i]; i++) {
                sendKeyToFPGA(sysCmd[i]);
            }
            sendKeyToFPGA(13);
        }
        
        return true;
    }
    
    Serial.println("[!] Errore durante caricamento");
    return false;
}

//==============================================================================
// D64 DISK IMAGE SUPPORT
//==============================================================================

// Calcola l'offset in bytes di un settore nel file D64
uint32_t d64GetSectorOffset(uint8_t track, uint8_t sector) {
    if (track < 1 || track > 35) return 0;
    return (d64_track_offset[track] + sector) * 256;
}

// Legge un settore dal file D64
bool d64ReadSector(uint8_t track, uint8_t sector, uint8_t* buffer) {
    if (!d64Mounted || !currentD64File) return false;
    
    uint32_t offset = d64GetSectorOffset(track, sector);
    currentD64File.seek(offset);
    return currentD64File.read(buffer, 256) == 256;
}

// Monta un file D64
bool d64Mount(const char* path) {
    // Chiudi file precedente se aperto
    if (currentD64File) {
        currentD64File.close();
    }
    
    currentD64File = SD.open(path);
    if (!currentD64File) {
        Serial.printf("[D64] Cannot open: %s\n", path);
        d64Mounted = false;
        return false;
    }
    
    // Verifica dimensione
    uint32_t size = currentD64File.size();
    if (size != 174848 && size != 175531 && size != 196608) {
        Serial.printf("[D64] Invalid size: %d bytes\n", size);
        currentD64File.close();
        d64Mounted = false;
        return false;
    }
    
    strncpy(currentD64Path, path, 127);
    d64Mounted = true;
    Serial.printf("[D64] Mounted: %s (%d bytes)\n", path, size);
    return true;
}

// Smonta il D64
void d64Unmount() {
    if (currentD64File) {
        currentD64File.close();
    }
    d64Mounted = false;
    d64EntryCount = 0;
    currentD64Path[0] = '\0';
    Serial.println("[D64] Unmounted");
}

// Legge la directory del D64
int d64ReadDirectory() {
    if (!d64Mounted) return 0;
    
    d64EntryCount = 0;
    uint8_t sector[256];
    
    // La directory inizia a Track 18, Sector 1
    uint8_t track = 18;
    uint8_t sec = 1;
    
    while (track != 0 && d64EntryCount < MAX_D64_ENTRIES) {
        if (!d64ReadSector(track, sec, sector)) break;
        
        // Prossimo settore della directory
        track = sector[0];
        sec = sector[1];
        
        // 8 entries per settore, ogni entry è 32 bytes
        for (int i = 0; i < 8 && d64EntryCount < MAX_D64_ENTRIES; i++) {
            int offset = i * 32;
            uint8_t fileType = sector[offset + 2] & 0x07;
            
            // Tipo file: 0=DEL, 1=SEQ, 2=PRG, 3=USR, 4=REL
            if (fileType >= 1 && fileType <= 4) {
                D64DirEntry* entry = &d64Directory[d64EntryCount];
                
                // Copia filename (16 caratteri, padded con $A0)
                for (int j = 0; j < 16; j++) {
                    uint8_t c = sector[offset + 5 + j];
                    if (c == 0xA0) c = ' ';  // Convert padding to space
                    entry->filename[j] = (c >= 0x41 && c <= 0x5A) ? c : 
                                         (c >= 0x61 && c <= 0x7A) ? c - 32 : 
                                         (c >= 0x20 && c <= 0x3F) ? c : '?';
                }
                entry->filename[16] = '\0';
                
                // Trim trailing spaces
                for (int j = 15; j >= 0 && entry->filename[j] == ' '; j--) {
                    entry->filename[j] = '\0';
                }
                
                entry->fileType = fileType;
                entry->startTrack = sector[offset + 3];
                entry->startSector = sector[offset + 4];
                entry->blockSize = sector[offset + 30] | (sector[offset + 31] << 8);
                entry->valid = true;
                
                d64EntryCount++;
            }
        }
    }
    
    Serial.printf("[D64] Found %d files\n", d64EntryCount);
    return d64EntryCount;
}

// Mostra la directory del D64 corrente
void d64ShowDirectory() {
    if (!d64Mounted) {
        Serial.println("[D64] No disk mounted");
        return;
    }
    
    if (d64EntryCount == 0) {
        d64ReadDirectory();
    }
    
    Serial.println("\n=== D64 DIRECTORY ===");
    Serial.printf("Disk: %s\n\n", currentD64Path);
    
    const char* typeStr[] = {"DEL", "SEQ", "PRG", "USR", "REL"};
    
    for (int i = 0; i < d64EntryCount; i++) {
        D64DirEntry* e = &d64Directory[i];
        Serial.printf("[%2d] %-16s  %3s  %3d blocks\n", 
                      i, e->filename, typeStr[e->fileType], e->blockSize);
    }
    Serial.println();
}

// Carica un file dal D64
bool d64LoadFile(int index) {
    if (!d64Mounted || index < 0 || index >= d64EntryCount) {
        Serial.println("[D64] Invalid file index");
        return false;
    }
    
    D64DirEntry* entry = &d64Directory[index];
    
    // Solo file PRG
    if (entry->fileType != 2) {
        Serial.println("[D64] Not a PRG file");
        return false;
    }
    
    Serial.printf("[D64] Loading: %s\n", entry->filename);
    
    // Prima passa: calcola dimensione file e leggi load address
    uint8_t sector[256];
    uint32_t fileSize = 0;
    uint8_t track = entry->startTrack;
    uint8_t sec = entry->startSector;
    uint16_t loadAddr = 0;
    bool firstSector = true;
    
    // Calcola dimensione totale
    uint8_t startTrack = track;
    uint8_t startSec = sec;
    
    while (track != 0) {
        if (!d64ReadSector(track, sec, sector)) {
            Serial.println("[D64] Read error (size calc)");
            return false;
        }
        
        uint8_t nextTrack = sector[0];
        uint8_t nextSector = sector[1];
        
        int bytesInSector;
        if (nextTrack == 0) {
            bytesInSector = nextSector - 1;
        } else {
            bytesInSector = 254;
        }
        
        if (firstSector) {
            loadAddr = sector[2] | (sector[3] << 8);
            firstSector = false;
        }
        
        fileSize += bytesInSector;
        track = nextTrack;
        sec = nextSector;
        
        if (fileSize > 65536) {
            Serial.println("[D64] File too large");
            return false;
        }
    }
    
    Serial.printf("[D64] File size: %d bytes\n", fileSize);
    Serial.printf("[D64] Load address: $%04X\n", loadAddr);
    
    if (fileSize < 2) {
        Serial.println("[D64] File too small");
        return false;
    }
    
    // Invia comando al FPGA
    char cmd[32];
    sprintf(cmd, "PROG_START %04X %04X", loadAddr, fileSize - 2);
    sendToFPGA(cmd);
    
    if (!waitResponse("PRG_OK", 2000)) {
        Serial.println("[D64] FPGA rejected");
        return false;
    }
    
    // Seconda passa: leggi e invia dati in streaming
    track = startTrack;
    sec = startSec;
    uint32_t bytesSent = 0;
    firstSector = true;
    
    while (track != 0) {
        if (!d64ReadSector(track, sec, sector)) {
            Serial.println("[D64] Read error (streaming)");
            return false;
        }
        
        uint8_t nextTrack = sector[0];
        uint8_t nextSector = sector[1];
        
        int bytesInSector;
        if (nextTrack == 0) {
            bytesInSector = nextSector - 1;
        } else {
            bytesInSector = 254;
        }
        
        // Salta i primi 2 bytes (load address) solo nel primo settore
        int startOffset = firstSector ? 4 : 2;  // 2 link + 2 load addr nel primo
        int dataBytes = firstSector ? (bytesInSector - 2) : bytesInSector;
        
        if (dataBytes > 0) {
            for (int i = 0; i < dataBytes; i++) {
                FPGASerial.write(sector[startOffset + i]);
                bytesSent++;
                if ((bytesSent % 64) == 0) delayMicroseconds(500);
            }
        }
        
        if ((bytesSent % 1024) < 256) {
            Serial.printf("[D64] Sent %d/%d bytes\n", bytesSent, fileSize - 2);
        }
        
        firstSector = false;
        track = nextTrack;
        sec = nextSector;
    }
    
    Serial.printf("[D64] Transfer complete: %d bytes\n", bytesSent);
    
    delay(100);
    sendToFPGA("PROG_END");
    
    if (waitResponse("PRG_DONE", 2000)) {
        Serial.printf("[D64] Loaded: %d bytes @ $%04X\n", fileSize - 2, loadAddr);
        
        // Calcola fine programma
        uint16_t endAddr = loadAddr + (fileSize - 2);
        
        delay(500);
        
        if (loadAddr == 0x0801) {
            // Programma BASIC - dobbiamo aggiornare i puntatori
            // Invia POKE per impostare fine programma ($2D-$2E)
            Serial.println("[D64] Setting BASIC pointers...");
            
            // POKE 45,<low byte>: POKE 46,<high byte>
            char pokeCmd[40];
            sprintf(pokeCmd, "POKE45,%d:POKE46,%d", endAddr & 0xFF, (endAddr >> 8) & 0xFF);
            for (int i = 0; pokeCmd[i]; i++) {
                sendKeyToFPGA(pokeCmd[i]);
            }
            sendKeyToFPGA(13);
            delay(300);
            
            // Ora CLR per reinizializzare le variabili
            Serial.println("[D64] Sending CLR...");
            sendKeyToFPGA('C');
            sendKeyToFPGA('L');
            sendKeyToFPGA('R');
            sendKeyToFPGA(13);
            delay(300);
            
            // Infine RUN
            Serial.println("[D64] Sending RUN...");
            sendKeyToFPGA('R');
            sendKeyToFPGA('U');
            sendKeyToFPGA('N');
            sendKeyToFPGA(13);
        } else {
            Serial.printf("[D64] Sending SYS %d...\n", loadAddr);
            char sysCmd[20];
            sprintf(sysCmd, "SYS %d", loadAddr);
            for (int i = 0; sysCmd[i]; i++) {
                sendKeyToFPGA(sysCmd[i]);
            }
            sendKeyToFPGA(13);
        }
        return true;
    }
    
    Serial.println("[D64] Load failed");
    return false;
}

// Elenca i file D64 disponibili nella cartella floppy
int scanD64Files() {
    File dir = SD.open(D64_PATH);
    if (!dir) {
        Serial.printf("[D64] Folder not found: %s\n", D64_PATH);
        Serial.println("[D64] Create /floppy folder on SD card");
        return 0;
    }
    
    Serial.println("\n=== D64 DISK IMAGES ===\n");
    
    int count = 0;
    while (File f = dir.openNextFile()) {
        String name = f.name();
        if (!f.isDirectory() && (name.endsWith(".d64") || name.endsWith(".D64"))) {
            Serial.printf("[%2d] %s (%d bytes)\n", count, name.c_str(), f.size());
            count++;
        }
        f.close();
    }
    dir.close();
    
    if (count == 0) {
        Serial.println("No D64 files found.");
        Serial.printf("Put .d64 files in %s/\n", D64_PATH);
    }
    
    return count;
}

//==============================================================================
// LOAD_REQ SUPPORT - FPGA Virtual LOAD Command
//==============================================================================
// Gestisce richieste LOAD dal C64 intercettate dall'FPGA
// Formato: LOAD_REQ filename device secondary

// Trova un file nella directory D64 per nome (case insensitive)
int d64FindFile(const char* filename) {
    if (!d64Mounted || d64EntryCount == 0) {
        d64ReadDirectory();
    }
    
    String searchName = String(filename);
    searchName.toUpperCase();
    searchName.trim();
    
    // Rimuovi estensione se presente
    int dotPos = searchName.lastIndexOf('.');
    if (dotPos > 0) {
        searchName = searchName.substring(0, dotPos);
    }
    
    for (int i = 0; i < d64EntryCount; i++) {
        String entryName = String(d64Directory[i].filename);
        entryName.trim();
        
        // Match esatto
        if (entryName.equalsIgnoreCase(searchName)) {
            return i;
        }
        
        // Wildcard * - primo file PRG
        if (searchName == "*" && d64Directory[i].fileType == 2) {
            return i;
        }
        
        // Pattern con * alla fine (es. "GAME*")
        if (searchName.endsWith("*")) {
            String pattern = searchName.substring(0, searchName.length() - 1);
            if (entryName.startsWith(pattern) && d64Directory[i].fileType == 2) {
                return i;
            }
        }
    }
    
    return -1;  // Non trovato
}

// Cerca un file PRG diretto sulla SD
String findDirectPRG(const char* filename) {
    String baseDirs[] = { "/progs/c64/", "/progs/", "/" };
    String extensions[] = { ".prg", ".PRG", "" };
    String fname = String(filename);
    fname.toUpperCase();
    
    for (int d = 0; d < 3; d++) {
        for (int e = 0; e < 3; e++) {
            String fullPath = baseDirs[d] + fname + extensions[e];
            if (SD.exists(fullPath)) {
                return fullPath;
            }
            // Prova lowercase
            String lowerPath = baseDirs[d] + fname;
            lowerPath.toLowerCase();
            lowerPath += extensions[e];
            if (SD.exists(lowerPath)) {
                return lowerPath;
            }
        }
    }
    return "";
}

// Cerca e monta un D64 che contiene il file richiesto
bool findAndMountD64WithFile(const char* filename) {
    String baseDirs[] = { "/floppy/", "/disks/c64/", "/disks/", "/" };
    
    for (int d = 0; d < 4; d++) {
        File dir = SD.open(baseDirs[d]);
        if (!dir || !dir.isDirectory()) continue;
        
        while (File f = dir.openNextFile()) {
            String name = f.name();
            if (!f.isDirectory() && (name.endsWith(".d64") || name.endsWith(".D64"))) {
                String fullPath = baseDirs[d] + name;
                f.close();
                
                // Monta e cerca
                if (d64Mount(fullPath.c_str())) {
                    d64ReadDirectory();
                    int idx = d64FindFile(filename);
                    if (idx >= 0) {
                        dir.close();
                        return true;  // Trovato! D64 già montato
                    }
                    d64Unmount();
                }
            } else {
                f.close();
            }
        }
        dir.close();
    }
    return false;
}

// Carica un file PRG diretto e invia all'FPGA
bool loadDirectPRG(String path) {
    File file = SD.open(path);
    if (!file) {
        Serial.printf("[LOAD] Cannot open: %s\n", path.c_str());
        return false;
    }
    
    uint32_t fileSize = file.size();
    if (fileSize < 3) {
        file.close();
        return false;
    }
    
    // Leggi load address
    uint8_t addrLow = file.read();
    uint8_t addrHigh = file.read();
    uint16_t loadAddr = addrLow | (addrHigh << 8);
    uint32_t dataSize = fileSize - 2;
    
    Serial.printf("[LOAD] PRG: %s @ $%04X, %d bytes\n", path.c_str(), loadAddr, dataSize);
    
    // Invia PROG_START
    char cmd[32];
    sprintf(cmd, "PROG_START %04X %04X", loadAddr, (uint16_t)dataSize);
    sendToFPGA(cmd);
    
    if (!waitResponse("PRG_OK", 2000)) {
        file.close();
        return false;
    }
    
    delay(10);
    
    // Invia dati
    uint32_t sent = 0;
    uint8_t buffer[64];
    while (file.available() && sent < dataSize) {
        int toRead = min((uint32_t)64, dataSize - sent);
        int bytesRead = file.read(buffer, toRead);
        for (int i = 0; i < bytesRead; i++) {
            FPGASerial.write(buffer[i]);
            sent++;
            if (sent % 16 == 0) delayMicroseconds(200);
        }
    }
    file.close();
    
    delay(50);
    sendToFPGA("PROG_END");
    waitResponse("PRG_DONE", 1000);
    
    return true;
}

// Carica file da D64 già montato e invia all'FPGA (versione senza auto-run)
bool d64LoadFileNoRun(int index) {
    if (!d64Mounted || index < 0 || index >= d64EntryCount) {
        return false;
    }
    
    D64DirEntry* entry = &d64Directory[index];
    if (entry->fileType != 2) {  // Solo PRG
        return false;
    }
    
    Serial.printf("[LOAD] D64 file: %s\n", entry->filename);
    
    // Calcola dimensione file
    uint8_t sector[256];
    uint32_t fileSize = 0;
    uint8_t track = entry->startTrack;
    uint8_t sec = entry->startSector;
    uint16_t loadAddr = 0;
    bool firstSector = true;
    uint8_t startTrack = track;
    uint8_t startSec = sec;
    
    while (track != 0) {
        if (!d64ReadSector(track, sec, sector)) break;
        uint8_t nextTrack = sector[0];
        uint8_t nextSector = sector[1];
        int bytesInSector = (nextTrack == 0) ? (nextSector - 1) : 254;
        if (firstSector) {
            loadAddr = sector[2] | (sector[3] << 8);
            firstSector = false;
        }
        fileSize += bytesInSector;
        track = nextTrack;
        sec = nextSector;
        if (fileSize > 65536) break;
    }
    
    if (fileSize < 2) return false;
    
    Serial.printf("[LOAD] D64: $%04X, %d bytes\n", loadAddr, fileSize - 2);
    
    // Invia PROG_START
    char cmd[32];
    sprintf(cmd, "PROG_START %04X %04X", loadAddr, fileSize - 2);
    sendToFPGA(cmd);
    
    if (!waitResponse("PRG_OK", 2000)) {
        return false;
    }
    
    // Invia dati
    track = startTrack;
    sec = startSec;
    firstSector = true;
    
    while (track != 0) {
        if (!d64ReadSector(track, sec, sector)) break;
        uint8_t nextTrack = sector[0];
        uint8_t nextSector = sector[1];
        int bytesInSector = (nextTrack == 0) ? (nextSector - 1) : 254;
        int startOffset = firstSector ? 4 : 2;
        int dataBytes = firstSector ? (bytesInSector - 2) : bytesInSector;
        
        if (dataBytes > 0) {
            for (int i = 0; i < dataBytes; i++) {
                FPGASerial.write(sector[startOffset + i]);
                if ((i % 16) == 0) delayMicroseconds(200);
            }
        }
        firstSector = false;
        track = nextTrack;
        sec = nextSector;
    }
    
    delay(50);
    sendToFPGA("PROG_END");
    waitResponse("PRG_DONE", 1000);
    
    return true;
}

// Handler principale per LOAD_REQ
void handleLoadRequest(String line) {
    // Formato: "LOAD_REQ filename device secondary"
    Serial.print("[LOAD_REQ] ");
    Serial.println(line);
    
    int firstSpace = line.indexOf(' ');
    int secondSpace = line.indexOf(' ', firstSpace + 1);
    int thirdSpace = line.indexOf(' ', secondSpace + 1);
    
    if (firstSpace < 0 || secondSpace < 0) {
        Serial.println("[LOAD] Invalid format");
        FPGASerial.println("LOAD_ERR");
        return;
    }
    
    String filename = line.substring(firstSpace + 1, secondSpace);
    filename.trim();
    filename.toUpperCase();
    
    String deviceStr = line.substring(secondSpace + 1, thirdSpace > 0 ? thirdSpace : line.length());
    uint8_t device = (uint8_t)strtol(deviceStr.c_str(), NULL, 16);
    
    bool secondary = false;
    if (thirdSpace > 0) {
        secondary = (line.charAt(thirdSpace + 1) == '1');
    }
    
    Serial.printf("[LOAD] File: '%s', Dev: %d, Sec: %d\n", filename.c_str(), device, secondary);
    
    bool loaded = false;
    
    // 1. Cerca PRG diretto
    String prgPath = findDirectPRG(filename.c_str());
    if (prgPath.length() > 0) {
        FPGASerial.println("LOAD_ACK");
        delay(10);
        loaded = loadDirectPRG(prgPath);
    }
    
    // 2. Se D64 già montato, cerca lì
    if (!loaded && d64Mounted) {
        int idx = d64FindFile(filename.c_str());
        if (idx >= 0) {
            FPGASerial.println("LOAD_ACK");
            delay(10);
            loaded = d64LoadFileNoRun(idx);
        }
    }
    
    // 3. Cerca in tutti i D64 disponibili
    if (!loaded) {
        if (findAndMountD64WithFile(filename.c_str())) {
            int idx = d64FindFile(filename.c_str());
            if (idx >= 0) {
                FPGASerial.println("LOAD_ACK");
                delay(10);
                loaded = d64LoadFileNoRun(idx);
            }
        }
    }
    
    if (loaded) {
        Serial.println("[LOAD] Success!");
        FPGASerial.println("LOAD_OK");
    } else {
        Serial.printf("[LOAD] File not found: %s\n", filename.c_str());
        FPGASerial.println("LOAD_ERR");
    }
}

//==============================================================================
// ZX SPECTRUM TAP/BAS FILE SUPPORT - IMPLEMENTATION
//==============================================================================
// TAP format: sequence of data blocks
// Each block: 2 bytes length (LSB) + data bytes
// Data block structure:
//   byte 0: flag (0x00 = header, 0xFF = data)
//   bytes 1-n: payload
//   byte n+1: checksum (XOR of all bytes)
//
// Header block (17 bytes after flag):
//   byte 0: type (0=Program, 1=Number array, 2=Character array, 3=Code)
//   bytes 1-10: filename (padded with spaces)
//   bytes 11-12: data length (LSB)
//   bytes 13-14: param1 (start addr for Code, autostart line for Program)
//   bytes 15-16: param2 (32768 for Code, program length for Program)
//==============================================================================

// TAP block storage (struct defined in header section)
TAPBlock tapBlocks[MAX_TAP_BLOCKS];
int tapBlockCount = 0;

// Parse TAP file and return number of loadable blocks
int parseTAPFile(File& f) {
    tapBlockCount = 0;
    f.seek(0);

    uint32_t filePos = 0;
    uint32_t fileSize = f.size();

    Serial.println("[TAP] Parsing TAP file...");

    while (filePos < fileSize && tapBlockCount < MAX_TAP_BLOCKS) {
        // Read block length (2 bytes, LSB first)
        uint8_t lenLo = f.read();
        uint8_t lenHi = f.read();
        uint16_t blockLen = lenLo | (lenHi << 8);
        filePos += 2;

        if (blockLen == 0 || filePos + blockLen > fileSize) {
            Serial.printf("[TAP] Invalid block length at %d: %d\n", filePos - 2, blockLen);
            break;
        }

        // Read flag byte
        uint8_t flag = f.read();
        filePos++;

        TAPBlock* block = &tapBlocks[tapBlockCount];
        block->flag = flag;
        block->blockLen = blockLen;

        if (flag == 0x00 && blockLen == 19) {
            // Header block
            block->type = f.read();

            // Read filename (10 bytes)
            for (int i = 0; i < 10; i++) {
                block->filename[i] = f.read();
            }
            block->filename[10] = '\0';

            // Trim trailing spaces
            for (int i = 9; i >= 0 && block->filename[i] == ' '; i--) {
                block->filename[i] = '\0';
            }

            // Data length
            uint8_t dl = f.read();
            uint8_t dh = f.read();
            block->dataLen = dl | (dh << 8);

            // Param1 (start addr or autostart line)
            uint8_t p1l = f.read();
            uint8_t p1h = f.read();
            block->param1 = p1l | (p1h << 8);

            // Param2
            uint8_t p2l = f.read();
            uint8_t p2h = f.read();
            block->param2 = p2l | (p2h << 8);

            // Skip checksum
            f.read();
            filePos += 17;

            // Next block should be data
            block->dataOffset = filePos + 2 + 1;  // +2 for length, +1 for flag

            const char* typeStr[] = {"Program", "Num Array", "Char Array", "Code"};
            Serial.printf("[TAP] Block %d: %s '%s' len=%d addr=$%04X\n",
                          tapBlockCount,
                          block->type < 4 ? typeStr[block->type] : "Unknown",
                          block->filename,
                          block->dataLen,
                          block->param1);

            tapBlockCount++;
        } else if (flag == 0xFF) {
            // Data block - skip it (we'll read it when loading)
            f.seek(f.position() + blockLen - 1);  // -1 because we already read flag
            filePos += blockLen - 1;
            Serial.printf("[TAP] Data block: %d bytes\n", blockLen - 2);  // -2 for flag+checksum
        } else {
            // Unknown block type
            Serial.printf("[TAP] Unknown flag: 0x%02X at pos %d\n", flag, filePos - 1);
            f.seek(f.position() + blockLen - 1);
            filePos += blockLen - 1;
        }
    }

    Serial.printf("[TAP] Found %d loadable blocks\n", tapBlockCount);
    return tapBlockCount;
}

// Load a specific block from TAP file to Spectrum
bool loadTAPBlock(File& f, int blockIndex) {
    if (blockIndex < 0 || blockIndex >= tapBlockCount) {
        Serial.println("[TAP] Invalid block index");
        return false;
    }

    TAPBlock* block = &tapBlocks[blockIndex];

    // Only load Program or Code blocks
    if (block->type != 0 && block->type != 3) {
        Serial.println("[TAP] Can only load Program or Code blocks");
        return false;
    }

    Serial.printf("[TAP] Loading block '%s' (%d bytes)\n", block->filename, block->dataLen);

    // Seek to data block
    f.seek(block->dataOffset);

    // Read and verify data block length
    uint8_t lenLo = f.read();
    uint8_t lenHi = f.read();
    uint16_t dataBlockLen = lenLo | (lenHi << 8);

    // Read flag (should be 0xFF for data)
    uint8_t dataFlag = f.read();
    if (dataFlag != 0xFF) {
        Serial.printf("[TAP] Expected data block (0xFF), got 0x%02X\n", dataFlag);
        return false;
    }

    // Calculate actual data bytes (excluding flag and checksum)
    uint16_t dataBytes = dataBlockLen - 2;

    // Determine load address
    uint16_t loadAddr;
    if (block->type == 3) {
        // Code block - use param1 as load address
        loadAddr = block->param1;
    } else {
        // Program block - load to PROG area (23755 = 0x5CCB)
        loadAddr = 23755;
    }

    Serial.printf("[TAP] Load address: $%04X, size: %d bytes\n", loadAddr, dataBytes);

    // Send PROG_START command to FPGA
    char cmd[32];
    sprintf(cmd, "PROG_START %04X %04X", loadAddr, dataBytes);
    sendToFPGA(cmd);

    if (!waitResponse("PRG_OK", 2000)) {
        Serial.println("[TAP] FPGA did not accept PROG_START");
        return false;
    }

    // Send data bytes
    uint32_t sent = 0;
    uint8_t checksum = 0xFF;  // Start with flag

    while (sent < dataBytes && f.available()) {
        uint8_t byte = f.read();
        checksum ^= byte;
        FPGASerial.write(byte);
        sent++;

        if (sent % 1024 == 0) {
            Serial.printf("[TAP] %d/%d bytes\n", sent, dataBytes);
        }
        if (sent % 64 == 0) delayMicroseconds(500);
    }

    // Read and verify checksum
    uint8_t fileChecksum = f.read();
    if (checksum != fileChecksum) {
        Serial.printf("[TAP] Checksum mismatch: calc=0x%02X file=0x%02X\n", checksum, fileChecksum);
        // Continue anyway - some files have wrong checksums
    }

    delay(100);
    sendToFPGA("PROG_END");

    if (waitResponse("PRG_DONE", 2000)) {
        Serial.printf("[TAP] Loaded %d bytes @ $%04X\n", sent, loadAddr);

        // For Program blocks, send RUN command
        if (block->type == 0) {
            delay(500);
            Serial.println("[TAP] Sending RUN...");
            sendKeyToFPGA('R');
            sendKeyToFPGA('U');
            sendKeyToFPGA('N');
            sendKeyToFPGA(13);
        } else if (block->type == 3) {
            // Code block - send RANDOMIZE USR address
            delay(500);
            Serial.printf("[TAP] Sending RANDOMIZE USR %d...\n", loadAddr);
            char usrCmd[32];
            sprintf(usrCmd, "RANDOMIZE USR %d", loadAddr);
            for (int i = 0; usrCmd[i]; i++) {
                sendKeyToFPGA(usrCmd[i]);
            }
            sendKeyToFPGA(13);
        }

        return true;
    }

    Serial.println("[TAP] Load failed");
    return false;
}

//==============================================================================
// ZX SPECTRUM BASIC (.BAS) FILE SUPPORT
//==============================================================================
// .BAS files are text files containing BASIC listings
// We convert them to tokenized Spectrum BASIC and create a TAP-like load
//
// Spectrum BASIC line format:
//   2 bytes: line number (MSB first!)
//   2 bytes: line length (LSB first, including CR at end)
//   n bytes: tokenized BASIC
//   1 byte: 0x0D (CR)
//==============================================================================

// Spectrum BASIC tokens (partial list - most common)
struct BasicToken {
    const char* keyword;
    uint8_t token;
};

// Tokens from 0xA5 onwards
// IMPORTANT: Tokens are sorted by length (longest first) to ensure correct matching
// e.g., "INKEY$" must match before "IN", "INPUT" before "IN", etc.
const BasicToken spectrumTokens[] = {
    // 9+ chars
    {"RANDOMIZE", 0xF9},
    // 8 chars
    {"CONTINUE", 0xE8},
    // 7 chars
    {"RESTORE", 0xE5}, {"INVERSE", 0xDD}, {"SCREEN$", 0xAA}, {"CLOSE #", 0xD4},
    // 6 chars
    {"INKEY$", 0xA6}, {"BRIGHT", 0xDC}, {"BORDER", 0xE7}, {"CIRCLE", 0xD8},
    {"FORMAT", 0xD0}, {"LPRINT", 0xE0}, {"RETURN", 0xFE}, {"VERIFY", 0xD6},
    {"DEF FN", 0xCE}, {"GO SUB", 0xED}, {"OPEN #", 0xD3},
    // 5 chars
    {"POINT", 0xA9}, {"FLASH", 0xDB}, {"ERASE", 0xD2}, {"INPUT", 0xEE},
    {"LLIST", 0xE1}, {"MERGE", 0xD5}, {"PAUSE", 0xF2}, {"CLEAR", 0xFD},
    {"PRINT", 0xF5}, {"GO TO", 0xEC}, {"PAPER", 0xDA}, {"GOSUB", 0xED},
    // 4 chars
    {"ATTR", 0xAB}, {"VAL$", 0xAE}, {"CODE", 0xAF}, {"PEEK", 0xBE},
    {"STR$", 0xC1}, {"CHR$", 0xC2}, {"LINE", 0xCA}, {"THEN", 0xCB},
    {"STEP", 0xCD}, {"MOVE", 0xD1}, {"BEEP", 0xD7}, {"OVER", 0xDE},
    {"STOP", 0xE2}, {"READ", 0xE3}, {"DATA", 0xE4}, {"NEXT", 0xF3},
    {"POKE", 0xF4}, {"PLOT", 0xF6}, {"SAVE", 0xF8}, {"DRAW", 0xFC},
    {"COPY", 0xFF}, {"LIST", 0xF0}, {"LOAD", 0xEF}, {"GOTO", 0xEC},
    // 3 chars
    {"RND", 0xA5}, {"TAB", 0xAD}, {"VAL", 0xB0}, {"LEN", 0xB1},
    {"SIN", 0xB2}, {"COS", 0xB3}, {"TAN", 0xB4}, {"ASN", 0xB5},
    {"ACS", 0xB6}, {"ATN", 0xB7}, {"EXP", 0xB9}, {"INT", 0xBA},
    {"SQR", 0xBB}, {"SGN", 0xBC}, {"ABS", 0xBD}, {"USR", 0xC0},
    {"NOT", 0xC3}, {"BIN", 0xC4}, {"AND", 0xC6}, {"CAT", 0xCF},
    {"INK", 0xD9}, {"OUT", 0xDF}, {"NEW", 0xE6}, {"DIM", 0xE9},
    {"REM", 0xEA}, {"FOR", 0xEB}, {"LET", 0xF1}, {"RUN", 0xF7},
    {"CLS", 0xFB},
    // 2 chars
    {"PI", 0xA7}, {"FN", 0xA8}, {"AT", 0xAC}, {"LN", 0xB8},
    {"IN", 0xBF}, {"OR", 0xC5}, {"TO", 0xCC}, {"IF", 0xFA},
    {"<=", 0xC7}, {">=", 0xC8}, {"<>", 0xC9},
    {NULL, 0}
};

// Buffer per BASIC tokenizzato
#define MAX_BAS_SIZE 32768
uint8_t basBuffer[MAX_BAS_SIZE];
uint16_t basBufferLen = 0;

// Tokenizza una linea BASIC
// Restituisce la lunghezza dei dati tokenizzati
int tokenizeBasicLine(const char* line, uint8_t* output) {
    int outPos = 0;
    int lineLen = strlen(line);
    int i = 0;

    // Salta spazi iniziali
    while (i < lineLen && line[i] == ' ') i++;

    while (i < lineLen) {
        // Cerca keyword match (case insensitive)
        bool found = false;

        for (int t = 0; spectrumTokens[t].keyword != NULL; t++) {
            int kwLen = strlen(spectrumTokens[t].keyword);
            if (i + kwLen <= lineLen) {
                bool match = true;
                for (int k = 0; k < kwLen && match; k++) {
                    char c1 = toupper(line[i + k]);
                    char c2 = spectrumTokens[t].keyword[k];
                    if (c1 != c2) match = false;
                }
                if (match) {
                    // Verifica che non sia parte di una parola più lunga
                    char nextChar = (i + kwLen < lineLen) ? line[i + kwLen] : ' ';
                    if (!isalpha(nextChar) ||
                        spectrumTokens[t].keyword[kwLen-1] == '$' ||
                        spectrumTokens[t].keyword[kwLen-1] == '#') {
                        output[outPos++] = spectrumTokens[t].token;
                        i += kwLen;
                        found = true;
                        break;
                    }
                }
            }
        }

        if (!found) {
            // Numero: aggiungi anche la rappresentazione floating point
            if (isdigit(line[i]) || (line[i] == '.' && i + 1 < lineLen && isdigit(line[i+1]))) {
                // Copia cifre del numero come caratteri
                int numStart = i;
                while (i < lineLen && (isdigit(line[i]) || line[i] == '.')) {
                    output[outPos++] = line[i++];
                }

                // Aggiungi marker numero (0x0E) seguito da 5 bytes floating point
                output[outPos++] = 0x0E;

                // Converti il numero in floating point Spectrum (semplificato)
                char numStr[32];
                int numLen = i - numStart;
                if (numLen > 31) numLen = 31;
                strncpy(numStr, &line[numStart], numLen);
                numStr[numLen] = '\0';
                double val = atof(numStr);

                // Formato floating point Spectrum (semplificato per interi)
                if (val == (int)val && val >= -65535 && val <= 65535) {
                    // Integer format: 00 00 LL HH 00
                    int16_t intVal = (int16_t)val;
                    output[outPos++] = 0x00;
                    output[outPos++] = 0x00;
                    output[outPos++] = intVal & 0xFF;
                    output[outPos++] = (intVal >> 8) & 0xFF;
                    output[outPos++] = 0x00;
                } else {
                    // Full floating point (placeholder - 0 for now)
                    for (int j = 0; j < 5; j++) output[outPos++] = 0x00;
                }
            } else {
                // Carattere normale
                output[outPos++] = line[i++];
            }
        }
    }

    // Aggiungi CR alla fine della linea
    output[outPos++] = 0x0D;

    return outPos;
}

// ZX Spectrum K-mode keyword mapping
// In K-mode (at start of line), pressing a letter key produces a keyword
// We need to map BASIC keywords to their K-mode key equivalents
// Format: {keyword, key_to_press} - key is what to press in K-mode to get that keyword
struct SpectrumKModeKey {
    const char* keyword;
    char key;       // Key to press in K-mode
    bool extended;  // true if needs SYMBOL SHIFT (extended mode)
};

// K-mode mappings (main keys without SYMBOL SHIFT)
const SpectrumKModeKey kModeKeys[] = {
    {"PRINT", 'P'},
    {"LIST", 'K'},      // K in K-mode = LIST
    {"RUN", 'R'},
    {"NEW", 'A'},
    {"BORDER", 'B'},
    {"CONTINUE", 'C'},
    {"DIM", 'D'},
    {"REM", 'E'},
    {"FOR", 'F'},
    {"GO TO", 'G'},
    {"GOTO", 'G'},
    {"INPUT", 'I'},
    {"LOAD", 'J'},
    {"LET", 'L'},
    {"PAUSE", 'M'},
    {"NEXT", 'N'},
    {"POKE", 'O'},
    {"PLOT", 'Q'},
    {"RETURN", 'Y'},
    {"RANDOMIZE", 'T'},
    {"IF", 'U'},
    {"CLS", 'V'},
    {"SAVE", 'S'},
    {"DRAW", 'W'},
    {"CLEAR", 'X'},
    {"COPY", 'Z'},
    {NULL, 0}
};

// Extended mode (CAPS SHIFT + SYMBOL SHIFT + key)
// These require special codes: 0x80 + ASCII value of key
// The FPGA Verilog code interprets these as CAPS+SYM+key combinations
const SpectrumKModeKey extModeKeys[] = {
    {"INK", 0xD8},      // 0x80 + 'X' (88) = INK
    {"PAPER", 0xC3},    // 0x80 + 'C' (67) = PAPER
    {"FLASH", 0xD6},    // 0x80 + 'V' (86) = FLASH
    {"BRIGHT", 0xC2},   // 0x80 + 'B' (66) = BRIGHT
    {"INVERSE", 0xCD},  // 0x80 + 'M' (77) = INVERSE
    {"OVER", 0xCE},     // 0x80 + 'N' (78) = OVER
    {"BEEP", 0xDA},     // 0x80 + 'Z' (90) = BEEP
    {"CIRCLE", 0xC8},   // 0x80 + 'H' (72) = CIRCLE
    {NULL, 0}
};

// Invia una keyword cercando la mappatura K-mode
// Restituisce il numero di caratteri consumati dalla linea, 0 se non trovata
int sendSpectrumKeyword(const char* text) {
    // Prima cerca nelle keyword K-mode standard
    for (int i = 0; kModeKeys[i].keyword != NULL; i++) {
        int kwLen = strlen(kModeKeys[i].keyword);
        if (strncasecmp(text, kModeKeys[i].keyword, kwLen) == 0) {
            // Verifica che non sia parte di una parola più lunga
            char nextChar = text[kwLen];
            if (nextChar == '\0' || nextChar == ' ' || isdigit(nextChar) ||
                nextChar == '"' || nextChar == '(' || nextChar == ')' ||
                nextChar == ',' || nextChar == ';' || nextChar == ':') {
                // Invia il tasto K-mode
                sendKeyToFPGA(kModeKeys[i].key);
                delay(80);
                return kwLen;
            }
        }
    }

    // Cerca nelle keyword extended mode (richiedono CAPS+SYMBOL SHIFT)
    for (int i = 0; extModeKeys[i].keyword != NULL; i++) {
        int kwLen = strlen(extModeKeys[i].keyword);
        if (strncasecmp(text, extModeKeys[i].keyword, kwLen) == 0) {
            char nextChar = text[kwLen];
            if (nextChar == '\0' || nextChar == ' ' || isdigit(nextChar) ||
                nextChar == '"' || nextChar == '(' || nextChar == ')' ||
                nextChar == ',' || nextChar == ';' || nextChar == ':') {
                // Invia il codice speciale (0x80 + key) che l'FPGA interpreta
                // come CAPS SHIFT + SYMBOL SHIFT + key
                sendKeyToFPGA(extModeKeys[i].key);  // Il codice è già 0x80+key
                delay(100);
                return kwLen;
            }
        }
    }

    return 0;  // Non trovata
}

// Carica file .BAS inviando le linee come testo
// Usa la mappatura K-mode per le keyword
bool loadBASFile(File& f) {
    Serial.println("[BAS] Loading BASIC file via keyboard input...");

    char lineBuffer[256];
    int lineIndex = 0;
    int lineCount = 0;

    while (f.available()) {
        // Leggi una linea
        lineIndex = 0;
        while (f.available() && lineIndex < 254) {
            char c = f.read();
            if (c == '\n' || c == '\r') {
                if (f.available()) {
                    char next = f.peek();
                    if ((c == '\r' && next == '\n') || (c == '\n' && next == '\r')) {
                        f.read();
                    }
                }
                break;
            }
            lineBuffer[lineIndex++] = c;
        }
        lineBuffer[lineIndex] = '\0';

        // Salta linee vuote
        if (lineIndex == 0) continue;

        // Salta linee che non iniziano con un numero
        int i = 0;
        while (lineBuffer[i] == ' ') i++;
        if (!isdigit(lineBuffer[i])) {
            Serial.printf("[BAS] Skipping: %s\n", lineBuffer);
            continue;
        }

        Serial.printf("[BAS] Sending: %s\n", lineBuffer);

        // Invia numero di linea (in L-mode, i numeri sono normali)
        while (isdigit(lineBuffer[i])) {
            sendKeyToFPGA(lineBuffer[i++]);
            delay(50);
        }

        // Salta spazi dopo numero
        while (lineBuffer[i] == ' ') {
            sendKeyToFPGA(' ');
            delay(50);
            i++;
        }

        // Ora siamo in K-mode - processa il resto della linea
        bool inString = false;
        while (lineBuffer[i]) {
            if (lineBuffer[i] == '"') {
                inString = !inString;
                sendKeyToFPGA('"');
                delay(50);
                i++;
            }
            else if (inString) {
                // Dentro una stringa, invia caratteri normali
                sendKeyToFPGA(lineBuffer[i++]);
                delay(50);
            }
            else if (lineBuffer[i] == ' ') {
                sendKeyToFPGA(' ');
                delay(50);
                i++;
            }
            else if (isdigit(lineBuffer[i])) {
                // Numeri passano normalmente
                sendKeyToFPGA(lineBuffer[i++]);
                delay(50);
            }
            else if (isalpha(lineBuffer[i])) {
                // Prova a trovare una keyword
                int consumed = sendSpectrumKeyword(&lineBuffer[i]);
                if (consumed > 0) {
                    i += consumed;
                } else {
                    // Lettera singola - invia come minuscola (L-mode)
                    // Lo Spectrum dovrebbe essere in L-mode dopo una keyword
                    sendKeyToFPGA(tolower(lineBuffer[i++]));
                    delay(50);
                }
            }
            else {
                // Altri caratteri (operatori, punteggiatura)
                sendKeyToFPGA(lineBuffer[i++]);
                delay(50);
            }
        }

        // Invia ENTER
        sendKeyToFPGA(13);
        delay(300);

        lineCount++;
    }

    if (lineCount == 0) {
        Serial.println("[BAS] No valid BASIC lines found");
        return false;
    }

    Serial.printf("[BAS] Loaded %d lines\n", lineCount);

    delay(500);

    // Invia RUN (R in K-mode = RUN)
    Serial.println("[BAS] Sending RUN...");
    sendKeyToFPGA('R');
    delay(100);
    sendKeyToFPGA(13);

    return true;
}

//==============================================================================
// DISPLAY
//==============================================================================

void drawHeader() {
    tft.fillRect(0, 0, 240, 40, COLOR_HEADER);
    tft.setTextColor(COLOR_TEXT);
    tft.setTextDatum(MC_DATUM);
    tft.drawString("RETROPC v4", 120, 20, 4);
}

void drawStatus() {
    tft.fillRect(0, 280, 240, 40, COLOR_BG);
    tft.setTextColor(fpgaReady ? COLOR_ACTIVE : COLOR_ERROR);
    tft.setTextDatum(ML_DATUM);
    tft.drawString(fpgaReady ? "FPGA: OK" : "FPGA: --", 10, 295, 2);
    
    tft.setTextColor(sdCardReady ? COLOR_ACTIVE : COLOR_ERROR);
    tft.drawString(sdCardReady ? "SD: OK" : "SD: --", 120, 295, 2);
    
    tft.setTextColor(COLOR_TEXT);
    tft.setTextDatum(MR_DATUM);
    tft.drawString(getCurrentIP(), 230, 310, 1);
}

void drawIconFast(int16_t x, int16_t y, int iconIndex) {
    if (iconIndex < 0 || iconIndex >= NUM_ICONS) return;
    
    const uint16_t* iconPtr = (const uint16_t*)pgm_read_ptr(&system_icons[iconIndex]);
    uint16_t lineBuf[ICON_WIDTH];
    
    for (int row = 0; row < ICON_HEIGHT; row++) {
        for (int col = 0; col < ICON_WIDTH; col++) {
            lineBuf[col] = pgm_read_word(&iconPtr[row * ICON_WIDTH + col]);
        }
        tft.pushImage(x, y + row, ICON_WIDTH, 1, lineBuf);
    }
}

void drawSystemGrid() {
    // Layout: 4 icone agli angoli + 1 al centro (Test Pattern)
    // Display 240x320, area icone 240x220 (y: 45-265)
    tft.fillRect(0, 40, 240, 230, COLOR_BG);

    int iconSize = ICON_WIDTH;  // 64x64
    int margin = 10;            // Margine dai bordi
    int centerY = 145;          // Centro verticale area icone

    // Posizioni fisse per i 5 sistemi:
    // [1] C64        [2] Spectrum    (angoli superiori)
    //           [0] Test           (centro)
    // [3] VIC-20    [4] Apple I     (angoli inferiori)

    struct IconPos { int x; int y; int sysIdx; };
    IconPos positions[5] = {
        {88,  centerY - iconSize/2,        0},  // Centro: Test Pattern
        {margin,         50,               1},  // Top-Left: C64
        {240-margin-iconSize, 50,          2},  // Top-Right: Spectrum
        {margin,         200,              3},  // Bottom-Left: VIC-20
        {240-margin-iconSize, 200,         4},  // Bottom-Right: Apple I
    };

    for (int i = 0; i < 5; i++) {
        int x = positions[i].x;
        int y = positions[i].y;
        int sysIdx = positions[i].sysIdx;

        // Disegna icona
        if (sysIdx < NUM_ICONS) {
            drawIconFast(x, y, sysIdx);
        } else {
            // Placeholder
            tft.fillRect(x, y, iconSize, iconSize, COLOR_CARD);
            tft.setTextColor(COLOR_TEXT);
            tft.setTextDatum(MC_DATUM);
            tft.drawString(systems[sysIdx].id, x + iconSize/2, y + iconSize/2, 2);
        }

        // Etichetta sotto l'icona
        tft.setTextColor(COLOR_TEXT);
        tft.setTextDatum(TC_DATUM);
        tft.drawString(systems[sysIdx].name, x + iconSize/2, y + iconSize + 2, 1);

        // Bordo selezione (verde)
        if (sysIdx == selectedIndex) {
            tft.drawRect(x - 2, y - 2, iconSize + 4, iconSize + 4, COLOR_ACTIVE);
            tft.drawRect(x - 3, y - 3, iconSize + 6, iconSize + 6, COLOR_ACTIVE);
        }

        // Indicatore ROM disponibili (pallino verde in alto a destra)
        if (systems[sysIdx].romCount > 0) {
            tft.fillCircle(x + iconSize - 8, y + 8, 6, 0x07E0);
            tft.drawCircle(x + iconSize - 8, y + 8, 6, COLOR_TEXT);
        }
    }
}

void redrawScreen() {
    tft.fillScreen(COLOR_BG);
    drawHeader();
    drawSystemGrid();
    drawStatus();
}

//==============================================================================
// TOUCH
//==============================================================================

void handleTouch() {
    if (!touch.Pressed()) return;

    if (millis() - lastTouch < 300) return;
    lastTouch = millis();

    uint16_t x = touch.X();
    uint16_t y = touch.Y();

    Serial.printf("[TOUCH] x=%d y=%d\n", x, y);

    // Layout identico a drawSystemGrid()
    int iconSize = ICON_WIDTH;  // 64x64
    int margin = 10;
    int centerY = 145;

    struct IconPos { int x; int y; int sysIdx; };
    IconPos positions[5] = {
        {88,  centerY - iconSize/2,        0},  // Centro: Test Pattern
        {margin,         50,               1},  // Top-Left: C64
        {240-margin-iconSize, 50,          2},  // Top-Right: Spectrum
        {margin,         200,              3},  // Bottom-Left: VIC-20
        {240-margin-iconSize, 200,         4},  // Bottom-Right: Apple I
    };

    for (int i = 0; i < 5; i++) {
        int cx = positions[i].x;
        int cy = positions[i].y;
        int sysIdx = positions[i].sysIdx;

        if (x >= cx && x <= cx + iconSize && y >= cy && y <= cy + iconSize) {
            if (selectedIndex == sysIdx) {
                // Double tap - load system
                Serial.printf("[LOAD] System %d (%s)\n", sysIdx, systems[sysIdx].name);
                setLED(false, false, true);

                tft.fillRect(0, 280, 240, 40, COLOR_BG);
                tft.setTextColor(COLOR_WARNING);
                tft.setTextDatum(MC_DATUM);
                tft.drawString("Loading...", 120, 295, 2);

                bool ok = loadSystemROMs(sysIdx);

                setLED(false, ok, !ok);
                delay(500);
                setLED(false, false, false);

                redrawScreen();
            } else {
                // First tap - select
                selectedIndex = sysIdx;
                drawSystemGrid();
            }
            return;
        }
    }
}

//==============================================================================
// SERIAL COMMANDS
//==============================================================================

void handleSerialCommand() {
    if (!Serial.available()) return;
    
    char c = Serial.read();
    
    // Keyboard mode
    if (keyboardMode) {
        // Buffer per accumulare la stringa
        static String inputBuffer = "";
        static bool lineMode = true;  // true = accumula stringa, false = carattere singolo
        
        if (c == '~') {
            keyboardMode = false;
            inputBuffer = "";
            Serial.println("\n[EXIT] Keyboard mode disabled");
            return;
        }
        
        // Toggle tra line mode e character mode con ESC+M
        // Tasti speciali: usa ESC+lettera per inviarli
        static bool escMode = false;
        if (c == 27) {  // ESC
            escMode = true;
            Serial.print("[ESC]");
            return;
        }
        
        if (escMode) {
            escMode = false;
            uint8_t special = 0;
            switch (c) {
                case 'm': case 'M':  // Toggle mode
                    lineMode = !lineMode;
                    Serial.printf("\n[MODE] %s\n", lineMode ? "LINE (buffer+RETURN)" : "CHAR (immediato)");
                    return;
                case 'u': case 'U': special = 145; break;  // Cursor UP (C64)
                case 'd': case 'D': special = 17;  break;  // Cursor DOWN
                case 'l': case 'L': special = 157; break;  // Cursor LEFT
                case 'r': case 'R': special = 29;  break;  // Cursor RIGHT
                case 'h': case 'H': special = 19;  break;  // HOME
                case 'c': case 'C': special = 147; break;  // CLR (clear screen)
                case 'i': case 'I': special = 148; break;  // INSERT
                case 'x': case 'X': special = 20;  break;  // DELETE
                case 'n': case 'N': special = 13;  break;  // RETURN (newline)
                case 's': case 'S': special = 32;  break;  // SPACE
                case '1': special = 133; break;  // F1
                case '2': special = 137; break;  // F2
                case '3': special = 134; break;  // F3
                case '4': special = 138; break;  // F4
                case '5': special = 135; break;  // F5
                case '6': special = 139; break;  // F6
                case '7': special = 136; break;  // F7
                case '8': special = 140; break;  // F8
                default:
                    Serial.printf("[?%c]", c);
                    return;
            }
            sendKeyToFPGA(special);
            Serial.printf("[KEY:%d]", special);
            return;
        }
        
        // LINE MODE: accumula caratteri e invia con RETURN quando premi INVIO
        if (lineMode) {
            if (c == '\r' || c == '\n') {
                // Invia tutta la stringa accumulata
                Serial.printf("\n[SEND] '%s' + RETURN\n", inputBuffer.c_str());
                
                for (int i = 0; i < inputBuffer.length(); i++) {
                    uint8_t ch = inputBuffer[i];
                    
                    // Converti minuscole in maiuscole per Commodore/Apple
                    if (currentCore >= 1 && currentCore <= 4) {
                        if (ch >= 'a' && ch <= 'z') ch -= 32;
                    }
                    
                    sendKeyToFPGA(ch);
                }
                
                // Invia RETURN corretto per ogni core
                uint8_t returnCode = 13;  // Default CR
                switch (currentCore) {
                    case 0:  // C64
                    case 1:  // C64 (alt)
                    case 3:  // VIC-20
                        returnCode = 13;  // CR
                        break;
                    case 2:  // ZX Spectrum
                        returnCode = 13;  // ENTER
                        break;
                    case 4:  // Apple I
                        returnCode = 13;  // CR (0x0D)
                        break;
                }
                sendKeyToFPGA(returnCode);
                Serial.printf("[RET:%d]\n", returnCode);
                
                inputBuffer = "";
                return;
            }
            else if (c == 8 || c == 127) {  // Backspace
                if (inputBuffer.length() > 0) {
                    inputBuffer.remove(inputBuffer.length() - 1);
                    Serial.print("\b \b");  // Cancella carattere su terminale
                }
                return;
            }
            else {
                // Accumula nel buffer
                inputBuffer += c;
                Serial.print(c);
                return;
            }
        }
        
        // CHARACTER MODE: invia subito ogni carattere (comportamento originale)
        // Converti in maiuscolo per Commodore
        if (currentCore >= 1 && currentCore <= 4) {
            if (c >= 'a' && c <= 'z') c -= 32;
        }
        
        // INVIO normale
        if (c == '\r' || c == '\n') {
            sendKeyToFPGA(13);
            Serial.println("[RET]");
            return;
        }
        
        sendKeyToFPGA(c);
        Serial.print(c);
        return;
    }
    
    if (c == '\n' || c == '\r') return;
    
    Serial.printf("\n[CMD] %c\n", c);
    
    switch (c) {
        case '0': case '1': case '2': case '3': case '4':
            selectedIndex = c - '0';
            loadSystemROMs(c - '0');
            redrawScreen();
            break;
            
        case 'p': case 'P':
            testFPGA();
            break;
            
        case 's': case 'S':
            sendToFPGA("STATUS");
            getResponse(2000);
            break;
            
        case 'r': case 'R':
            sendToFPGA("RESET");
            romLoaded = false;
            break;
            
        case 'd': case 'D':
            scanROMs();
            break;
            
        case 'k': case 'K':
            Serial.println("\n=== KEYBOARD MODE ===");
            Serial.println("LINE MODE: digita stringa + INVIO (invia tutto + RETURN)");
            Serial.println("ESC+M: toggle LINE/CHAR mode");
            Serial.println("ESC+tasto: caratteri speciali (H=HOME, C=CLR, U/D/L/R=cursori)");
            Serial.println("~ per uscire\n");
            keyboardMode = true;
            break;
            
        case 'g': case 'G':
            listPrograms();
            break;
            
        case 'l': case 'L':
            Serial.printf("Enter program number (0-%d): ", programCount > 0 ? programCount - 1 : 0);
            {
                // Aspetta input numero (supporta più cifre)
                String numStr = "";
                while (true) {
                    if (Serial.available()) {
                        char c = Serial.read();
                        if (c == '\n' || c == '\r') {
                            break;
                        } else if (c >= '0' && c <= '9') {
                            numStr += c;
                            Serial.print(c);  // Echo
                        }
                    }
                    delay(10);
                }
                Serial.println();
                
                // Svuota buffer seriale
                delay(50);
                while (Serial.available()) Serial.read();
                
                if (numStr.length() > 0) {
                    int num = numStr.toInt();
                    if (num >= 0 && num < programCount) {
                        loadProgram(num);
                    } else {
                        Serial.printf("[!] Invalid number. Range: 0-%d\n", programCount - 1);
                    }
                }
            }
            break;
        
        // === D64 DISK IMAGE COMMANDS ===
        case 'm': case 'M':
            // Mostra file D64 disponibili e monta uno
            {
                Serial.println("\n=== D64 DISK IMAGES ===");
                File dir = SD.open(D64_PATH);
                if (!dir) {
                    Serial.printf("Folder not found: %s\n", D64_PATH);
                    Serial.println("Create /floppy folder on SD card");
                    break;
                }
                
                // Costruisci lista (filtra file ._ di MacOS)
                char d64Files[30][64];
                int d64Count = 0;
                
                while (File f = dir.openNextFile()) {
                    String name = f.name();
                    // Filtra file nascosti MacOS (._*) e altri file nascosti
                    if (!f.isDirectory() && !name.startsWith(".") && 
                        (name.endsWith(".d64") || name.endsWith(".D64"))) {
                        if (d64Count < 30) {
                            strncpy(d64Files[d64Count], name.c_str(), 63);
                            d64Files[d64Count][63] = '\0';
                            Serial.printf("[%2d] %s\n", d64Count, d64Files[d64Count]);
                            d64Count++;
                        }
                    }
                    f.close();
                }
                dir.close();
                
                if (d64Count == 0) {
                    Serial.println("No D64 files found");
                    break;
                }
                
                Serial.printf("\nEnter disk number (0-%d): ", d64Count - 1);
                
                // Aspetta input numero (supporta più cifre)
                String numStr = "";
                while (true) {
                    if (Serial.available()) {
                        char c = Serial.read();
                        if (c == '\n' || c == '\r') {
                            break;
                        } else if (c >= '0' && c <= '9') {
                            numStr += c;
                            Serial.print(c);  // Echo
                        }
                    }
                    delay(10);
                }
                Serial.println();
                
                // Svuota buffer seriale (rimuovi eventuali \r\n residui)
                delay(50);
                while (Serial.available()) Serial.read();
                
                if (numStr.length() > 0) {
                    int diskNum = numStr.toInt();
                    if (diskNum >= 0 && diskNum < d64Count) {
                        char fullPath[128];
                        sprintf(fullPath, "%s/%s", D64_PATH, d64Files[diskNum]);
                        if (d64Mount(fullPath)) {
                            d64ReadDirectory();
                            d64ShowDirectory();
                        }
                    } else {
                        Serial.printf("[!] Invalid number. Range: 0-%d\n", d64Count - 1);
                    }
                }
            }
            break;
            
        case 'f': case 'F':
            // Mostra directory D64 corrente
            d64ShowDirectory();
            break;
            
        case 'e': case 'E':
            // Carica file da D64
            if (!d64Mounted) {
                Serial.println("No disk mounted. Use 'm' first.");
                break;
            }
            Serial.printf("Enter file number (0-%d): ", d64EntryCount > 0 ? d64EntryCount - 1 : 0);
            {
                // Aspetta input numero (supporta più cifre)
                String numStr = "";
                while (true) {
                    if (Serial.available()) {
                        char c = Serial.read();
                        if (c == '\n' || c == '\r') {
                            break;
                        } else if (c >= '0' && c <= '9') {
                            numStr += c;
                            Serial.print(c);  // Echo
                        }
                    }
                    delay(10);
                }
                Serial.println();
                
                // Svuota buffer seriale
                delay(50);
                while (Serial.available()) Serial.read();
                
                if (numStr.length() > 0) {
                    int fileNum = numStr.toInt();
                    d64LoadFile(fileNum);
                }
            }
            break;
            
        case 'u': case 'U':
            // Smonta D64
            d64Unmount();
            break;
            
        case 't': case 'T':
            {
                // Apple I usa Woz Monitor, non BASIC
                if (currentCore == 4) {
                    Serial.println("[TEST] Apple I Woz Monitor test...");
                    Serial.println("[NOTE] Testing memory read/write with Woz Monitor");
                    
                    int charDelay = 100;
                    int lineDelay = 500;
                    
                    // Test Woz Monitor commands
                    const char* cmds[] = {
                        "300",           // Set address to $0300
                        "300.30F",       // Display memory $0300-$030F
                        "300: A9 41",    // Store LDA #'A' at $0300-$0301
                        "302: 8D 12 D0", // Store STA $D012 at $0302-$0304
                        "305: 4C 00 03", // Store JMP $0300 at $0305-$0307
                        "300.307",       // Verify our code
                        "300R"           // Run from $0300 (prints 'A' forever)
                    };
                    int numCmds = 7;
                    
                    for (int cmd = 0; cmd < numCmds; cmd++) {
                        const char* s = cmds[cmd];
                        Serial.printf("[CMD] %s\n", s);
                        
                        for (int i = 0; s[i]; i++) {
                            sendKeyToFPGA(s[i]);
                            delay(charDelay);
                        }
                        sendKeyToFPGA(13);  // RETURN
                        delay(lineDelay);
                    }
                    
                    Serial.println("[DONE] Apple I test complete!");
                    Serial.println("[NOTE] Screen should show 'A' being printed repeatedly");
                    break;
                }
                
                Serial.println("[TEST] Sending simple BASIC program...");
                
                // Programma BASIC ridotto per testare (senza FOR-NEXT complesso)
                const char* lines[] = {
                    "10 PRINT \"HELLO\"",
                    "20 PRINT \"WORLD\"",
                    "30 PRINT \"TEST OK\""
                };
                int numLines = 3;
                
                // Delay variabili per sistema
                int charDelay = 50;    // ms tra caratteri
                int lineDelay = 500;   // ms dopo ENTER
                
                // ZX Spectrum - timing ridotti (il problema era i caratteri, non il timing)
                if (currentCore == 2) {
                    charDelay = 100;   // 100ms tra caratteri
                    lineDelay = 1000;  // 1 secondo dopo ogni riga
                    Serial.println("[NOTE] ZX Spectrum: using moderate timing");
                }

                // Invia le righe del programma
                for (int line = 0; line < numLines; line++) {
                    const char* s = lines[line];
                    Serial.printf("[LINE] %s\n", s);

                    for (int i = 0; s[i]; i++) {
                        char ch = s[i];
                        // Converti in maiuscolo per tutti i sistemi
                        if (currentCore >= 1 && currentCore <= 4) {
                            if (ch >= 'a' && ch <= 'z') ch -= 32;
                        }
                        sendKeyToFPGA(ch);
                        delay(charDelay);
                    }
                    // Invia RETURN
                    sendKeyToFPGA(13);
                    Serial.println("[WAIT] Waiting for line to be processed...");
                    delay(lineDelay);
                }
                
                // Delay extra prima di RUN (non necessario dopo fix caratteri)
                if (currentCore == 2) {
                    Serial.println("[WAIT] Extra delay before RUN...");
                    delay(1000);
                }
                
                // Invia RUN
                Serial.println("[LINE] RUN");
                const char* runCmd = "RUN";
                for (int i = 0; runCmd[i]; i++) {
                    sendKeyToFPGA(runCmd[i]);
                    delay(charDelay);
                }
                sendKeyToFPGA(13);
                
                Serial.println("[DONE] Program sent!");
            }
            break;

	case 'c': case 'C':
            {
                // Apple I Display Test - stampa messaggio e caratteri ASCII
                if (currentCore == 4) {
                    Serial.println("\n[APPLE1 TEST] Sending Display Test...");
                    Serial.println("[APPLE1 TEST] Will print message and ASCII characters\n");
                    
                    // Test program bytes (81 bytes, loads at $0300)
                    // Stampa "TEST OUTPUT TO APPLE-1 DISPLAY." poi tutti i caratteri ASCII
                    const uint8_t apple1_test[] = {
                        0xA2, 0x00, 0xBD, 0x30, 0x03, 0xF0, 0x07, 0x20, 0x27, 0x03, 0xE8, 0x4C, 0x02, 0x03, 0xA9, 0x0D,
                        0x20, 0x27, 0x03, 0xA9, 0x21, 0x20, 0x27, 0x03, 0x18, 0x69, 0x01, 0xC9, 0x60, 0xD0, 0xF6, 0xA9,
                        0x0D, 0x20, 0x27, 0x03, 0x4C, 0x24, 0x03, 0x2C, 0x13, 0xD0, 0x30, 0xFB, 0x8D, 0x12, 0xD0, 0x60,
                        0x54, 0x45, 0x53, 0x54, 0x20, 0x4F, 0x55, 0x54, 0x50, 0x55, 0x54, 0x20, 0x54, 0x4F, 0x20, 0x41,
                        0x50, 0x50, 0x4C, 0x45, 0x2D, 0x31, 0x20, 0x44, 0x49, 0x53, 0x50, 0x4C, 0x41, 0x59, 0x2E, 0x0D,
                        0x00
                    };
                    const int apple1_test_len = 81;
                    
                    // Delay più lunghi per Woz Monitor
                    int charDelay = 120;   // Era 80, aumentato
                    int lineDelay = 500;   // Era 300, aumentato
                    
                    // Invia i byte in gruppi da 8 per riga Woz Monitor
                    for (int i = 0; i < apple1_test_len; i += 8) {
                        // Costruisci comando: ADDR: XX XX XX ...
                        char cmd[64];
                        int addr = 0x0300 + i;
                        int len = (apple1_test_len - i > 8) ? 8 : (apple1_test_len - i);
                        
                        sprintf(cmd, "%04X:", addr);
                        for (int j = 0; j < len; j++) {
                            char hex[4];
                            sprintf(hex, " %02X", apple1_test[i + j]);
                            strcat(cmd, hex);
                        }
                        
                        Serial.printf("[WOZ] %s\n", cmd);
                        
                        // Invia comando al Woz Monitor carattere per carattere
                        for (int c = 0; cmd[c]; c++) {
                            sendKeyToFPGA(cmd[c]);
                            delay(charDelay);
                        }
                        sendKeyToFPGA(13);  // RETURN
                        delay(lineDelay);
                        
                        // Yield per evitare watchdog timeout
                        yield();
                    }
                    
                    // Pausa prima di eseguire
                    delay(1000);
                    
                    // Esegui il programma
                    Serial.println("[WOZ] 0300R");
                    const char* runCmd = "0300R";
                    for (int c = 0; runCmd[c]; c++) {
                        sendKeyToFPGA(runCmd[c]);
                        delay(charDelay);
                    }
                    sendKeyToFPGA(13);
                    
                    Serial.println("\n[APPLE1 TEST] Done!");
                    Serial.println("[APPLE1 TEST] Screen should show:");
                    Serial.println("  TEST OUTPUT TO APPLE-1 DISPLAY.");
                    Serial.println("  !\"#$%&'()*+,-./0123456789:;<=>?@ABC...");
                    break;
                }
                
                // Se siamo su ZX Spectrum (Core 2), esegui il test grafico richiesto
                if (currentCore == 2) {
                    Serial.println("\n[ZX TEST] Sending Graphics/Attribute Test...");
                    
                    const char* zxGraphicTest[] = {
                        "10 CLS",
                        "20 REM FILL SCREEN WHITE ON BLACK",
                        "30 FOR A=22528 TO 23295",
                        "40 POKE A,7",
                        "50 NEXT A",
                        "60 REM DRAW COLORED BARS",
                        "70 FOR C=0 TO 7",
                        "80 FOR R=0 TO 1",
                        "90 LET AD=22528+(R*256)+(C*32)", // 32*8 = 256
                        "100 FOR X=0 TO 10",
                        "110 POKE AD+X,C*8+7",
                        "120 NEXT X",
                        "130 NEXT R",
                        "140 NEXT C",
                        "RUN"
                    };
                    
                    int numLines = sizeof(zxGraphicTest) / sizeof(zxGraphicTest[0]);
                    Serial.printf("[ZX TEST] Sending %d lines...\n", numLines);
                    
                    for (int line = 0; line < numLines; line++) {
                        const char* s = zxGraphicTest[line];
                        Serial.printf("[%3d] %s\n", line+1, s);
                        
                        for (int i = 0; s[i]; i++) {
                            char ch = s[i];
                            // Mappatura caratteri ZX se necessario (ma i numeri e lettere base sono ok)
                            if (ch >= 'a' && ch <= 'z') ch -= 32; // Uppercase
                            sendKeyToFPGA(ch);
                            delay(50); // Delay per ZX Spectrum
                        }
                        sendKeyToFPGA(13); // ENTER
                        delay(500); // Pausa tra le righe
                    }
                    Serial.println("[ZX TEST] Done.");
                    break;
                }

                // Altrimenti esegui il test CPU 6502 (C64/VIC20) esistente
                Serial.println("\n[CPU TEST] Sending comprehensive 6502 CPU test program...");
                Serial.println("[CPU TEST] This tests: arithmetic, logic, loops, arrays, functions\n");

                // Programma BASIC completo per testare la CPU 6502
                // Testa: aritmetica, logica, loop, array, funzioni BASIC
                const char* cpuTestLines[] = {
                    // Intestazione
                    "10 PRINT CHR$(147)",                          // Clear screen
                    "20 PRINT \"=== CPU 6502 TEST ===\"",
                    "30 PRINT",

                    // Test 1: Aritmetica base (ADC, SBC)
                    "100 PRINT \"TEST 1: ARITHMETIC\"",
                    "110 A=5+3:IF A=8 THEN PRINT \"ADD OK\":GOTO 130",
                    "120 PRINT \"ADD FAIL\":STOP",
                    "130 B=10-4:IF B=6 THEN PRINT \"SUB OK\":GOTO 150",
                    "140 PRINT \"SUB FAIL\":STOP",
                    "150 C=7*6:IF C=42 THEN PRINT \"MUL OK\":GOTO 170",
                    "160 PRINT \"MUL FAIL\":STOP",
                    "170 D=48/8:IF D=6 THEN PRINT \"DIV OK\":GOTO 190",
                    "180 PRINT \"DIV FAIL\":STOP",
                    "190 PRINT",

                    // Test 2: Confronti (CMP, branch) - versione semplice
                    "200 PRINT \"TEST 2: COMPARISONS\"",
                    "205 X=10:Y=20",
                    "206 PRINT \"X=\";X;\" Y=\";Y",
                    "210 Z=Y-X",
                    "211 PRINT \"Y-X=\";Z",
                    "215 IF Z>0 THEN PRINT \"Z>0 OK\":GOTO 220",
                    "216 PRINT \"Z>0 FAIL\":GOTO 220",
                    "220 IF X<Y THEN PRINT \"LESS OK\":GOTO 240",
                    "230 PRINT \"LESS FAIL\":STOP",
                    "240 IF Y>X THEN PRINT \"GREATER OK\":GOTO 260",
                    "250 PRINT \"GREATER FAIL\":STOP",
                    "260 IF X=10 THEN PRINT \"EQUAL OK\":GOTO 280",
                    "270 PRINT \"EQUAL FAIL\":STOP",
                    "280 PRINT",

                    // Test 3: Loop FOR-NEXT (INX, INY, branch)
                    "400 PRINT \"TEST 3: FOR-NEXT LOOP\"",
                    "410 S=0",
                    "420 FOR I=1 TO 10",
                    "430 S=S+I",
                    "440 NEXT I",
                    "450 IF S=55 THEN PRINT \"LOOP OK (SUM=\";S;\")\":GOTO 470",
                    "460 PRINT \"LOOP FAIL S=\";S:STOP",
                    "470 PRINT",

                    // Test 4: Logica (AND, ORA, EOR)
                    "500 PRINT \"TEST 4: LOGIC OPS\"",
                    "510 A=15 AND 7:IF A=7 THEN PRINT \"AND OK\":GOTO 530",
                    "520 PRINT \"AND FAIL\":STOP",
                    "530 B=8 OR 4:IF B=12 THEN PRINT \"OR OK\":GOTO 550",
                    "540 PRINT \"OR FAIL\":STOP",
                    "550 PRINT",

                    // Test 5: Array (indexed addressing)
                    "600 PRINT \"TEST 5: ARRAYS\"",
                    "610 DIM A(5)",
                    "620 FOR I=0 TO 4:A(I)=I*2:NEXT",
                    "630 T=A(0)+A(1)+A(2)+A(3)+A(4)",
                    "640 IF T=20 THEN PRINT \"ARRAY OK\":GOTO 660",
                    "650 PRINT \"ARRAY FAIL\":STOP",
                    "660 PRINT",

                    // Test 6: GOSUB/RETURN (JSR, RTS)
                    "700 PRINT \"TEST 6: GOSUB/RETURN\"",
                    "710 R=0:GOSUB 750",
                    "720 IF R=99 THEN PRINT \"GOSUB OK\":GOTO 770",
                    "730 PRINT \"GOSUB FAIL\":STOP",
                    "740 GOTO 770",
                    "750 R=99:RETURN",
                    "760 PRINT \"ERROR\":STOP",
                    "770 PRINT",

                    // Test 7: Stringhe (STA, LDA indirect)
                    "800 PRINT \"TEST 7: STRINGS\"",
                    "810 A$=\"HELLO\"",
                    "820 B$=\"WORLD\"",
                    "830 C$=A$+\" \"+B$",
                    "840 IF C$=\"HELLO WORLD\" THEN PRINT \"STR OK\":GOTO 860",
                    "850 PRINT \"STR FAIL\":STOP",
                    "860 PRINT",

                    // Test 8: Nested loops
                    "900 PRINT \"TEST 8: NESTED LOOPS\"",
                    "910 T=0",
                    "920 FOR I=1 TO 3",
                    "930 FOR J=1 TO 3",
                    "940 T=T+1",
                    "950 NEXT J",
                    "960 NEXT I",
                    "970 IF T=9 THEN PRINT \"NESTED OK\":GOTO 990",
                    "980 PRINT \"NESTED FAIL\":STOP",
                    "990 PRINT",

                    // Risultato finale
                    "1000 PRINT \"========================\"",
                    "1010 PRINT \"ALL TESTS PASSED!\"",
                    "1020 PRINT \"CPU 6502 WORKING OK\"",
                    "1030 PRINT \"========================\"",
                    "1040 END",

                    // Esegui
                    "RUN"
                };

                int numLines = sizeof(cpuTestLines) / sizeof(cpuTestLines[0]);
                Serial.printf("[CPU TEST] Sending %d lines...\n", numLines);

                for (int line = 0; line < numLines; line++) {
                    const char* s = cpuTestLines[line];
                    Serial.printf("[%3d] %s\n", line+1, s);

                    for (int i = 0; s[i]; i++) {
                        char ch = s[i];
                        // Converti in maiuscolo per Commodore
                        if (currentCore >= 1 && currentCore <= 4) {
                            if (ch >= 'a' && ch <= 'z') ch -= 32;
                        }
                        sendKeyToFPGA(ch);
                        delay(25);  // Velocità ottimizzata
                    }
                    // Invia RETURN
                    sendKeyToFPGA(13);
                    delay(150);  // Pausa tra le righe

                    // Progress ogni 10 righe
                    if ((line + 1) % 10 == 0) {
                        Serial.printf("[PROGRESS] %d/%d lines sent\n", line+1, numLines);
                    }
                }
                Serial.println("\n[CPU TEST] Program sent! Watch the C64 screen for results.");
                Serial.println("[CPU TEST] If all tests pass, CPU 6502 is working correctly!\n");
            }
            break;
            
        case 'z': case 'Z':
            {
                // Test Z80 per ZX Spectrum
                if (currentCore != 2) {
                    Serial.println("[ERROR] Z80 test only for ZX Spectrum (core 2)");
                    Serial.println("[INFO] Select ZX Spectrum first with '2' command");
                    break;
                }
                
                Serial.println("\n[Z80 TEST] Sending comprehensive Z80 CPU test program...");
                Serial.println("[Z80 TEST] This tests: arithmetic, logic, loops, arrays\n");
                
                // Programma BASIC per ZX Spectrum
                // NOTA: In ZX BASIC, AND/OR sono logici, non bitwise!
                const char* z80TestLines[] = {
                    // Intestazione
                    "10 CLS",
                    "20 PRINT \"Z80 CPU TEST\"",
                    "30 PRINT",
                    
                    // Test 1: Aritmetica
                    "100 PRINT \"TEST 1 MATH\"",
                    "110 LET A=5+3",
                    "120 IF A=8 THEN PRINT \"ADD OK\"",
                    "130 LET A=10-4",
                    "140 IF A=6 THEN PRINT \"SUB OK\"",
                    "150 LET A=7*6",
                    "160 IF A=42 THEN PRINT \"MUL OK\"",
                    "170 LET A=INT(20/4)",
                    "180 IF A=5 THEN PRINT \"DIV OK\"",
                    "190 PRINT",
                    
                    // Test 2: Logica (ZX BASIC style)
                    "200 PRINT \"TEST 2 LOGIC\"",
                    "210 LET A=1 AND 1",
                    "220 IF A=1 THEN PRINT \"AND OK\"",
                    "230 LET A=0 OR 1",
                    "240 IF A=1 THEN PRINT \"OR OK\"",
                    "250 LET A=NOT 0",
                    "260 IF A=1 THEN PRINT \"NOT OK\"",
                    "270 PRINT",
                    
                    // Test 3: Loop
                    "300 PRINT \"TEST 3 LOOP\"",
                    "310 LET T=0",
                    "320 FOR I=1 TO 5",
                    "330 LET T=T+I",
                    "340 NEXT I",
                    "350 IF T=15 THEN PRINT \"LOOP OK\"",
                    "360 PRINT",
                    
                    // Risultato finale
                    "400 PRINT \"ALL DONE\"",
                    "410 STOP",
                    
                    // Esegui
                    "RUN"
                };
                
                int numLines = sizeof(z80TestLines) / sizeof(z80TestLines[0]);
                Serial.printf("[Z80 TEST] Sending %d lines...\n", numLines);
                
                for (int line = 0; line < numLines; line++) {
                    const char* s = z80TestLines[line];
                    Serial.printf("[%3d] %s\n", line+1, s);
                    
                    for (int i = 0; s[i]; i++) {
                        char ch = s[i];
                        // Converti in maiuscolo
                        if (ch >= 'a' && ch <= 'z') ch -= 32;
                        sendKeyToFPGA(ch);
                        delay(100);  // Timing per ZX Spectrum
                    }
                    // Invia ENTER
                    sendKeyToFPGA(13);
                    delay(1000);  // Pausa tra le righe
                    
                    // Progress ogni 10 righe
                    if ((line + 1) % 10 == 0) {
                        Serial.printf("[PROGRESS] %d/%d lines sent\n", line+1, numLines);
                    }
                }
                Serial.println("\n[Z80 TEST] Program sent! Watch the ZX Spectrum screen for results.");
                Serial.println("[Z80 TEST] If all tests pass, Z80 CPU is working correctly!\n");
            }
            break;
        
        case 'h': case 'H':
            Serial.println("\n=== COMMANDS ===");
            Serial.println("--- System Selection ---");
            Serial.println("0   : Test Pattern");
            Serial.println("1   : C64 (Commodore 64)");
            Serial.println("2   : ZX Spectrum 48K");
            Serial.println("3   : VIC-20");
            Serial.println("4   : Apple I");
            Serial.println("\n--- General ---");
            Serial.println("p   : PING FPGA");
            Serial.println("s   : STATUS");
            Serial.println("r   : RESET");
            Serial.println("k   : Keyboard mode (~ to exit)");
            Serial.println("\n--- PRG Programs ---");
            Serial.println("g   : List programs");
            Serial.println("l   : Load program by number");
            Serial.println("\n--- D64 Disk Images (C64 only) ---");
            Serial.println("m   : List & mount D64 disk");
            Serial.println("f   : Show D64 directory (after mount)");
            Serial.println("e   : Load file from D64");
            Serial.println("u   : Unmount D64 disk");
            Serial.println("\n--- Tests ---");
            Serial.println("t   : Simple BASIC test (Hello World)");
            Serial.println("c   : CPU 6502 comprehensive test (C64/VIC-20)");
            Serial.println("z   : CPU Z80 comprehensive test (ZX Spectrum)");
            Serial.println("h   : This help");
            Serial.println("\n--- SD Card Paths ---");
            Serial.println("/roms/c64/         : C64 ROMs");
            Serial.println("/roms/c64/programs : C64 PRG files");
            Serial.println("/roms/spectrum/    : ZX Spectrum ROMs");
            Serial.println("/roms/vic20/       : VIC-20 ROMs");
            Serial.println("/roms/apple1/      : Apple I programs");
            Serial.println("/floppy/           : D64 disk images");
            break;
            
        default:
            Serial.println("[?] Unknown. 'h' for help.");
    }
}

//==============================================================================
// WEB PAGE
//==============================================================================
const char index_html[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Multi-Core Retro Computer System</title>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Press+Start+2P&family=Roboto:wght@300;400;700&display=swap');
        *{box-sizing:border-box;margin:0;padding:0}
        body{font-family:'Roboto',sans-serif;background:linear-gradient(135deg,#0d0d1a,#1a1a2e,#16213e);color:#eee;padding:20px;min-height:100vh}
        body::before{content:"";position:fixed;top:0;left:0;width:100%;height:100%;background:repeating-linear-gradient(0deg,rgba(0,0,0,0.1),rgba(0,0,0,0.1) 1px,transparent 1px,transparent 2px);pointer-events:none;z-index:1000;opacity:0.3}
        .header{text-align:center;margin-bottom:25px}
        .header h1{font-family:'Press Start 2P',monospace;color:#00ff88;font-size:1.4em;text-shadow:0 0 10px #00ff88,0 0 20px #00ff8855;letter-spacing:2px;animation:glow 2s ease-in-out infinite alternate}
        @keyframes glow{from{text-shadow:0 0 10px #00ff88,0 0 20px #00ff8855}to{text-shadow:0 0 15px #00ff88,0 0 30px #00ff88,0 0 40px #00ff8833}}
        .header .subtitle{color:#8892b0;font-size:0.85em;margin-top:10px;font-weight:300}
        .header .author{color:#5a6a8a;font-size:0.75em;margin-top:5px}
        .status{display:flex;justify-content:center;gap:15px;margin-bottom:25px;flex-wrap:wrap}
        .status-item{padding:10px 18px;border-radius:25px;background:linear-gradient(145deg,#1e1e35,#252545);border:1px solid #333355;display:flex;align-items:center;gap:8px;font-size:0.85em;box-shadow:0 4px 15px rgba(0,0,0,0.3)}
        .status-icon{width:18px;height:18px}
        .status-ok{color:#00ff88;font-weight:700}
        .status-err{color:#ff4466;font-weight:700}
        .status-label{color:#8892b0}
        .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(155px,1fr));gap:18px;max-width:900px;margin:0 auto}
        .card{background:linear-gradient(145deg,#1e1e35,#252548);border-radius:16px;padding:20px 15px;text-align:center;cursor:pointer;transition:all 0.3s;border:2px solid transparent;position:relative;overflow:hidden}
        .card::before{content:"";position:absolute;top:0;left:0;right:0;height:3px;background:linear-gradient(90deg,var(--card-color,#666),transparent);opacity:0;transition:opacity 0.3s}
        .card:hover{transform:translateY(-5px) scale(1.02);background:linear-gradient(145deg,#252548,#303060);box-shadow:0 15px 40px rgba(0,0,0,0.4),0 0 20px var(--card-glow,transparent)}
        .card:hover::before{opacity:1}
        .card.active{border:2px solid #00ff88;box-shadow:0 0 25px rgba(0,255,136,0.3)}
        .card-icon{width:80px;height:80px;margin:0 auto 12px;border-radius:12px;overflow:hidden}
        .card h3{font-family:'Press Start 2P',monospace;font-size:0.65em;margin-bottom:8px;color:#fff}
        .card .year{color:#6a7a9a;font-size:0.8em}
        .card .cpu{color:#66aaff;font-size:0.7em;margin-top:6px;font-weight:300}
        .card .roms{color:#00ff88;font-size:0.75em;margin-top:8px;font-weight:500}
        .card .progs{color:#ffcc00;font-size:0.75em;margin-top:4px;font-weight:500}
        .card[data-system="test"]{--card-color:#888;--card-glow:rgba(136,136,136,0.2)}
        .card[data-system="c64"]{--card-color:#3a5a8a;--card-glow:rgba(58,90,138,0.3)}
        .card[data-system="spectrum"]{--card-color:#1a3a5a;--card-glow:rgba(26,58,90,0.3)}
        .card[data-system="vic20"]{--card-color:#2a7a6a;--card-glow:rgba(42,122,106,0.3)}
        .card[data-system="apple1"]{--card-color:#4a4a3a;--card-glow:rgba(74,74,58,0.3)}
        .actions{text-align:center;margin-top:25px;display:flex;justify-content:center;gap:12px;flex-wrap:wrap}
        .btn{background:linear-gradient(145deg,#00dd77,#00ff88);color:#000;border:none;padding:14px 28px;border-radius:12px;font-size:0.95em;font-weight:700;cursor:pointer;transition:all 0.2s;display:inline-flex;align-items:center;gap:8px;box-shadow:0 4px 15px rgba(0,255,136,0.3)}
        .btn:hover:not(:disabled){transform:translateY(-2px);box-shadow:0 6px 25px rgba(0,255,136,0.4)}
        .btn:disabled{background:linear-gradient(145deg,#3a3a50,#454560);color:#666;cursor:not-allowed;box-shadow:none}
        .btn-reset{background:linear-gradient(145deg,#dd4455,#ff5566);color:#fff;box-shadow:0 4px 15px rgba(255,68,102,0.3)}
        .btn-bt{background:linear-gradient(145deg,#0055dd,#0077ff);color:#fff;box-shadow:0 4px 15px rgba(0,119,255,0.3)}
        .btn-icon{width:20px;height:20px}
        .progress{display:none;margin:25px auto;width:85%;max-width:500px;height:12px;background:#1e1e35;border-radius:10px;overflow:hidden;border:1px solid #333355}
        .progress-bar{height:100%;background:linear-gradient(90deg,#00dd77,#00ff88,#00ffaa);width:0%;transition:width 0.3s;box-shadow:0 0 10px #00ff88}
        .keyboard{margin-top:25px;text-align:center;max-width:600px;margin-left:auto;margin-right:auto}
        .keyboard-container{display:flex;gap:10px;align-items:center}
        .keyboard input{flex:1;padding:14px 18px;font-size:1em;background:linear-gradient(145deg,#1a1a30,#202040);border:2px solid #333355;color:#fff;border-radius:12px;transition:all 0.2s}
        .keyboard input:focus{outline:none;border-color:#00ff88;box-shadow:0 0 15px rgba(0,255,136,0.2)}
        .keyboard input::placeholder{color:#5a6a8a}
        .footer{text-align:center;margin-top:35px;padding-top:20px;border-top:1px solid #252545}
        .footer p{color:#4a5a7a;font-size:0.7em;margin:4px 0}
        .footer .tech{color:#5a6a8a;font-family:'Press Start 2P',monospace;font-size:0.55em;margin-top:8px}
        .bas-section{margin:20px auto;text-align:center;padding:18px;background:linear-gradient(145deg,#1a1a30,#252040);border-radius:14px;max-width:500px;border:1px solid #333355}
        .bas-section h4{color:#bb77ff;margin-bottom:12px;font-size:0.9em;font-family:'Press Start 2P',monospace}
        .bas-section select{padding:12px 18px;background:linear-gradient(145deg,#252545,#303060);border:2px solid #444;color:#fff;border-radius:10px;min-width:200px;margin-right:12px;font-size:0.9em;cursor:pointer}
        .bas-section select:focus{outline:none;border-color:#bb77ff}
        .type-section{margin:20px auto;text-align:center;padding:18px;background:linear-gradient(145deg,#1a2a1a,#203020);border-radius:14px;max-width:600px;border:1px solid #335533}
        .type-section h4{color:#66ff66;margin-bottom:12px;font-size:0.9em;font-family:'Press Start 2P',monospace}
        .type-section textarea{width:90%;height:200px;padding:12px;background:#1a1a1a;border:2px solid #444;color:#0f0;border-radius:10px;font-family:'Courier New',monospace;font-size:12px;resize:vertical}
        .type-section textarea:focus{outline:none;border-color:#66ff66}
        .type-section .info{color:#888;font-size:0.75em;margin-top:8px}
        .btn-type{background:linear-gradient(145deg,#338833,#44aa44)!important;color:#fff!important;margin-top:12px}
        .btn-type:hover{background:linear-gradient(145deg,#44aa44,#55bb55)!important;box-shadow:0 5px 20px rgba(68,170,68,0.4)}
        .type-progress{color:#66ff66;font-size:0.8em;margin-top:10px;display:none}
        .btn-bas{background:linear-gradient(145deg,#9955dd,#bb77ff)!important;color:#fff!important}
        .btn-bas:hover{background:linear-gradient(145deg,#aa66ee,#cc88ff)!important;box-shadow:0 5px 20px rgba(187,119,255,0.4)}
        @media(max-width:600px){.header h1{font-size:1em}.grid{grid-template-columns:repeat(2,1fr);gap:12px}.card{padding:15px 10px}.card-icon{width:64px;height:64px}.btn{padding:12px 20px;font-size:0.85em}.bas-section select{min-width:140px;margin-bottom:10px}}
    </style>
</head>
<body>
    <div class="header">
        <h1>MULTI-CORE RETRO COMPUTER SYSTEM</h1>
        <p class="subtitle">FPGA-based Vintage Computer Emulation</p>
        <p class="author">Tesi di Laurea - Angelo Arato - Univ. Mercatorum</p>
    </div>
    <div class="status">
        <div class="status-item"><svg class="status-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8M12 17v4"/></svg><span class="status-label">FPGA:</span><span id="fpgaStatus">--</span></div>
        <div class="status-item"><svg class="status-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="5" width="20" height="14" rx="2"/><path d="M12 9v6M9 12h6"/></svg><span class="status-label">SD:</span><span id="sdStatus">--</span></div>
        <div class="status-item"><svg class="status-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M9 9h6v6H9z"/></svg><span class="status-label">Core:</span><span id="coreStatus">--</span></div>
    </div>
    <div class="grid" id="systemGrid"></div>
    <div class="actions">
        <button class="btn" id="loadBtn" disabled onclick="loadSystem()"><svg class="btn-icon" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>LOAD</button>
        <button class="btn btn-reset" onclick="resetSystem()"><svg class="btn-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M1 4v6h6"/><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/></svg>RESET</button>
    </div>
    <div class="bas-section" id="basSection" style="display:none">
        <h4>BASIC Programs (.BAS)</h4>
        <select id="basSelect"><option value="">-- Select BAS file --</option></select>
        <button class="btn btn-bas" onclick="loadBAS()"><svg class="btn-icon" viewBox="0 0 24 24" fill="currentColor"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M12 18v-6M9 15l3 3 3-3"/></svg>LOAD BAS</button>
    </div>
    <div class="type-section" id="typeSection" style="display:none">
        <h4>TYPE BASIC PROGRAM</h4>
        <textarea id="basCode" placeholder="Paste your BASIC program here...
Example:
10 PRINT &quot;HELLO WORLD&quot;
20 GOTO 10"></textarea>
        <div class="info">Paste BASIC code and click TYPE to send it line by line</div>
        <button class="btn btn-type" id="typeBtn" onclick="typeBAS()"><svg class="btn-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 19V5M5 12l7-7 7 7"/></svg>TYPE PROGRAM</button>
        <div class="type-progress" id="typeProgress">Sending line 0 of 0...</div>
    </div>
    <div class="progress" id="progress"><div class="progress-bar" id="progressBar"></div></div>
    <div class="keyboard"><div class="keyboard-container"><input type="text" id="keyInput" placeholder="Type to send to emulator..."><button class="btn" onclick="sendKeys()"><svg class="btn-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z"/></svg>SEND</button></div></div>
    <script>
        const systemIcons={
            test:`<svg viewBox="0 0 80 80"><rect width="80" height="80" fill="#1a1a1a" rx="8"/><rect x="10" y="15" width="8" height="40" fill="#fff"/><rect x="18" y="15" width="8" height="40" fill="#ff0"/><rect x="26" y="15" width="8" height="40" fill="#0ff"/><rect x="34" y="15" width="8" height="40" fill="#0f0"/><rect x="42" y="15" width="8" height="40" fill="#f0f"/><rect x="50" y="15" width="8" height="40" fill="#f00"/><rect x="58" y="15" width="8" height="40" fill="#00f"/><text x="40" y="68" text-anchor="middle" fill="#fff" font-size="7" font-weight="bold">Test Pattern</text></svg>`,
            c64:`<svg viewBox="0 0 80 80"><rect width="80" height="80" fill="#3a5a8a" rx="8"/><rect x="8" y="18" width="64" height="38" rx="3" fill="#d4c8b0"/><rect x="10" y="20" width="60" height="34" rx="2" fill="#c8bca4"/><rect x="14" y="23" width="52" height="14" rx="1" fill="#8b7355"/><rect x="16" y="25" width="48" height="10" fill="#6b5344"/><rect x="56" y="26" width="6" height="6" rx="1" fill="#4a3a2a"/><circle cx="66" cy="29" r="2" fill="#c44"/><g fill="#2a2a2a"><rect x="14" y="40" width="4" height="3" rx=".5"/><rect x="19" y="40" width="4" height="3" rx=".5"/><rect x="24" y="40" width="4" height="3" rx=".5"/><rect x="29" y="40" width="4" height="3" rx=".5"/><rect x="34" y="40" width="4" height="3" rx=".5"/><rect x="39" y="40" width="4" height="3" rx=".5"/><rect x="44" y="40" width="4" height="3" rx=".5"/><rect x="49" y="40" width="4" height="3" rx=".5"/><rect x="54" y="40" width="4" height="3" rx=".5"/><rect x="59" y="40" width="4" height="3" rx=".5"/><rect x="16" y="44" width="4" height="3" rx=".5"/><rect x="21" y="44" width="4" height="3" rx=".5"/><rect x="26" y="44" width="4" height="3" rx=".5"/><rect x="31" y="44" width="4" height="3" rx=".5"/><rect x="36" y="44" width="4" height="3" rx=".5"/><rect x="41" y="44" width="4" height="3" rx=".5"/><rect x="46" y="44" width="4" height="3" rx=".5"/><rect x="51" y="44" width="4" height="3" rx=".5"/><rect x="56" y="44" width="6" height="3" rx=".5"/><rect x="18" y="48" width="4" height="3" rx=".5"/><rect x="23" y="48" width="4" height="3" rx=".5"/><rect x="28" y="48" width="18" height="3" rx=".5"/><rect x="47" y="48" width="4" height="3" rx=".5"/><rect x="52" y="48" width="4" height="3" rx=".5"/></g><text x="40" y="68" text-anchor="middle" fill="#fff" font-size="7" font-weight="bold">Commodore 64</text></svg>`,
            spectrum:`<svg viewBox="0 0 80 80"><rect width="80" height="80" fill="#1a3a5a" rx="8"/><rect x="8" y="20" width="64" height="36" rx="2" fill="#1a1a1a"/><rect x="10" y="22" width="60" height="32" rx="1" fill="#2a2a2a"/><rect x="12" y="24" width="40" height="12" fill="#111"/><rect x="54" y="24" width="2" height="12" fill="#f00"/><rect x="56" y="24" width="2" height="12" fill="#f80"/><rect x="58" y="24" width="2" height="12" fill="#ff0"/><rect x="60" y="24" width="2" height="12" fill="#0f0"/><rect x="62" y="24" width="2" height="12" fill="#0ff"/><rect x="64" y="24" width="2" height="12" fill="#00f"/><g fill="#3a3a3a"><rect x="12" y="40" width="5" height="4" rx="1"/><rect x="18" y="40" width="5" height="4" rx="1"/><rect x="24" y="40" width="5" height="4" rx="1"/><rect x="30" y="40" width="5" height="4" rx="1"/><rect x="36" y="40" width="5" height="4" rx="1"/><rect x="42" y="40" width="5" height="4" rx="1"/><rect x="48" y="40" width="5" height="4" rx="1"/><rect x="54" y="40" width="5" height="4" rx="1"/><rect x="60" y="40" width="5" height="4" rx="1"/><rect x="14" y="46" width="5" height="4" rx="1"/><rect x="20" y="46" width="5" height="4" rx="1"/><rect x="26" y="46" width="5" height="4" rx="1"/><rect x="32" y="46" width="5" height="4" rx="1"/><rect x="38" y="46" width="5" height="4" rx="1"/><rect x="44" y="46" width="5" height="4" rx="1"/><rect x="50" y="46" width="5" height="4" rx="1"/><rect x="56" y="46" width="8" height="4" rx="1"/></g><text x="40" y="68" text-anchor="middle" fill="#fff" font-size="7" font-weight="bold">ZX Spectrum</text></svg>`,
            vic20:`<svg viewBox="0 0 80 80"><rect width="80" height="80" fill="#2a7a6a" rx="8"/><rect x="8" y="20" width="64" height="36" rx="3" fill="#e8dcc8"/><rect x="10" y="22" width="60" height="32" rx="2" fill="#d8ccb8"/><rect x="14" y="25" width="44" height="10" rx="1" fill="#3a3a3a"/><rect x="60" y="26" width="6" height="6" rx="1" fill="#888"/><rect x="61" y="27" width="4" height="4" fill="#666"/><circle cx="66" cy="30" r="1.5" fill="#0c0"/><g fill="#4a4a4a"><rect x="14" y="38" width="4" height="3" rx=".5"/><rect x="19" y="38" width="4" height="3" rx=".5"/><rect x="24" y="38" width="4" height="3" rx=".5"/><rect x="29" y="38" width="4" height="3" rx=".5"/><rect x="34" y="38" width="4" height="3" rx=".5"/><rect x="39" y="38" width="4" height="3" rx=".5"/><rect x="44" y="38" width="4" height="3" rx=".5"/><rect x="49" y="38" width="4" height="3" rx=".5"/><rect x="54" y="38" width="4" height="3" rx=".5"/><rect x="16" y="42" width="4" height="3" rx=".5"/><rect x="21" y="42" width="4" height="3" rx=".5"/><rect x="26" y="42" width="4" height="3" rx=".5"/><rect x="31" y="42" width="4" height="3" rx=".5"/><rect x="36" y="42" width="4" height="3" rx=".5"/><rect x="41" y="42" width="4" height="3" rx=".5"/><rect x="46" y="42" width="4" height="3" rx=".5"/><rect x="51" y="42" width="6" height="3" rx=".5"/><rect x="18" y="46" width="4" height="3" rx=".5"/><rect x="23" y="46" width="4" height="3" rx=".5"/><rect x="28" y="46" width="16" height="3" rx=".5"/><rect x="45" y="46" width="4" height="3" rx=".5"/><rect x="50" y="46" width="4" height="3" rx=".5"/></g><text x="40" y="68" text-anchor="middle" fill="#fff" font-size="8" font-weight="bold">VIC-20</text></svg>`,
            apple1:`<svg viewBox="0 0 80 80"><rect width="80" height="80" fill="#3a3a32" rx="8"/><rect x="8" y="15" width="50" height="35" rx="2" fill="#4a6a3a"/><rect x="10" y="17" width="46" height="31" fill="#5a7a4a"/><rect x="12" y="19" width="8" height="4" fill="#1a1a1a"/><rect x="22" y="19" width="8" height="4" fill="#1a1a1a"/><rect x="32" y="19" width="8" height="4" fill="#1a1a1a"/><rect x="42" y="19" width="8" height="4" fill="#1a1a1a"/><rect x="12" y="25" width="8" height="4" fill="#1a1a1a"/><rect x="22" y="25" width="8" height="4" fill="#1a1a1a"/><rect x="32" y="25" width="12" height="6" fill="#2a2a2a"/><rect x="12" y="33" width="38" height="3" fill="#8a8a6a"/><rect x="8" y="52" width="40" height="12" rx="1" fill="#c8c0b0"/><g fill="#3a3a3a"><rect x="10" y="54" width="3" height="2.5" rx=".3"/><rect x="14" y="54" width="3" height="2.5" rx=".3"/><rect x="18" y="54" width="3" height="2.5" rx=".3"/><rect x="22" y="54" width="3" height="2.5" rx=".3"/><rect x="26" y="54" width="3" height="2.5" rx=".3"/><rect x="30" y="54" width="3" height="2.5" rx=".3"/><rect x="34" y="54" width="3" height="2.5" rx=".3"/><rect x="38" y="54" width="3" height="2.5" rx=".3"/><rect x="42" y="54" width="3" height="2.5" rx=".3"/><rect x="11" y="58" width="3" height="2.5" rx=".3"/><rect x="15" y="58" width="3" height="2.5" rx=".3"/><rect x="19" y="58" width="3" height="2.5" rx=".3"/><rect x="23" y="58" width="12" height="2.5" rx=".3"/><rect x="36" y="58" width="3" height="2.5" rx=".3"/><rect x="40" y="58" width="3" height="2.5" rx=".3"/></g><rect x="60" y="18" width="14" height="22" rx="2" fill="#2a2a2a"/><rect x="62" y="20" width="10" height="8" fill="#1a1a1a"/><path d="M58 30Q55 35 52 35" stroke="#222" stroke-width="2" fill="none"/><path d="M60 38Q55 45 50 52" stroke="#222" stroke-width="1.5" fill="none"/><text x="40" y="74" text-anchor="middle" fill="#fff" font-size="8" font-weight="bold">Apple I</text></svg>`
        };
        let selectedSystem=null;
        async function loadStatus(){try{const r=await fetch('/api/status');const d=await r.json();document.getElementById('fpgaStatus').textContent=d.fpgaReady?'OK':'OFFLINE';document.getElementById('fpgaStatus').className=d.fpgaReady?'status-ok':'status-err';document.getElementById('sdStatus').textContent=d.sdReady?'OK':'ERROR';document.getElementById('sdStatus').className=d.sdReady?'status-ok':'status-err';document.getElementById('coreStatus').textContent=d.core||'None';document.getElementById('coreStatus').className='status-ok';}catch(e){console.error(e);}}
        async function loadSystems(){try{const r=await fetch('/api/systems');const d=await r.json();const cpu={'test':'Diagnostics','c64':'MOS 6502 @ 1MHz','spectrum':'Zilog Z80 @ 3.5MHz','vic20':'MOS 6502 @ 1MHz','apple1':'MOS 6502 @ 1MHz'};const g=document.getElementById('systemGrid');g.innerHTML='';d.systems.forEach(s=>{const c=document.createElement('div');c.className='card';c.setAttribute('data-system',s.id);c.onclick=()=>selectSystem(s.id,c);c.innerHTML=`<div class="card-icon">${systemIcons[s.id]||systemIcons.test}</div><h3>${s.name}</h3><div class="year">${s.year>0?s.year:''}</div><div class="cpu">${cpu[s.id]||''}</div>${s.romCount>0?'<div class="roms">'+s.romCount+' ROM</div>':''}${s.progCount>0?'<div class="progs">'+s.progCount+' games</div>':''}`;g.appendChild(c);});}catch(e){console.error(e);}}
        function selectSystem(id,card){document.querySelectorAll('.card').forEach(c=>c.classList.remove('active'));card.classList.add('active');selectedSystem=id;document.getElementById('loadBtn').disabled=false;}
        async function loadSystem(){if(!selectedSystem)return;const p=document.getElementById('progress');const b=document.getElementById('progressBar');const btn=document.getElementById('loadBtn');p.style.display='block';b.style.width='10%';btn.disabled=true;btn.innerHTML='Loading...';try{await fetch('/api/load',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({system:selectedSystem})});b.style.width='30%';let attempts=0;const maxAttempts=60;const poll=async()=>{const r=await fetch('/api/status');const d=await r.json();b.style.width=(30+attempts)+'%';if(d.loadComplete){b.style.width='100%';if(d.loadSuccess){loadBASFiles();loadStatus();}else{alert('Load failed!');}setTimeout(()=>{p.style.display='none';b.style.width='0%';btn.disabled=false;btn.innerHTML='<svg class=\"btn-icon\" viewBox=\"0 0 24 24\" fill=\"currentColor\"><path d=\"M8 5v14l11-7z\"/></svg>LOAD';},500);return;}attempts++;if(attempts<maxAttempts){setTimeout(poll,500);}else{alert('Timeout!');p.style.display='none';btn.disabled=false;btn.innerHTML='<svg class=\"btn-icon\" viewBox=\"0 0 24 24\" fill=\"currentColor\"><path d=\"M8 5v14l11-7z\"/></svg>LOAD';}};setTimeout(poll,500);}catch(e){alert('Error: '+e);p.style.display='none';btn.disabled=false;btn.innerHTML='<svg class=\"btn-icon\" viewBox=\"0 0 24 24\" fill=\"currentColor\"><path d=\"M8 5v14l11-7z\"/></svg>LOAD';}}
        async function resetSystem(){if(!confirm('Reset the system?'))return;await fetch('/api/reset',{method:'POST'});selectedSystem=null;document.querySelectorAll('.card').forEach(c=>c.classList.remove('active'));document.getElementById('loadBtn').disabled=true;document.getElementById('basSection').style.display='none';document.getElementById('typeSection').style.display='none';loadStatus();}
        async function loadBASFiles(){try{const r=await fetch('/api/basfiles');const d=await r.json();const sel=document.getElementById('basSelect');const sec=document.getElementById('basSection');const typeSec=document.getElementById('typeSection');sel.innerHTML='<option value="">-- Select BAS file --</option>';if(d.files&&d.files.length>0){d.files.forEach((f,i)=>{sel.innerHTML+=`<option value="${i}">${f}</option>`;});sec.style.display='block';}else{sec.style.display='none';}typeSec.style.display='block';}catch(e){document.getElementById('basSection').style.display='none';document.getElementById('typeSection').style.display='none';}}
        async function typeBAS(){const code=document.getElementById('basCode').value;if(!code.trim())return;const btn=document.getElementById('typeBtn');const prog=document.getElementById('typeProgress');const lines=code.split('\\n').filter(l=>l.trim());btn.disabled=true;prog.style.display='block';prog.textContent='Starting...';try{const r=await fetch('/api/typebas',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code:code})});if(r.ok){let attempts=0;const maxAttempts=lines.length*3+60;const poll=async()=>{const s=await fetch('/api/typestatus');const d=await s.json();prog.textContent=d.status;if(d.complete){prog.textContent=d.success?'Done! Program typed.':'Error!';setTimeout(()=>{btn.disabled=false;prog.style.display='none';},2000);return;}attempts++;if(attempts<maxAttempts){setTimeout(poll,500);}else{prog.textContent='Timeout';btn.disabled=false;}};setTimeout(poll,300);}else{prog.textContent='Error sending';btn.disabled=false;}}catch(e){prog.textContent='Error: '+e;btn.disabled=false;}}
        async function loadBAS(){const sel=document.getElementById('basSelect');const idx=sel.value;if(idx==='')return;const btn=document.querySelector('.btn-bas');btn.disabled=true;btn.innerHTML='Sending...';try{await fetch('/api/loadbas',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({index:parseInt(idx)})});let attempts=0;const maxAttempts=120;const poll=async()=>{const r=await fetch('/api/basstatus');const d=await r.json();if(d.complete){if(d.success){btn.innerHTML='Done!';}else{alert('BAS load failed!');}setTimeout(()=>{btn.disabled=false;btn.innerHTML='<svg class="btn-icon" viewBox="0 0 24 24" fill="currentColor"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M12 18v-6M9 15l3 3 3-3"/></svg>LOAD BAS';},1500);return;}attempts++;btn.innerHTML='Sending.'+(attempts%3==0?'..':attempts%3==1?'.':'');if(attempts<maxAttempts){setTimeout(poll,500);}else{alert('Timeout!');btn.disabled=false;btn.innerHTML='<svg class="btn-icon" viewBox="0 0 24 24" fill="currentColor"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M12 18v-6M9 15l3 3 3-3"/></svg>LOAD BAS';}};setTimeout(poll,300);}catch(e){alert('Error: '+e);btn.disabled=false;btn.innerHTML='<svg class="btn-icon" viewBox="0 0 24 24" fill="currentColor"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M12 18v-6M9 15l3 3 3-3"/></svg>LOAD BAS';}}
        async function sendKeys(){const i=document.getElementById('keyInput');const t=i.value;if(!t)return;await fetch('/api/keyboard',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text:t})});i.value='';}
        document.getElementById('keyInput').addEventListener('keypress',function(e){if(e.key==='Enter')sendKeys();});
        loadStatus();loadSystems();setInterval(loadStatus,5000);
    </script>
    <div class="footer"><p>Multi-Core Retro Computer System - Tesi di Laurea in Ing. Gestionale</p><p>Angelo Arato - Universita Telematica Mercatorum - 2024</p><p class="tech">Intel MAX 10 FPGA (DE10-Lite) + ESP32 Controller</p></div>
</body>
</html>
)rawliteral";

//==============================================================================
// WIFI CONFIGURATION PAGE
//==============================================================================

const char wifi_config_html[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="it">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WiFi Setup - RetroPC</title>
    <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:'Segoe UI',Arial,sans-serif;background:linear-gradient(135deg,#1a1a2e 0%,#16213e 100%);min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}
        .container{background:#0f0f23;border-radius:20px;padding:40px;max-width:400px;width:100%;box-shadow:0 20px 60px rgba(0,0,0,0.5);border:1px solid #333}
        h1{color:#00ff88;text-align:center;margin-bottom:10px;font-size:28px}
        .subtitle{color:#888;text-align:center;margin-bottom:30px;font-size:14px}
        .form-group{margin-bottom:20px}
        label{display:block;color:#aaa;margin-bottom:8px;font-size:14px}
        input[type="text"],input[type="password"]{width:100%;padding:15px;border:2px solid #333;border-radius:10px;background:#1a1a2e;color:#fff;font-size:16px;transition:border-color 0.3s}
        input:focus{outline:none;border-color:#00ff88}
        .btn{width:100%;padding:15px;border:none;border-radius:10px;font-size:16px;font-weight:bold;cursor:pointer;transition:all 0.3s;margin-top:10px}
        .btn-primary{background:linear-gradient(135deg,#00ff88,#00cc6a);color:#000}
        .btn-primary:hover{transform:translateY(-2px);box-shadow:0 5px 20px rgba(0,255,136,0.4)}
        .btn-secondary{background:#333;color:#fff}
        .btn-secondary:hover{background:#444}
        .btn-danger{background:#ff4444;color:#fff;margin-top:30px}
        .btn-danger:hover{background:#ff6666}
        .info{background:#1a1a2e;border-left:4px solid #00ff88;padding:15px;margin:20px 0;border-radius:0 10px 10px 0}
        .info p{color:#aaa;font-size:13px;line-height:1.6}
        .status{text-align:center;padding:15px;border-radius:10px;margin-top:20px}
        .status.success{background:rgba(0,255,136,0.2);color:#00ff88}
        .status.error{background:rgba(255,68,68,0.2);color:#ff4444}
        .current{background:#1a1a2e;padding:15px;border-radius:10px;margin-bottom:20px}
        .current p{color:#888;font-size:13px}
        .current strong{color:#00ff88}
        .divider{border-top:1px solid #333;margin:30px 0}
        .networks{max-height:200px;overflow-y:auto;margin-bottom:20px}
        .network{padding:12px;background:#1a1a2e;margin:5px 0;border-radius:8px;cursor:pointer;display:flex;justify-content:space-between;align-items:center;transition:background 0.2s}
        .network:hover{background:#252545}
        .network.selected{border:2px solid #00ff88}
        .signal{color:#00ff88;font-size:12px}
    </style>
</head>
<body>
    <div class="container">
        <h1>🔧 WiFi Setup</h1>
        <p class="subtitle">Multi-Core Retro Computer System</p>
        
        <div class="current">
            <p>Access Point: <strong id="apName">%AP_SSID%</strong></p>
            <p>IP Address: <strong>192.168.4.1</strong></p>
            <p id="staStatus"></p>
        </div>
        
        <button class="btn btn-secondary" onclick="scanNetworks()">🔍 Scan Networks</button>
        
        <div id="networks" class="networks" style="display:none"></div>
        
        <div class="divider"></div>
        
        <form id="wifiForm" onsubmit="saveWiFi(event)">
            <div class="form-group">
                <label>WiFi Network (SSID)</label>
                <input type="text" id="ssid" name="ssid" placeholder="Enter network name" required>
            </div>
            <div class="form-group">
                <label>Password</label>
                <input type="password" id="password" name="password" placeholder="Enter password">
            </div>
            <button type="submit" class="btn btn-primary">💾 Save & Connect</button>
        </form>
        
        <div class="info">
            <p><strong>Instructions:</strong></p>
            <p>1. Scan for available networks or enter manually</p>
            <p>2. Enter the WiFi password</p>
            <p>3. Click "Save & Connect"</p>
            <p>4. ESP32 will restart and connect to your network</p>
        </div>
        
        <div id="status" class="status" style="display:none"></div>
        
        <button class="btn btn-danger" onclick="resetWiFi()">🗑️ Reset WiFi Settings</button>
    </div>
    
    <script>
        let selectedNetwork = '';
        
        async function scanNetworks() {
            document.getElementById('networks').innerHTML = '<p style="color:#888;text-align:center;padding:20px">Scanning...</p>';
            document.getElementById('networks').style.display = 'block';
            try {
                const r = await fetch('/api/wifi/scan');
                const d = await r.json();
                let html = '';
                if (d.networks && d.networks.length > 0) {
                    d.networks.forEach(n => {
                        const signal = n.rssi > -50 ? '●●●●' : n.rssi > -70 ? '●●●○' : n.rssi > -80 ? '●●○○' : '●○○○';
                        html += `<div class="network" onclick="selectNetwork('${n.ssid}')">
                            <span>${n.ssid}</span>
                            <span class="signal">${signal} ${n.rssi}dBm</span>
                        </div>`;
                    });
                } else {
                    html = '<p style="color:#888;text-align:center;padding:20px">No networks found</p>';
                }
                document.getElementById('networks').innerHTML = html;
            } catch(e) {
                document.getElementById('networks').innerHTML = '<p style="color:#ff4444;text-align:center;padding:20px">Scan failed</p>';
            }
        }
        
        function selectNetwork(ssid) {
            document.querySelectorAll('.network').forEach(n => n.classList.remove('selected'));
            event.target.closest('.network').classList.add('selected');
            document.getElementById('ssid').value = ssid;
            selectedNetwork = ssid;
        }
        
        async function saveWiFi(e) {
            e.preventDefault();
            const ssid = document.getElementById('ssid').value;
            const password = document.getElementById('password').value;
            
            showStatus('Saving...', false);
            
            try {
                const r = await fetch('/api/wifi/save', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({ssid: ssid, password: password})
                });
                const d = await r.json();
                
                if (d.success) {
                    showStatus('✓ WiFi saved! Restarting...', true);
                    setTimeout(() => {
                        showStatus('Connect to your WiFi network and find the new IP in your router', true);
                    }, 3000);
                } else {
                    showStatus('✗ Failed to save: ' + (d.message || 'Unknown error'), false);
                }
            } catch(e) {
                showStatus('✗ Error: ' + e, false);
            }
        }
        
        async function resetWiFi() {
            if (!confirm('Reset all WiFi settings? The device will restart in AP mode.')) return;
            
            try {
                await fetch('/api/wifi/reset', {method: 'POST'});
                showStatus('✓ WiFi reset! Restarting...', true);
            } catch(e) {
                showStatus('✗ Error: ' + e, false);
            }
        }
        
        function showStatus(msg, success) {
            const s = document.getElementById('status');
            s.textContent = msg;
            s.className = 'status ' + (success ? 'success' : 'error');
            s.style.display = 'block';
        }
        
        // Check current status
        fetch('/api/wifi/status').then(r => r.json()).then(d => {
            if (d.configured && d.sta_ssid) {
                document.getElementById('staStatus').innerHTML = 'Saved Network: <strong>' + d.sta_ssid + '</strong>';
                document.getElementById('ssid').value = d.sta_ssid;
            }
        });
    </script>
</body>
</html>
)rawliteral";

//==============================================================================
// WIFI FUNCTIONS
//==============================================================================

// Genera SSID dinamico con ultimi 6 caratteri del MAC address
void generateAPSSID() {
    uint8_t mac[6];
    WiFi.macAddress(mac);
    sprintf(ap_ssid, "%s%02X%02X%02X", AP_SSID_PREFIX, mac[3], mac[4], mac[5]);
    Serial.printf("[WiFi] Generated AP SSID: %s\n", ap_ssid);
}

// Carica credenziali WiFi salvate da Preferences
void loadWiFiCredentials() {
    preferences.begin("wifi", true);  // Read-only
    String ssid = preferences.getString("sta_ssid", "");
    String pass = preferences.getString("sta_pass", "");
    preferences.end();
    
    if (ssid.length() > 0) {
        ssid.toCharArray(sta_ssid, sizeof(sta_ssid));
        pass.toCharArray(sta_password, sizeof(sta_password));
        wifiConfigured = true;
        Serial.printf("[WiFi] Loaded credentials for: %s\n", sta_ssid);
    } else {
        wifiConfigured = false;
        Serial.println("[WiFi] No saved credentials");
    }
}

// Salva credenziali WiFi in Preferences
void saveWiFiCredentials(const char* ssid, const char* password) {
    preferences.begin("wifi", false);  // Read-write
    preferences.putString("sta_ssid", ssid);
    preferences.putString("sta_pass", password);
    preferences.end();
    
    strcpy(sta_ssid, ssid);
    strcpy(sta_password, password);
    wifiConfigured = true;
    
    Serial.printf("[WiFi] Saved credentials for: %s\n", ssid);
}

// Cancella credenziali WiFi
void clearWiFiCredentials() {
    preferences.begin("wifi", false);
    preferences.remove("sta_ssid");
    preferences.remove("sta_pass");
    preferences.end();
    
    sta_ssid[0] = '\0';
    sta_password[0] = '\0';
    wifiConfigured = false;
    
    Serial.println("[WiFi] Credentials cleared");
}

// LED lampeggio per stato WiFi
void blinkWiFiLED(int times, int delayMs) {
    for (int i = 0; i < times; i++) {
        setLED(false, true, false);  // Verde
        delay(delayMs);
        setLED(false, false, false);
        delay(delayMs);
    }
}

// Tenta connessione a rete WiFi salvata
bool connectToWiFi() {
    if (!wifiConfigured || strlen(sta_ssid) == 0) {
        return false;
    }
    
    Serial.printf("[WiFi] Connecting to: %s\n", sta_ssid);
    
    WiFi.mode(WIFI_STA);
    WiFi.begin(sta_ssid, sta_password);
    
    unsigned long startTime = millis();
    int dots = 0;
    
    while (WiFi.status() != WL_CONNECTED) {
        if (millis() - startTime > WIFI_CONNECT_TIMEOUT) {
            Serial.println("\n[WiFi] Connection timeout!");
            return false;
        }
        
        // LED lampeggio veloce durante connessione
        setLED(false, (dots % 2 == 0), false);
        delay(250);
        dots++;
        Serial.print(".");
    }
    
    Serial.println();
    Serial.printf("[WiFi] Connected! IP: %s\n", WiFi.localIP().toString().c_str());
    
    // 3 lampeggi per confermare connessione
    blinkWiFiLED(3, 200);
    
    wifiClientMode = true;
    return true;
}

// Avvia Access Point
void startAccessPoint() {
    generateAPSSID();
    
    WiFi.mode(WIFI_AP);
    WiFi.softAP(ap_ssid, AP_PASSWORD);
    
    Serial.printf("[WiFi] AP Started: %s\n", ap_ssid);
    Serial.printf("[WiFi] AP Password: %s\n", AP_PASSWORD);
    Serial.printf("[WiFi] AP IP: %s\n", WiFi.softAPIP().toString().c_str());
    
    wifiClientMode = false;
    
    // LED lampeggio lento per AP mode
    setLED(false, false, true);  // Blu = AP mode
}

// Inizializza WiFi (tenta client, poi fallback ad AP)
void initWiFi() {
    loadWiFiCredentials();
    
    // Se ci sono credenziali salvate, prova a connettersi
    if (wifiConfigured) {
        Serial.println("[WiFi] Trying saved network...");
        
        tft.setTextColor(COLOR_WARNING);
        tft.drawString("WiFi...", 120, 220, 2);
        
        if (connectToWiFi()) {
            tft.setTextColor(COLOR_ACTIVE);
            tft.drawString("WiFi OK!", 120, 220, 2);
            return;
        } else {
            Serial.println("[WiFi] Failed, starting AP mode");
            tft.setTextColor(COLOR_ERROR);
            tft.drawString("WiFi failed", 120, 220, 2);
            delay(1000);
        }
    }
    
    // Fallback: avvia Access Point
    startAccessPoint();
    
    tft.setTextColor(COLOR_TEXT);
    tft.drawString("AP Mode", 120, 220, 2);
}

// Ottieni IP corrente (AP o STA)
String getCurrentIP() {
    if (wifiClientMode) {
        return WiFi.localIP().toString();
    } else {
        return WiFi.softAPIP().toString();
    }
}

//==============================================================================
// WEB SERVER SETUP
//==============================================================================

void setupWebServer() {
    server.on("/", HTTP_GET, [](AsyncWebServerRequest *req){
        req->send_P(200, "text/html", index_html);
    });
    
    // WiFi Configuration Page
    server.on("/wifi", HTTP_GET, [](AsyncWebServerRequest *req){
        String html = String(wifi_config_html);
        html.replace("%AP_SSID%", ap_ssid);
        req->send(200, "text/html", html);
    });
    
    // WiFi Status API
    server.on("/api/wifi/status", HTTP_GET, [](AsyncWebServerRequest *req){
        String json = "{";
        json += "\"configured\":" + String(wifiConfigured ? "true" : "false") + ",";
        json += "\"client_mode\":" + String(wifiClientMode ? "true" : "false") + ",";
        json += "\"ap_ssid\":\"" + String(ap_ssid) + "\",";
        json += "\"sta_ssid\":\"" + String(sta_ssid) + "\",";
        json += "\"ip\":\"" + getCurrentIP() + "\",";
        json += "\"rssi\":" + String(wifiClientMode ? WiFi.RSSI() : 0);
        json += "}";
        req->send(200, "application/json", json);
    });
    
    // WiFi Scan API
    server.on("/api/wifi/scan", HTTP_GET, [](AsyncWebServerRequest *req){
        int n = WiFi.scanNetworks();
        String json = "{\"networks\":[";
        for (int i = 0; i < n && i < 20; i++) {
            if (i > 0) json += ",";
            json += "{\"ssid\":\"" + WiFi.SSID(i) + "\",";
            json += "\"rssi\":" + String(WiFi.RSSI(i)) + ",";
            json += "\"secure\":" + String(WiFi.encryptionType(i) != WIFI_AUTH_OPEN ? "true" : "false") + "}";
        }
        json += "]}";
        WiFi.scanDelete();
        req->send(200, "application/json", json);
    });
    
    // WiFi Save API
    server.on("/api/wifi/save", HTTP_POST, [](AsyncWebServerRequest *req){},
        NULL,
        [](AsyncWebServerRequest *req, uint8_t *data, size_t len, size_t index, size_t total){
            String body = "";
            for (size_t i = 0; i < len; i++) body += (char)data[i];
            
            // Parse JSON
            int ssidStart = body.indexOf("\"ssid\":\"") + 8;
            int ssidEnd = body.indexOf("\"", ssidStart);
            String ssid = body.substring(ssidStart, ssidEnd);
            
            int passStart = body.indexOf("\"password\":\"") + 12;
            int passEnd = body.indexOf("\"", passStart);
            String password = body.substring(passStart, passEnd);
            
            if (ssid.length() > 0) {
                saveWiFiCredentials(ssid.c_str(), password.c_str());
                req->send(200, "application/json", "{\"success\":true}");
                
                // Restart dopo 2 secondi
                delay(2000);
                ESP.restart();
            } else {
                req->send(200, "application/json", "{\"success\":false,\"message\":\"Invalid SSID\"}");
            }
        });
    
    // WiFi Reset API
    server.on("/api/wifi/reset", HTTP_POST, [](AsyncWebServerRequest *req){
        clearWiFiCredentials();
        req->send(200, "application/json", "{\"success\":true}");
        
        // Restart dopo 2 secondi
        delay(2000);
        ESP.restart();
    });
    
    server.on("/api/status", HTTP_GET, [](AsyncWebServerRequest *req){
        String json = "{";
        json += "\"fpgaReady\":" + String(fpgaReady ? "true" : "false") + ",";
        json += "\"sdReady\":" + String(sdCardReady ? "true" : "false") + ",";
        json += "\"core\":\"" + String(systems[currentCore].name) + "\",";
        json += "\"loading\":" + String(webLoadPending ? "true" : "false") + ",";
        json += "\"loadComplete\":" + String(webLoadComplete ? "true" : "false") + ",";
        json += "\"loadSuccess\":" + String(webLoadSuccess ? "true" : "false");
        json += "}";
        req->send(200, "application/json", json);
    });
    
    server.on("/api/systems", HTTP_GET, [](AsyncWebServerRequest *req){
        String json = "{\"systems\":[";
        for (int i = 0; i < NUM_SYSTEMS; i++) {
            if (i > 0) json += ",";
            json += "{\"id\":\"" + String(systems[i].id) + "\",";
            json += "\"name\":\"" + String(systems[i].name) + "\",";
            json += "\"year\":" + String(systems[i].year) + ",";
            json += "\"romCount\":" + String(systems[i].romCount) + ",";
            json += "\"progCount\":" + String(i == currentCore ? programCount : 0) + "}";
        }
        json += "]}";
        req->send(200, "application/json", json);
    });
    
    server.on("/api/load", HTTP_POST, [](AsyncWebServerRequest *req){},
        NULL,
        [](AsyncWebServerRequest *req, uint8_t *data, size_t len, size_t index, size_t total){
            String body = "";
            for (size_t i = 0; i < len; i++) body += (char)data[i];
            
            int start = body.indexOf("\"system\":\"") + 10;
            int end = body.indexOf("\"", start);
            String sysId = body.substring(start, end);
            
            int sysIndex = -1;
            for (int i = 0; i < NUM_SYSTEMS; i++) {
                if (String(systems[i].id) == sysId) {
                    sysIndex = i;
                    break;
                }
            }
            
            if (sysIndex >= 0) {
                // Caricamento differito: imposta flag, il loop() farà il lavoro
                webLoadSystemIndex = sysIndex;
                webLoadComplete = false;
                webLoadSuccess = false;
                webLoadPending = true;
                
                // Rispondi subito, il client farà polling su /api/status
                req->send(200, "application/json", "{\"success\":true,\"loading\":true}");
            } else {
                req->send(200, "application/json", "{\"success\":false,\"message\":\"System not found\"}");
            }
        });
    
    server.on("/api/reset", HTTP_POST, [](AsyncWebServerRequest *req){
        sendToFPGA("RESET");
        currentCore = 0;
        romLoaded = false;
        webLoadPending = false;
        webLoadComplete = false;
        webLoadSuccess = false;
        preferences.putInt("core", 0);
        req->send(200, "application/json", "{\"success\":true}");
    });
    
    // API per lista file BAS
    server.on("/api/basfiles", HTTP_GET, [](AsyncWebServerRequest *req){
        String json = "{\"files\":[";
        for (int i = 0; i < basFileCount; i++) {
            if (i > 0) json += ",";
            json += "\"" + String(basFileList[i].name) + "\"";
        }
        json += "]}";
        req->send(200, "application/json", json);
    });
    
    // API per stato caricamento BAS
    server.on("/api/basstatus", HTTP_GET, [](AsyncWebServerRequest *req){
        String json = "{";
        json += "\"loading\":" + String(basLoadPending ? "true" : "false") + ",";
        json += "\"complete\":" + String(basLoadComplete ? "true" : "false") + ",";
        json += "\"success\":" + String(basLoadSuccess ? "true" : "false");
        json += "}";
        req->send(200, "application/json", json);
    });
    
    // API per caricare file BAS (caricamento differito)
    server.on("/api/loadbas", HTTP_POST, [](AsyncWebServerRequest *req){},
        NULL,
        [](AsyncWebServerRequest *req, uint8_t *data, size_t len, size_t index, size_t total){
            String body = "";
            for (size_t i = 0; i < len; i++) body += (char)data[i];
            
            int start = body.indexOf("\"index\":") + 8;
            int idx = body.substring(start).toInt();
            
            if (idx >= 0 && idx < basFileCount) {
                // Caricamento differito: imposta flag, il loop() farà il lavoro
                basLoadIndex = idx;
                basLoadComplete = false;
                basLoadSuccess = false;
                basLoadPending = true;
                req->send(200, "application/json", "{\"success\":true,\"loading\":true}");
            } else {
                req->send(200, "application/json", "{\"success\":false,\"message\":\"Invalid index\"}");
            }
        });
    
    server.on("/api/keyboard", HTTP_POST, [](AsyncWebServerRequest *req){},
        NULL,
        [](AsyncWebServerRequest *req, uint8_t *data, size_t len, size_t index, size_t total){
            String body = "";
            for (size_t i = 0; i < len; i++) body += (char)data[i];
            
            // Parsing robusto che gestisce virgolette escaped (\")
            int start = body.indexOf("\"text\":\"") + 8;
            int end = start;
            bool escaped = false;
            
            // Trova la vera fine della stringa (virgoletta non escaped)
            while (end < body.length()) {
                char c = body.charAt(end);
                if (escaped) {
                    escaped = false;
                } else if (c == '\\') {
                    escaped = true;
                } else if (c == '"') {
                    break;  // Trovata virgoletta di chiusura
                }
                end++;
            }
            
            String rawText = body.substring(start, end);
            
            // Decodifica escape sequences (\\ -> \, \" -> ")
            String text = "";
            for (int i = 0; i < rawText.length(); i++) {
                char c = rawText.charAt(i);
                if (c == '\\' && i + 1 < rawText.length()) {
                    char next = rawText.charAt(i + 1);
                    if (next == '"' || next == '\\') {
                        text += next;
                        i++;  // Salta il carattere successivo
                        continue;
                    }
                }
                text += c;
            }
            
            // Invio differito: salva nel buffer, il loop() invierà
            keyboardBuffer = text;
            keyboardComplete = false;
            keyboardPending = true;
            
            req->send(200, "application/json", "{\"success\":true}");
        });
    
    // Endpoint per digitare programma BASIC
    // Buffer statico per accumulare dati multipart
    static String typePostBuffer = "";
    
    server.on("/api/typebas", HTTP_POST, 
        // Handler finale (chiamato dopo tutti i chunk)
        [](AsyncWebServerRequest *req){
            // Processing fatto nel body handler
        },
        NULL,
        // Body handler (chiamato per ogni chunk)
        [](AsyncWebServerRequest *req, uint8_t *data, size_t len, size_t index, size_t total){
            // Se è il primo chunk, pulisci il buffer
            if (index == 0) {
                typePostBuffer = "";
                typePostBuffer.reserve(total + 1);  // Pre-alloca memoria
                Serial.printf("[TYPE] Receiving %d bytes...\n", total);
            }
            
            // Accumula questo chunk
            for (size_t i = 0; i < len; i++) {
                typePostBuffer += (char)data[i];
            }
            
            // Se abbiamo ricevuto tutto, processa
            if (index + len >= total) {
                Serial.printf("[TYPE] Received complete body: %d bytes\n", typePostBuffer.length());
                
                // Estrai il codice dal JSON
                int start = typePostBuffer.indexOf("\"code\":\"") + 8;
                int end = start;
                bool escaped = false;
                
                while (end < typePostBuffer.length()) {
                    char c = typePostBuffer.charAt(end);
                    if (escaped) {
                        escaped = false;
                    } else if (c == '\\') {
                        escaped = true;
                    } else if (c == '"') {
                        break;
                    }
                    end++;
                }
                
                String rawCode = typePostBuffer.substring(start, end);
                typePostBuffer = "";  // Libera memoria
                
                // Decodifica escape sequences
                String code = "";
                code.reserve(rawCode.length());
                for (int i = 0; i < rawCode.length(); i++) {
                    char c = rawCode.charAt(i);
                    if (c == '\\' && i + 1 < rawCode.length()) {
                        char next = rawCode.charAt(i + 1);
                        if (next == 'n') {
                            code += '\n';
                            i++;
                            continue;
                        } else if (next == 'r') {
                            i++;  // Ignora \r
                            continue;
                        } else if (next == '"' || next == '\\') {
                            code += next;
                            i++;
                            continue;
                        }
                    }
                    code += c;
                }
                
                // Conta le righe
                int lines = 0;
                for (int i = 0; i < code.length(); i++) {
                    if (code.charAt(i) == '\n') lines++;
                }
                if (code.length() > 0 && code.charAt(code.length()-1) != '\n') lines++;
                
                // Imposta variabili per invio differito
                typeCodeBuffer = code;
                typeTotalLines = lines;
                typeCurrentLine = 0;
                typeComplete = false;
                typeSuccess = false;
                typeStatusMsg = "Starting...";
                typePending = true;
                
                Serial.printf("[TYPE] Parsed %d lines of BASIC code\n", lines);
                req->send(200, "application/json", "{\"success\":true}");
            }
        });
    
    // Endpoint stato typing
    server.on("/api/typestatus", HTTP_GET, [](AsyncWebServerRequest *req){
        String json = "{\"complete\":" + String(typeComplete ? "true" : "false") +
                      ",\"success\":" + String(typeSuccess ? "true" : "false") +
                      ",\"line\":" + String(typeCurrentLine) +
                      ",\"total\":" + String(typeTotalLines) +
                      ",\"status\":\"" + typeStatusMsg + "\"}";
        req->send(200, "application/json", json);
    });
    
    server.begin();
    Serial.println("[WEB] Server started");
}

//==============================================================================
// SETUP
//==============================================================================

void setup() {
    Serial.begin(115200);
    delay(500);
    
    Serial.println("\n========================================");
    Serial.println("  RETROPC - ESP32 v4.0");
    Serial.println("  Touch + WebApp + LOAD_REQ + BAS");
    Serial.println("========================================\n");
    
    // LED
    pinMode(LED_RED, OUTPUT);
    pinMode(LED_GREEN, OUTPUT);
    pinMode(LED_BLUE, OUTPUT);
    setLED(false, false, true);
    
    // Preferences
    preferences.begin("retropc", false);
    currentCore = preferences.getInt("core", 0);
    
    // Display
    pinMode(TFT_BL, OUTPUT);
    digitalWrite(TFT_BL, HIGH);
    tft.init();
    tft.setRotation(0);
    tft.fillScreen(COLOR_BG);
    tft.setTextColor(COLOR_ACTIVE);
    tft.setTextDatum(MC_DATUM);
    tft.drawString("RETROPC v4", 120, 100, 4);
    tft.setTextColor(COLOR_TEXT);
    tft.drawString("Init...", 120, 200, 2);
    
    // Touch
    touch.setCal(495, 3398, 721, 3448, 320, 240, 1);
    touch.setRotation(0);
    
    // SD Card
    sdCardReady = initSDCard();
    if (sdCardReady) {
        scanROMs();
        setLED(false, true, false);
    } else {
        setLED(true, false, false);
    }
    
    // UART FPGA
    Serial.println("[UART] Init GPIO26/27...");
    FPGASerial.setRxBufferSize(1024);
    FPGASerial.begin(115200, SERIAL_8N1, FPGA_RX_PIN, FPGA_TX_PIN);
    delay(100);
    
    // Test FPGA
    testFPGA();
    
    // WiFi - Prova connessione a rete salvata, altrimenti AP mode
    initWiFi();
    
    // Web Server
    setupWebServer();
    
    // Done
    delay(500);
    redrawScreen();
    setLED(false, false, false);
    
    Serial.println("\n✓ System ready!");
    Serial.println("  Touch display or use serial commands");
    Serial.println("  WebApp: http://" + getCurrentIP());
    Serial.println("  WiFi Setup: http://" + getCurrentIP() + "/wifi");
    Serial.println("  Systems: 0=Test, 1=C64, 2=ZX Spectrum, 3=VIC-20, 4=Apple I");
    Serial.println("  Commands: g=games, b=bt, k=keyboard, h=help\n");
}

//==============================================================================
// LOOP
//==============================================================================

void loop() {
    handleTouch();
    handleSerialCommand();
    
    // === CARICAMENTO DIFFERITO DA WEBAPP ===
    // Esegue loadSystemROMs() qui nel loop() invece che nella callback HTTP
    // per evitare watchdog reset (la callback ha stack e tempo limitati)
    if (webLoadPending) {
        webLoadPending = false;  // Reset flag subito
        
        Serial.println("[WEB] Deferred load started...");
        setLED(false, false, true);  // LED blu durante caricamento
        
        // Esegui il caricamento
        webLoadSuccess = loadSystemROMs(webLoadSystemIndex);
        webLoadComplete = true;
        
        if (webLoadSuccess) {
            Serial.println("[WEB] Load completed successfully!");
            setLED(false, true, false);  // LED verde
        } else {
            Serial.println("[WEB] Load FAILED!");
            setLED(true, false, false);  // LED rosso
        }
        
        delay(500);
        setLED(false, false, false);
        redrawScreen();
    }
    
    // === CARICAMENTO DIFFERITO FILE BAS ===
    if (basLoadPending) {
        basLoadPending = false;  // Reset flag subito
        
        Serial.println("[WEB] BAS load started...");
        setLED(false, false, true);  // LED blu durante caricamento
        
        // Esegui il caricamento BAS
        basLoadSuccess = loadAndRunBASFile(basFileList[basLoadIndex].path);
        basLoadComplete = true;
        
        if (basLoadSuccess) {
            Serial.println("[WEB] BAS load completed!");
            setLED(false, true, false);  // LED verde
        } else {
            Serial.println("[WEB] BAS load FAILED!");
            setLED(true, false, false);  // LED rosso
        }
        
        delay(300);
        setLED(false, false, false);
    }
    
    // === INVIO TASTIERA DIFFERITO ===
    if (keyboardPending) {
        keyboardPending = false;  // Reset flag subito
        
        Serial.printf("[WEB] Keyboard send: '%s'\n", keyboardBuffer.c_str());
        
        // Invia ogni carattere
        for (int i = 0; i < keyboardBuffer.length(); i++) {
            char c = keyboardBuffer.charAt(i);
            // Converti in maiuscolo per sistemi 8-bit
            if (currentCore >= 1 && currentCore <= 4) {
                if (c >= 'a' && c <= 'z') c -= 32;
            }
            sendKeyToFPGA(c);
        }
        
        // Delay prima di RETURN
        delay(200);
        
        // Invia RETURN
        sendKeyToFPGA(0x0D);
        
        // Delay dopo RETURN
        delay(200);
        
        keyboardComplete = true;
        keyboardBuffer = "";
        
        Serial.println("[WEB] Keyboard send complete!");
    }
    
    // === TYPE BASIC PROGRAM (invio riga per riga) ===
    if (typePending) {
        typePending = false;  // Reset flag subito
        
        Serial.printf("[TYPE] Starting to type %d lines...\n", typeTotalLines);
        setLED(false, false, true);  // LED blu
        
        // Delay e timing per ogni core
        int charDelay = 80;   // C64/VIC-20
        int lineDelay = 800;
        
        if (currentCore == 2) {  // ZX Spectrum - più lento
            charDelay = 100;
            lineDelay = 1000;
            Serial.println("[TYPE] ZX Spectrum: using keyboard input");
        }
        else if (currentCore == 4) {  // Apple I
            charDelay = 120;
            lineDelay = 500;
        }
        
        // Processa ogni riga
        int lineNum = 0;
        int pos = 0;
        String line = "";
        
        while (pos <= typeCodeBuffer.length()) {
            char c = (pos < typeCodeBuffer.length()) ? typeCodeBuffer.charAt(pos) : '\n';
            
            if (c == '\n' || c == '\r') {
                // Fine riga - invia se non vuota
                line.trim();
                if (line.length() > 0) {
                    lineNum++;
                    typeCurrentLine = lineNum;
                    typeStatusMsg = "Sending line " + String(lineNum) + " of " + String(typeTotalLines);
                    
                    Serial.printf("[TYPE] Line %d: %s\n", lineNum, line.c_str());
                    
                    // Invia ogni carattere della riga
                    for (int i = 0; i < line.length(); i++) {
                        char ch = line.charAt(i);
                        // Converti in maiuscolo per sistemi 8-bit
                        if (ch >= 'a' && ch <= 'z') {
                            ch -= 32;
                        }
                        sendKeyToFPGA((uint8_t)ch);
                        delay(charDelay);
                        yield();  // Evita watchdog
                    }
                    
                    // Invia RETURN
                    sendKeyToFPGA(0x0D);
                    delay(lineDelay);
                    yield();
                }
                line = "";
                
                // Salta eventuali \r\n consecutivi
                while (pos + 1 < typeCodeBuffer.length() && 
                       (typeCodeBuffer.charAt(pos + 1) == '\n' || typeCodeBuffer.charAt(pos + 1) == '\r')) {
                    pos++;
                }
            } else {
                line += c;
            }
            pos++;
        }
        
        typeSuccess = true;
        typeComplete = true;
        typeStatusMsg = "Done! " + String(lineNum) + " lines typed.";
        typeCodeBuffer = "";
        
        Serial.printf("[TYPE] Complete! Sent %d lines\n", lineNum);
        setLED(false, true, false);  // LED verde
        delay(300);
        setLED(false, false, false);
    }
    
    // Handle FPGA responses and commands
    while (FPGASerial.available()) {
        String line = FPGASerial.readStringUntil('\n');
        line.trim();
        if (line.length() > 0) {
            // Gestisci LOAD_REQ dal C64
            if (line.startsWith("LOAD_REQ")) {
                handleLoadRequest(line);
            } else {
                Serial.print("[FPGA] ");
                Serial.println(line);
            }
        }
    }
    
    delay(10);
}
