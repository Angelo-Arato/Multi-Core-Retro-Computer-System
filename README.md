# Architettura Ibrida FPGA/MCU per Retro Computer 8-bit

## Tesi Sperimentale - Ingegneria Industriale
**Autore:** Angelo  
**Anno:** 2025/2026

## Descrizione
Sistema multi-core FPGA per emulazione hardware di 6 computer storici 8-bit.

### Computer Supportati
1. **Commodore 64** (CPU 6510, VIC-II, SID)
2. **VIC-20** (CPU 6502, VIC)
3. **Commodore 16** (CPU 7501, TED)
4. **ZX Spectrum 48K** (CPU Z80, ULA)
5. **Apple II** (CPU 6502)
6. **Atari 800** (CPU 6502, ANTIC, GTIA, POKEY)

## Hardware Necessario
- DE10-Lite FPGA Board (~150€)
- ESP32-DevKitC V4 (~10€)
- Monitor VGA
- Tastiera USB
- SD Card 8GB+
- Cavi jumper

## Collegamenti Hardware
```
DE10-Lite → ESP32
─────────────────
GPIO_0[0] (TX) → GPIO16 (RX)
GPIO_0[1] (RX) ← GPIO17 (TX)
GND ─ GND comune
```

## Quick Start
1. Compila FPGA con Quartus Prime Lite
2. Programma ESP32 con Arduino IDE
3. Connetti WiFi: `RetroComputer` / `retro1234`
4. Browser: `http://192.168.4.1`
5. Seleziona computer e carica ROM

## Struttura Progetto
```
Multi-Core-Retro-Computer-System/
├── README.md
├── docs/           (documentazione)
├── fpga/           (codice Verilog)
├── esp32/          (codice Arduino/C++)
├── scripts/        (test e build)
└── roms/           (directory ROM - vuota)
```

## Documentazione
- `docs/01_hardware_connections.md` - Schema completo
- `docs/02_build_guide_fpga.md` - Build FPGA
- `docs/03_build_guide_esp32.md` - Build ESP32
- `docs/04_user_manual.md` - Manuale utente

## Licenza
MIT License

**IMPORTANTE:** ROM NON incluse. Procuratele legalmente.

## Versione
v1.0 - Novembre 2025