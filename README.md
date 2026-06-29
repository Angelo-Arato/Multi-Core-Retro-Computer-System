# MULTI-CORE RETRO COMPUTER SYSTEM

## Architettura Ibrida FPGA/MCU per Emulazione Retro Computer

**Autore:** Angelo Arato  
**Università:** Telematica Mercatorum - Ingegneria Gestionale  
**Data:** Dicembre 2025  
**Versione:** 1.0

---

## Panoramica

Sistema multi-core di emulazione retro computer su FPGA DE10-Lite (Intel MAX 10) con ESP32 come controller. L'architettura ibrida combina la precisione dell'emulazione hardware FPGA con la flessibilità del firmware ESP32 per gestione ROM, interfaccia utente e testing automatizzato.

### Sistemi Supportati

| Core | Sistema | CPU | RAM | ROM | Anno |
|------|---------|-----|-----|-----|------|
| 0 | Test Pattern | - | - | - | - |
| 1 | Commodore 64 | 6510 | 64KB | 20KB | 1982 |
| 2 | ZX Spectrum 48K | Z80 | 48KB | 16KB | 1982 |
| 3 | VIC-20 | 6502 | 8KB | 20KB | 1980 |
| 4 | Apple I | 6502 | 2KB | 256B | 1976 |

---

## Architettura del Sistema

```
┌────────────────────────────────────────────────────────────────┐
│                        ESP32-DevKitC                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │ WiFi/Web │  │ SD Card  │  │   TFT    │  │  Serial  │        │
│  │  Server  │  │  Reader  │  │ Display  │  │ Console  │        │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘        │
│       └─────────────┴─────────────┴─────────────┘              │
│                           │                                    │
│                      [UART 115200]                             │
└───────────────────────────┼────────────────────────────────────┘
                            │
┌───────────────────────────┼────────────────────────────────────┐
│  DE10-Lite FPGA           │                                    │
│  ┌────────────────────────┴────────────────────────────────┐   │
│  │                  UART Controller                        │   │
│  │              ┌──────────────────┐                       │   │
│  │              │  Command Parser  │                       │   │
│  │              └────────┬─────────┘                       │   │
│  │                       │                                 │   │
│  │  ┌────────┬───────────┼───────────┬────────┐            │   │
│  │  │        │           │           │        │            │   │
│  │  ▼        ▼           ▼           ▼        ▼            │   │
│  │ ┌───┐  ┌─────┐   ┌────────┐   ┌──────┐ ┌───────┐        │   │
│  │ │C64│  │VIC20│   │Spectrum│   │Apple1│ │ROM    │        │   │
│  │ │   │  │     │   │        │   │      │ │Loader │        │   │
│  │ └───┘  └─────┘   └────────┘   └──────┘ └───────┘        │   │
│  │   │        │          │           │        │            │   │
│  │   └────────┴──────────┴───────────┴────────┘            │   │
│  │                       │                                 │   │
│  │              ┌────────┴─────────┐                       │   │
│  │              │  Shared RAM/ROM  │                       │   │
│  │              │      Pool        │                       │   │
│  │              └──────────────────┘                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                    │
│              ┌────────────┴─────────────┐                      │
│              │      VGA Controller      │                      │
│              │    (640x480 @60Hz)       │                      │
│              │(800x600 @72Hz con SW8-ON)│                      │
│              └──────────────────────────┘                      │
└────────────────────────────────────────────────────────────────┘
```

---

## Utilizzo Risorse FPGA

### Architettura Condivisa

```
Device: 10M50DAF484C7G (MAX 10)
Logic Elements:    ~45,000 / 49,760 (90%)
Memory Bits:      ~1,430,000 / 1,677,312 (85%)
```

---

## Struttura File

### Directory Principale

