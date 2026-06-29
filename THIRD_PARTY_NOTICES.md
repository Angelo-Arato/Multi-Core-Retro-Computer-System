# Third-Party Notices

This file provides a consolidated attribution and intellectual-property notice for the **Multi-Core Retro Computer System** repository.

The main project license applies only to original code, documentation, schematics, firmware, scripts and other materials authored by **Angelo Arato**, unless a file, folder or source header states otherwise.

Some files in this repository are third-party or derivative components and remain subject to their own copyright notices, license terms and disclaimers. Those notices must be preserved.

This file is intended to clarify attribution. It does not replace the original license headers contained in third-party source files.

---

## 1. Project Code Authored by Angelo Arato

Unless otherwise stated in a specific file, folder or source header, original project materials authored by Angelo Arato are distributed under the license provided in the repository LICENSE file.

This includes, where original to the project:

* top-level integration logic;
* FPGA system integration modules;
* ESP32 controller firmware;
* UART command/control logic;
* ROM loading logic;
* project documentation;
* configuration files;
* educational/demo code written specifically for this project.

Third-party components listed below are not relicensed by the main project license.

---

## 2. T65 65xx-Compatible CPU Core

**Component:** T65 / 65xx-compatible microprocessor core
**Repository path:** `rtl/t65/`
**Typical files:**

* `rtl/t65/T65.vhd`
* `rtl/t65/T65_ALU.vhd`
* `rtl/t65/T65_MCode.vhd`
* `rtl/t65/T65_Pack.vhd`
* `rtl/t65/T65_wrapper.v`

**Authors / copyright holders:** as stated in the original source-file headers, including Daniel Wallner, Mike Johnson, Wolfgang Scherr, Morten Leikvoll and other contributors.

**License:** permissive BSD-style license as stated in the original T65 source-file headers.

**Notice:** The original copyright notices, license conditions and warranty disclaimers in the T65 source files must be retained. If this project is distributed in source form, keep those headers intact. If a synthesized form, bitstream, product, documentation package or other derived distribution is provided, reproduce the applicable T65 notices, conditions and disclaimers in the accompanying documentation or distribution materials.

The names of the original authors and contributors must not be used to endorse or promote derived products without prior written permission.

---

## 3. T80 Z80-Compatible CPU Core

**Component:** T80 / Z80-compatible microprocessor core
**Repository path:** `rtl/t80/`
**Typical files:**

* `rtl/t80/T80.vhd`
* `rtl/t80/T80a.vhd`
* `rtl/t80/T80_ALU.vhd`
* `rtl/t80/T80_MCode.vhd`
* `rtl/t80/T80_Pack.vhd`
* `rtl/t80/T80_Reg.vhd`
* `rtl/t80/T80_wrapper.v`

**Authors / copyright holders:** as stated in the original source-file headers, including Daniel Wallner, Sorgelig and other contributors.

**License:** permissive BSD-style license as stated in the original T80 source-file headers.

**Notice:** The original copyright notices, license conditions and warranty disclaimers in the T80 source files must be retained. If this project is distributed in source form, keep those headers intact. If a synthesized form, bitstream, product, documentation package or other derived distribution is provided, reproduce the applicable T80 notices, conditions and disclaimers in the accompanying documentation or distribution materials.

The names of the original authors and contributors must not be used to endorse or promote derived products without prior written permission.

---

## 4. ESP32 / Arduino / External Library Dependencies

The ESP32 firmware may depend on ESP32 board-support packages, Arduino framework components and/or external libraries installed by the developer environment.

Those packages are not relicensed by this repository. They remain subject to their respective upstream licenses and notices.

If any third-party library source code is copied directly into this repository in the future, its license and copyright notice should be added to this file and preserved in the corresponding source files.

---

## 5. ROMs, Firmware Images and Proprietary System Software

This repository is intended as an educational and technical hardware-emulation / hardware-recreation project.

It does **not** include proprietary ROM files, copyrighted firmware images, operating-system ROMs, BASIC ROMs, KERNAL ROMs, character ROMs, monitor ROMs or other original system software from historical computers.

Users are responsible for obtaining any required ROM or firmware files legally from original hardware they own, licensed distributors or other lawful sources.

The project does not condone or support piracy.

---

## 6. Apple I Monitor / Font / ROM-Related HDL Files

Files such as `rtl/apple1_rom.v` and `rtl/apple1_font_rom.v`, if present, should be treated with particular care because historical monitor ROMs, font ROMs and firmware images may be subject to third-party rights.

These files are intended to be used only as original educational / functional HDL implementations or placeholders, unless a separate written authorization or public-domain status is clearly documented.

If any file contains byte-for-byte or substantially derived data from an original proprietary ROM, firmware image, font ROM or monitor program, that file should either be replaced with an original clean-room implementation or accompanied by clear written permission and a specific notice in this file.

---

## 7. Trademarks and Historical System Names

Names such as **Commodore**, **Commodore 64**, **C64**, **VIC-20**, **ZX Spectrum**, **Apple**, **Apple I**, **Atari** and other historical computer or company names may be trademarks or registered trademarks of their respective owners.

Any use of those names in this repository is intended only for descriptive, historical, educational or compatibility-reference purposes.

This project is not affiliated with, sponsored by, endorsed by or officially connected to Commodore, Apple, Sinclair, Atari or any other trademark owner, unless expressly stated in a written agreement.

No trademark, logo, trade dress, original packaging artwork or proprietary branding from any third party is licensed or granted by this repository.

---

## 8. Future Contributions

Future contributors should:

* clearly mark any third-party code, HDL, firmware, ROM data, images, documentation or other materials;
* preserve original copyright and license headers;
* add new third-party components to this file;
* avoid adding proprietary ROMs or firmware images;
* avoid using third-party trademarks as project branding;
* document whether a file is original, third-party, derived, clean-room or placeholder material.

---

## 9. No Legal Advice

This file is provided as a practical attribution and compliance aid for the repository. It is not legal advice. For commercial distribution, manufacturing, licensing, trademark use or inclusion in a product, consult a qualified intellectual-property professional.
