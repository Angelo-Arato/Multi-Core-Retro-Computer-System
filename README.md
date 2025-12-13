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

| Core | Sistema         | CPU  | RAM  | ROM  | Anno |
|------|-----------------|------|------|------|------|
| 0    | Test Pattern    |  -   |   -  |   -  |   -  |
| 1    | Commodore 64    | 6510 | 64KB | 20KB | 1982 |
| 2    | ZX Spectrum 48K | Z80  | 48KB | 16KB | 1982 |
| 3    | VIC-20          | 6502 | 8KB  | 20KB | 1980 |
| 4    | Apple I         | 6502 | 2KB  | 256B | 1976 |

---

## Architettura del Sistema

```
┌─────────────────────────────────────────────────────────────────┐
│                        ESP32-DevKitC                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐         │
│  │ WiFi/Web │  │ SD Card  │  │   TFT    │  │  Serial  │         │
│  │  Server  │  │  Reader  │  │ Display  │  │ Console  │         │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘         │
│       └─────────────┴─────────────┴─────────────┘               │
│                           │                                     │
│                      [UART 115200]                              │
└───────────────────────────┼─────────────────────────────────────┘
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
│  │ ┌───┐   ┌─────┐   ┌────────┐   ┌──────┐  ┌───────┐      │   │
│  │ │C64│   │VIC20│   │Spectrum│   │Apple1│  │ROM    │      │   │
│  │ │   │   │     │   │        │   │      │  │Loader │      │   │
│  │ └───┘   └─────┘   └────────┘   └──────┘  └───────┘      │   │
│  │   │        │           │           │         │          │   │
│  │   └────────┴───────────┴───────────┴─────────┘          │   │
│  │                       │                                 │   │
│  │              ┌────────┴─────────┐                       │   │
│  │              │  Shared RAM/ROM  │                       │   │
│  │              │      Pool        │                       │   │
│  │              └──────────────────┘                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                    │
│              ┌────────────┴─────────────┐                      │
│              │      VGA Controller      │                      │
│              │    (640x480 @ 60Hz)      │                      │
│              └──────────────────────────┘                      │
└────────────────────────────────────────────────────────────────┘
```

---

## Utilizzo Risorse FPGA

### Architettura Condivisa (v8/v9)

```
Device: 10M50DAF484C7G (MAX 10)
Logic Elements:    ~35,000 / 49,760 (70%)
Memory Bits:      ~800,000 / 1,677,312 (48%)
M9K Blocks:            86 / 182 (47%)
M9K Disponibili:       96 (per espansioni future)
```

---

## Struttura File

### Directory Principale

```
/
├── rtl/                          # Sorgenti Verilog/VHDL
│   ├── retro_multicore_shared.v  # Top-level module
│   ├── c64_personality.v         # Core Commodore 64
│   ├── vic20_personality.v       # Core VIC-20
│   ├── spectrum_personality.v    # Core ZX Spectrum
│   ├── apple1_personality.v      # Core Apple I
│   ├── uart_controller.v         # Controller UART
│   ├── command_parser.v          # Parser comandi
│   ├── rom_loader.v              # Caricatore ROM dinamico
│   └── t65/                      # Soft-core 6502
│       ├── T65.vhd
│       ├── T65_ALU.vhd
│       ├── T65_MCode.vhd
│       ├── T65_Pack.vhd
│       └── T65_wrapper.v
│
├── esp32/                        # Firmware ESP32
│   ├── RetroPC_ESP32_v9.ino      # Firmware principale
│   └── data/                     # WebApp (SPIFFS)
│       ├── index.html
│       └── style.css
│
├── quartus/                      # Progetto Quartus
│   ├── retro_multicore_cpu.qpf   # File progetto
│   └── retro_multicore_cpu.qsf   # Settings
│
└── README.md
```

### Struttura SD Card

```
/sd
├── /roms
│   ├── /c64
│   │   ├── basic.901226-01.bin
│   │   ├── kernal.901227-03.bin
│   │   └── characters.901225-01.bin
│   ├── /spectrum
│   │   └── opense.rom
│   ├── /vic20
│   │   ├── characters.901460-03.bin
│   │   ├── basic.901486-01.bin
│   │   └── kernal.901486-07.bin
│   └── /apple1
│       └── (Woz Monitor integrato - nessuna ROM esterna necessaria)
│
├── /progs
│   ├── /c64
│   │   └── *.prg
│   ├── /vic20
│   │   └── *.prg
│   └── /spectrum
│       └── *.z80
│
└── /floppy
    └── *.d64
```

---

## Connessioni Hardware

### ESP32 ↔ FPGA (UART)

| ESP32       | FPGA (GPIO)       | Funzione     |
|-------------|-------------------|--------------|
| GPIO26 (TX) | GPIO[1] / PIN_W10 | ESP32 → FPGA |
| GPIO27 (RX) | GPIO[0] / PIN_V10 | FPGA → ESP32 |
| GND         | GND               | Massa comune |

---

## Comandi ESP32

### Selezione Sistema

| Comando | Sistema.        |
|---------|-----------------|
| `0`     | Test Pattern    |
| `1`.    | Commodore 64    |
| `2`     | ZX Spectrum 48K |
| `3`     | VIC-20          |
| `4`     | Apple I         |

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
| 1 | `characters.901460-03.bin` | $8000 (4KB) |
| 2 | `basic.901486-01.bin` | $C000 (8KB) |
| 3 | `kernal.901486-07.bin` | $E000 (8KB) |

**IMPORTANTE:** L'ordine è fondamentale! CHAR → BASIC → KERNAL

---

## Compilazione

### Quartus (FPGA)

1. Aprire `quartus/retro_multicore_cpu.qpf`
2. Processing → Start Compilation
3. Tools → Programmer → Start

### Arduino IDE (ESP32)

1. Installare board ESP32 (Espressif Systems)
2. Aprire `esp32/RetroPC_ESP32_v9.ino`
3. Selezionare board "ESP32 Dev Module"
4. Impostare Upload Speed: 921600
5. Upload

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

## WebApp

L'ESP32 espone una WebApp per controllo remoto via WiFi.

### Accesso

1. ESP32 crea AP WiFi o si connette a rete esistente
2. Accedere all'IP mostrato su Serial Monitor
3. Utilizzare interfaccia web per:
   - Selezione core
   - Invio comandi tastiera
   - Visualizzazione stato
   - Reset sistema

---

## Troubleshooting

### VIC-20 mostra pattern ripetuto

- Verificare ordine ROM: CHAR, BASIC, KERNAL
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

Con 96 M9K liberi disponibili, è possibile aggiungere:

- 🎮 **NES** (6502 + PPU)
- 🕹️ **Atari 2600** (6507)
- 💾 **MSX** (Z80)
- 🖥️ **Amstrad CPC** (Z80)
- 🎹 **Audio SID** (per C64)

---

## Licenza

Progetto per tesi universitaria.  
Università Telematica Mercatorum - Ingegneria Gestionale

---

## Contatti

**Angelo Arato**  
Tesi di Laurea in Ingegneria Gestionale  
Dicembre 2025