```
Multi-Core-Retro-Computer-System/
│
├── README.md                         # Documentazione progetto
├── retro_multicore_cpu.qpf           # File progetto Quartus
├── retro_multicore_cpu.qsf           # Settings Quartus
│
├── rtl/                              # Sorgenti Verilog/VHDL
│   ├── retro_multicore_top_cpu.v     # Top-level module
│   ├── c64_complete.v                # Core Commodore 64
│   ├── vic20_complete.v              # Core VIC-20
│   ├── zxspectrum_complete.v         # Core ZX Spectrum
│   ├── apple1_complete.v             # Core Apple I
│   ├── apple1_rom.v                  # Woz Monitor ROM
│   ├── apple1_ram.v                  # RAM Apple I
│   ├── apple1_font_rom.v             # Font ROM Apple I
│   ├── zx_memory.v                   # Memoria ZX Spectrum
│   ├── shared_ram.v                  # RAM condivisa
│   ├── rom_chargen.v                 # Character generator ROM
│   ├── rom_loader.v                  # Caricatore ROM da UART
│   ├── load_handler.v                # Gestore caricamento programmi
│   ├── uart_controller.v             # Controller UART
│   ├── command_parser.v              # Parser comandi
│   ├── ps2_keyboard.v                # Controller tastiera PS/2
│   ├── test_pattern_gen.v            # Generatore test pattern
│   │
│   ├── t65/                          # Soft-core 6502
│   │   ├── T65.vhd                   # Core principale
│   │   ├── T65_ALU.vhd               # Unità aritmetico-logica
│   │   ├── T65_MCode.vhd             # Microcode
│   │   ├── T65_Pack.vhd              # Package definizioni
│   │   └── T65_wrapper.v             # Wrapper Verilog
│   │
│   └── t80/                          # Soft-core Z80
│       ├── T80.vhd                   # Core principale
│       ├── T80a.vhd                  # Versione alternativa
│       ├── T80_ALU.vhd               # Unità aritmetico-logica
│       ├── T80_MCode.vhd             # Microcode
│       ├── T80_Pack.vhd              # Package definizioni
│       ├── T80_Reg.vhd               # File registri
│       └── T80_wrapper.v             # Wrapper Verilog
│
└── esp32/                            # Firmware ESP32
    └── RetroPC_ESP32_v4/
        ├── RetroPC_ESP32_v4.ino      # Firmware principale
        └── icons.h                   # Icone per display TFT
```

### Struttura SD Card

```
/sd
├── /roms
│   ├── /c64/                         # ROM Commodore 64
│   ├── /spectrum/                    # ROM ZX Spectrum
│   ├── /vic20/                       # ROM VIC-20
│   └── /apple1/                      # (Woz Monitor integrato)
│
├── /progs
│   ├── /c64/                         # Programmi .prg C64
│   ├── /vic20/                       # Programmi .prg VIC-20
│   └── /spectrum/                    # Programmi .z80 Spectrum
│
└── /floppy/                          # Immagini disco .d64
```

---

## Connessioni Hardware

### ESP32 ↔ FPGA (UART)

| ESP32 | FPGA (GPIO) | Funzione |
|-------|-------------|----------|
| GPIO26 (TX) | GPIO[1] / PIN_W10 | ESP32 → FPGA |
| GPIO27 (RX) | GPIO[0] / PIN_V10 | FPGA → ESP32 |
| GND | GND | Massa comune |

### Tastiera PS/2

| Segnale | GPIO | PIN FPGA | Header |
|---------|------|----------|--------|
| PS2_CLK | GPIO[2] | PIN_AA15 | JP1-3 |
| PS2_DATA | GPIO[3] | PIN_AB15 | JP1-4 |
| +5V | - | - | JP1-29 |
| GND | - | - | JP1-30 |

#### Schema Connessione Adattatore PS/2

```
Connettore PS/2 (vista frontale - fori):

    ┌───────────┐
    │  6     5  │    Pin 1: DATA  ──► PS2_DATA
    │     ┌───┐ │    Pin 2: N/C
    │  4  │   │ │    Pin 3: GND   ──► GND
    │     └───┘ │    Pin 4: +5V   ──► 5V
    │  3  2  1  │    Pin 5: CLK   ──► PS2_CLK
    └───────────┘    Pin 6: N/C
```

#### Resistenze Pull-up

Se la tastiera non funziona correttamente, aggiungere resistenze pull-up:

```
PS2_CLK  ──┬── 4.7kΩ ──┬── +3.3V
           │           │
PS2_DATA ──┴── 4.7kΩ ──┘
```

**Nota:** La DE10-Lite ha già pull-up interni abilitabili via Quartus. Nel file `.qsf`:
```tcl
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to PS2_CLK
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to PS2_DATA
```

#### Layout Tastiera Supportato

Il sistema supporta layout **italiano** con mappatura automatica:
- Tasti speciali: ò, à, è, ì, ù
- Shift + numeri per simboli
- AltGr per caratteri speciali (@, #, €, ecc.)

---

## Comandi ESP32

### Selezione Sistema

| Comando | Sistema |
|---------|---------|
| `0` | Test Pattern |
| `1` | Commodore 64 |
| `2` | ZX Spectrum 48K |
| `3` | VIC-20 |
| `4` | Apple I |

### Comandi Generali

| Comando | Descrizione |
|---------|-------------|
| `p` | Ping FPGA (verifica connessione) |
| `s` | Status del sistema |
| `r` | Reset core corrente |
| `k` | Modalità tastiera (~ per uscire) |
| `h` | Help |
| `a` | Animazione demo |

### Test

| Comando | Descrizione |
|---------|-------------|
| `t` | Test BASIC semplice (Hello World) |
| `c` | Test CPU 6502 completo (C64/VIC-20) |
| `z` | Test CPU Z80 completo (ZX Spectrum) |

### Programmi e Disk (solo C64)

| Comando | Descrizione |
|---------|-------------|
| `g` | Lista programmi PRG |
| `l` | Carica programma per numero |
| `m` | Monta immagine D64 |
| `f` | Directory D64 |
| `e` | Carica file da D64 |
| `u` | Smonta D64 |

### Modalità Tastiera

| Comando | Azione |
|---------|--------|
| `~` | Esci da keyboard mode |
| `ESC+M` | Toggle LINE/CHAR mode |
| `ESC+H` | HOME |
| `ESC+C` | CLR (clear screen) |
| `ESC+U/D/L/R` | Cursori |
| `ESC+1-8` | Tasti funzione F1-F8 |
| `Backspace` | Cancella ultimo carattere (LINE mode) |

---

## Apple I - Woz Monitor

### Comandi

| Comando | Esempio | Descrizione |
|---------|---------|-------------|
| `<addr>` | `300` | Imposta indirizzo corrente |
| `<addr>.<addr>` | `300.3FF` | Visualizza range memoria |
| `<addr>: <bb>` | `300: A9 00` | Deposita bytes |
| `<addr>R` | `300R` | Esegue da indirizzo |

The Apple I-compatible core does not include the original Woz Monitor ROM. A placeholder ROM is provided only to allow synthesis/testing. Users must provide legally obtained monitor code if required.

### Caratteristiche

- Display: 32 colonne × 16 righe
- Colore: Verde fosforescente su nero
- Cursore lampeggiante
- Solo UPPERCASE (conversione automatica)
- RAM: $0000-$07FF (2KB)
- PIA: $D010-$D013
- ROM: $FF00-$FFFF

---

## VIC-20 - Note ROM

Le ROM vengono caricate nell'ordine specificato:

| Ordine | File | Destinazione |
|--------|------|--------------|
| 1 | `basic.bin` | $C000 (8KB) |
| 2 | `kernal.bin` | $E000 (8KB) |
| 3 | `characters.bin` | $8000 (4KB) |

**IMPORTANTE:** L'ordine è fondamentale! BASIC → KERNAL → CHAR

---

## Compilazione

### Quartus (FPGA)

1. Aprire `quartus/retro_multicore_cpu.qpf`
2. Processing → Start Compilation
3. Tools → Programmer → Start

### Arduino IDE (ESP32)

1. Installare board ESP32 (Espressif Systems)
2. Aprire `esp32/RetroPC_ESP32_v4.ino`
3. Selezionare board "ESP32 Dev Module"
4. Impostare Upload Speed: 460800
5. Impostare (No OTA 2MB/2MB)
6. Upload

### Librerie ESP32 Richieste

- WiFi (built-in)
- WebServer (built-in)
- SD (built-in)
- BluetoothSerial (built-in)

---

## LED Status (DE10-Lite)

| LED | Funzione |
|-----|----------|
| LEDR[2:0] | Numero core attivo (0-4) |
| LEDR[3] | ROM loading attivo |
| LEDR[4] | Attività UART RX |
| LEDR[5] | Byte UART valido |
| LEDR[6] | Comando KEY_CHAR riconosciuto |
| LEDR[7] | Key strobe ai core |
| LEDR[8] | Debug IRQ/Timer |

## Display 7-Segment

| Core | Display |
|------|---------|
| 0 | `tESt 0` |
| 1 | `C 64 1` |
| 2 | `SPEc 2` |
| 3 | `U-20 3` |
| 4 | `APL 1 4` |

### Debug Mode

| HEX | Funzione |
|-----|----------|
| HEX3-HEX0 | Indirizzo CPU (es. "FF00") |
| HEX5-HEX4 | Dati letti (cpu_din) |

---

## WebApp e Configurazione WiFi

L'ESP32 espone una WebApp per controllo remoto via WiFi con due modalità operative.

### Configurazione WiFi Default

```
SSID:     RetroPC_XXXXXX    (XXXXXX = ultimi 6 caratteri MAC in esadecimale)
Password: retro2025
IP:       192.168.4.1       (modalità Access Point)
```

### Credenziali Modificabili nel Firmware

Nel file `RetroPC_ESP32_v4.ino`, cerca la sezione configurazione:

```cpp
// ===== WiFi Configuration =====
#define AP_SSID_PREFIX "RetroPC_"        // Prefisso nome Access Point
#define AP_PASSWORD    "retro2025"       // Password Access Point
#define WIFI_CONNECT_TIMEOUT 15000       // Timeout connessione (ms)
```

### Modalità di Funzionamento

#### 1. Modalità Access Point (Default)

Se non è configurata una rete WiFi, l'ESP32 crea un proprio hotspot:

1. **Accendi il sistema** - L'ESP32 crea l'Access Point
2. **Cerca la rete WiFi** `RetroPC_XXXXXX` sul tuo dispositivo (es: `RetroPC_A1B2C3`)
3. **Connettiti** con password `retro2025`
4. **Apri il browser** e vai su `http://192.168.4.1`
5. **Usa la WebApp** per controllare il sistema
6. **Configura WiFi** andando su `http://192.168.4.1/wifi`

#### 2. Modalità Client (Connessione a Rete Esistente)

Se hai configurato una rete WiFi nel firmware:

1. **L'ESP32 si connette** alla rete configurata
2. **L'IP viene assegnato** dal router (DHCP)
3. **Controlla il Serial Monitor** per vedere l'IP assegnato
4. **Apri il browser** e vai su `http://[IP_ASSEGNATO]`

### Prima Configurazione WiFi

Al primo avvio o dopo un reset:

```
1. Connettiti al WiFi "RetroPC_XXXXXX"
2. Password: retro2025
3. Apri http://192.168.4.1
4. Clicca "Configura WiFi"
5. Seleziona la tua rete domestica
6. Inserisci la password
7. Clicca "Salva e Connetti"
8. L'ESP32 si riavvia e si connette alla nuova rete
```

### Interfaccia WebApp

#### Pagina Principale

<img width="946" height="1038" alt="image" src="https://github.com/user-attachments/assets/2781e58f-42bc-40ed-847f-6043b9025e4c" />

### Endpoint API REST

| Metodo | Endpoint | Descrizione |
|--------|----------|-------------|
| GET | `/` | Pagina principale WebApp |
| GET | `/api/status` | Status JSON del sistema |
| POST | `/api/core` | Cambio core (body: `{"core": 1}`) |
| POST | `/api/keyboard` | Invio testo (body: `{"text": "..."}`) |
| POST | `/api/reset` | Reset core corrente |
| GET | `/api/ping` | Test connessione FPGA |

#### Esempio Response `/api/status`

```json
{
  "core": 1,
  "core_name": "C64",
  "uptime": 3600,
  "fpga_connected": true,
  "sd_card": true,
  "wifi_rssi": -45,
  "ip": "192.168.1.105",
  "free_heap": 120000
}
```

### Configurazione Avanzata

#### Cambio Password Access Point

Modifica nel firmware:
```cpp
#define AP_PASSWORD "tua_nuova_password"
```

#### IP Statico (opzionale)

Per assegnare un IP fisso quando connesso a una rete:
```cpp
IPAddress local_IP(192, 168, 1, 200);
IPAddress gateway(192, 168, 1, 1);
IPAddress subnet(255, 255, 255, 0);
WiFi.config(local_IP, gateway, subnet);
```

#### Disabilitare Access Point

Per usare solo la connessione a rete esistente:
```cpp
#define DISABLE_AP_MODE true
```

### Reset Configurazione WiFi

Se hai problemi di connessione:

1. **Via Serial Monitor:** Invia il comando `wifi_reset`
2. **Via Hardware:** Tieni premuto il pulsante BOOT per 10 secondi all'avvio
3. **Via WebApp:** Pagina Impostazioni → "Reset WiFi"

L'ESP32 cancellerà le credenziali salvate e tornerà in modalità Access Point.

### LED Indicatori WiFi

| Stato LED | Significato |
|-----------|-------------|
| Lampeggio veloce (5Hz) | Ricerca rete WiFi |
| Lampeggio lento (1Hz) | Modalità Access Point attiva |
| 3 lampeggi | Connessione riuscita |
| Fisso | Errore connessione |

### Troubleshooting WiFi

#### Non trovo la rete "RetroPC_..."
- Verifica che l'ESP32 sia alimentato
- Attendi 10 secondi dopo l'accensione
- Riavvia l'ESP32

#### La WebApp non si carica
- Verifica di essere connesso alla rete corretta
- Prova `http://192.168.4.1` (non https)
- Disabilita VPN se attiva

#### Connessione instabile
- Avvicina l'ESP32 al router
- Verifica che la rete sia 2.4GHz (non 5GHz)
- Controlla RSSI in `/api/status`

---

## Troubleshooting

### VIC-20 mostra pattern ripetuto

- Verificare ordine ROM: BASIC, KERNAL e CHAR
- Verificare che le ROM siano nella cartella corretta `/roms/vic20/`
- BASIC ROM deve essere mappata a $C000-$DFFF (non $A000)

### VIC-20 caratteri speciali non funzionano (es: " diventa 2)

- **Causa:** LSHIFT mappato nella colonna sbagliata
- LSHIFT è in Col3 Row1, Z è in Col4 Row1

### VIC-20 cursore non lampeggia

- Verificare che timer IRQ sia abilitato
- LEDR[8] dovrebbe lampeggiare se timer funziona

### Apple I schermo tutto verde

- **Causa:** Bug nell'indice font
- Deve sottrarre 0x20 da ASCII: `char_index = current_char - 7'h20`

### Apple I non risponde alla tastiera

- Verificare che il core sia selezionato (4)
- Usare modalità tastiera (`k`)
- Caratteri convertiti automaticamente in uppercase
- Provare a inviare un secondo comando per "sbloccare" il primo

### ZX Spectrum caratteri mancanti

- Evitare `:` nei programmi BASIC test (causa conflitti)
- Usare `IF A=x THEN PRINT` invece di costrutti con GO TO

### ZX Spectrum sfondo nero

- Normale comportamento iniziale
- I colori sono forzati: paper=grigio, ink=nero

### RETURN/INVIO eseguito in ritardo

- **Causa:** Buffer UART non svuotato
- Il firmware invia NOP dopo RETURN per forzare flush
- Aggiornare all'ultima versione del firmware

### Compilazione fallisce per Logic Elements

- Già ottimizzato al 70% con architettura v8
- Rimuovere features non essenziali se necessario

### Compilazione fallisce per M9K

- Con architettura v8: 47% utilizzo, 96 blocchi liberi
- Se ancora problemi, verificare dimensione RAM/ROM

### ESP32 non comunica con FPGA

- Verificare connessioni TX/RX (sono incrociate)
- Verificare baud rate: 115200
- Controllare che GND sia in comune

---

## Cronologia Versioni

### v1.0 (Dicembre 2025) - Release Iniziale
- Sistema multi-core completo con 4 computer emulati
- Architettura condivisa RAM/ROM pool (47% M9K)
- Core "personality" modules separati
- Caricamento ROM dinamico da SD
- WebApp per controllo remoto
- Test BASIC automatizzati
- Debug LED e HEX display

#### Sviluppo interno:
- Fix VIC-20: VIA2 tastiera, LSHIFT, BASIC ROM address
- Fix Apple I: font index, scroll, keyboard
- Fix ZX Spectrum: colori, token BASIC
- Ottimizzazione risorse FPGA

---

## Test Rapido

```bash
# 1. Collegare ESP32 e aprire Serial Monitor (115200 baud)

# 2. Verificare comunicazione
p                    # Deve rispondere "PONG"

# 3. Selezionare un core
1                    # Carica C64

# 4. Attendere caricamento ROM
# (LEDR[3] lampeggia durante caricamento)

# 5. Test BASIC
t                    # Esegue test automatico

# 6. Modalità tastiera
k                    # Entra in keyboard mode
PRINT "HELLO"        # Digita comando
[INVIO]              # Esegue
~                    # Esce da keyboard mode
```

---

## Possibili Espansioni Future

- 🎮 **NES** (6502 + PPU)
- 🕹️ **Atari 2600** (6507)
- 💾 **MSX** (Z80)
- 🖥️ **Amstrad CPC** (Z80)
- 🎹 **Audio SID** (per C64)

---

## Licenza

Progetto per tesi universitaria.  
Università Telematica Mercatorum - Ingegneria Gestionale
Third-party HDL cores and trademark/ROM notices are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

## Contatti

**Angelo Arato**  
Tesi di Laurea in Ingegneria Gestionale  
Dicembre 2025
