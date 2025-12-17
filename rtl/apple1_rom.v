//==============================================================================
// APPLE I - WOZ MONITOR ROM (256 bytes)
//==============================================================================
// Ricreazione funzionale del monitor originale di Steve Wozniak
// Indirizzo: $FF00-$FFFF
//
// Comandi:
//   <addr>           - Imposta indirizzo corrente
//   <addr>.<addr>    - Visualizza range memoria
//   <addr>: <bb> ... - Deposita bytes in memoria
//   <addr>R          - Esegue da indirizzo
//
// Autore: Angelo Arato
// Per uso educativo - Tesi di laurea
//==============================================================================

module apple1_rom (
    input  wire        clk,
    input  wire [7:0]  addr,
    output reg  [7:0]  data
);

always @(posedge clk) begin
    case (addr)
        // --- RESET & INIT ---
        8'h00: data <= 8'hD8; // CLD
        8'h01: data <= 8'h58; // CLI
        8'h02: data <= 8'hA0; // LDY #$7F
        8'h03: data <= 8'h7F;
        8'h04: data <= 8'h8C; // STY $D012
        8'h05: data <= 8'h12;
        8'h06: data <= 8'hD0;
        8'h07: data <= 8'hA9; // LDA #$5C ('\')
        8'h08: data <= 8'h5C;
        8'h09: data <= 8'h20; // JSR ECHO
        8'h0A: data <= 8'hEF;
        8'h0B: data <= 8'hFF;

        // --- GETLINE ($FF0C) ---
        8'h0C: data <= 8'hA9; // LDA #$8D (CR)
        8'h0D: data <= 8'h8D;
        8'h0E: data <= 8'h20; // JSR ECHO
        8'h0F: data <= 8'hEF;
        8'h10: data <= 8'hFF;
        8'h11: data <= 8'hA2; // LDX #$01
        8'h12: data <= 8'h01;
        // NEXTCHAR ($FF13)
        8'h13: data <= 8'h2C; // BIT $D011
        8'h14: data <= 8'h11;
        8'h15: data <= 8'hD0;
        8'h16: data <= 8'h10; // BPL NEXTCHAR
        8'h17: data <= 8'hFB;
        8'h18: data <= 8'hAD; // LDA $D010
        8'h19: data <= 8'h10;
        8'h1A: data <= 8'hD0;
        8'h1B: data <= 8'hC9; // CMP #$DF
        8'h1C: data <= 8'hDF;
        8'h1D: data <= 8'h90; // BCC CONVERT
        8'h1E: data <= 8'h02;
        8'h1F: data <= 8'h29; // AND #$5F
        8'h20: data <= 8'h5F;
        // CONVERT ($FF21)
        8'h21: data <= 8'h95; // STA $00,X
        8'h22: data <= 8'h00;
        8'h23: data <= 8'h20; // JSR ECHO
        8'h24: data <= 8'hEF;
        8'h25: data <= 8'hFF;
        8'h26: data <= 8'hC9; // CMP #$8D (CR)
        8'h27: data <= 8'h8D;
        8'h28: data <= 8'hF0; // BEQ PARSE
        8'h29: data <= 8'h10;
        8'h2A: data <= 8'hC9; // CMP #$9B (ESC)
        8'h2B: data <= 8'h9B;
        8'h2C: data <= 8'hF0; // BEQ GETLINE
        8'h2D: data <= 8'hDD;
        8'h2E: data <= 8'hE8; // INX
        8'h2F: data <= 8'hE0; // CPX #$28
        8'h30: data <= 8'h28;
        8'h31: data <= 8'h90; // BCC NEXTCHAR
        8'h32: data <= 8'hE0; // Offset corretto (-32)
        8'h33: data <= 8'hD0; // BNE GETLINE
        8'h34: data <= 8'hD6;

        8'h35: data <= 8'hEA; 
        8'h36: data <= 8'hEA;
        8'h37: data <= 8'hEA;
        8'h38: data <= 8'hEA;
        8'h39: data <= 8'hEA;

        // --- PARSE ($FF3A) ---
        8'h3A: data <= 8'hA0; // LDY #$00
        8'h3B: data <= 8'h00;
        8'h3C: data <= 8'hA9; // LDA #$00
        8'h3D: data <= 8'h00;
        8'h3E: data <= 8'hAA; // TAX
        // SETSTOR
        8'h3F: data <= 8'h86; // STX $27
        8'h40: data <= 8'h27;
        // NEXTITEM ($FF41)
        8'h41: data <= 8'hB9; // LDA $0001,Y
        8'h42: data <= 8'h01;
        8'h43: data <= 8'h00;
        8'h44: data <= 8'hC8; // INY
        8'h45: data <= 8'hC9; // CMP #$8D
        8'h46: data <= 8'h8D;
        8'h47: data <= 8'hF0; // BEQ GETLINE
        8'h48: data <= 8'hC2;
        8'h49: data <= 8'hC9; // CMP #'.'
        8'h4A: data <= 8'hAE;
        8'h4B: data <= 8'hF0; // BEQ SETMODE
        8'h4C: data <= 8'h29; 
        8'h4D: data <= 8'hC9; // CMP #':'
        8'h4E: data <= 8'hBA;
        8'h4F: data <= 8'hF0; // BEQ STORE
        8'h50: data <= 8'h35;
        8'h51: data <= 8'hC9; // CMP #'R'
        8'h52: data <= 8'hD2;
        8'h53: data <= 8'hF0; // BEQ RUN
        8'h54: data <= 8'h3D;
        8'h55: data <= 8'hC9; // CMP #' '
        8'h56: data <= 8'hA0;
        // FIX CRITICO: Offset per tornare a NEXTITEM ($FF41)
        // PC corrente $FF59. Target $FF41. Offset $E8 (-24)
        8'h57: data <= 8'hF0; // BEQ NEXTITEM
        8'h58: data <= 8'hE7; // Offset corretto
        
        // HEX PARSING
        8'h59: data <= 8'h38; // SEC
        8'h5A: data <= 8'hE9; // SBC #'0'
        8'h5B: data <= 8'hB0;
        8'h5C: data <= 8'hC9; 
        8'h5D: data <= 8'h0A;
        8'h5E: data <= 8'h90; // BCC DIGIT
        8'h5F: data <= 8'h06;
        8'h60: data <= 8'h69; // ADC #$08
        8'h61: data <= 8'h08;
        8'h62: data <= 8'hC9; // CMP #$10
        8'h63: data <= 8'h10;
        // FIX CRITICO: BCS NEXTITEM ($FF41)
        // PC corrente $FF66. Target $FF41. Offset $DB (-37)
        8'h64: data <= 8'hB0; // BCS NEXTITEM
        8'h65: data <= 8'hDA; // Offset corretto
        
        // DIGIT
        8'h66: data <= 8'h0A; // ASL A
        8'h67: data <= 8'h0A; 
        8'h68: data <= 8'h0A;
        8'h69: data <= 8'h0A;
        8'h6A: data <= 8'hA2; // LDX #$04
        8'h6B: data <= 8'h04;
        // HEXSHIFT
        8'h6C: data <= 8'h0A; // ASL A
        8'h6D: data <= 8'h26; // ROL $24
        8'h6E: data <= 8'h24;
        8'h6F: data <= 8'h26; // ROL $25
        8'h70: data <= 8'h25;
        8'h71: data <= 8'hCA; // DEX
        8'h72: data <= 8'hD0; // BNE HEXSHIFT
        8'h73: data <= 8'hF8;
        // BEQ NEXTITEM ($FF41)
        8'h74: data <= 8'hF0; 
        8'h75: data <= 8'hCB; // Offset corretto

        // SETMODE
        8'h76: data <= 8'hA5; // LDA $24
        8'h77: data <= 8'h24;
        8'h78: data <= 8'h85; // STA $28
        8'h79: data <= 8'h28;
        8'h7A: data <= 8'hA5; // LDA $25
        8'h7B: data <= 8'h25;
        8'h7C: data <= 8'h85; // STA $29
        8'h7D: data <= 8'h29;
        // FIX CRITICO: BNE NEXTITEM ($FF41)
        // PC corrente $FF80. Target $FF41. Offset $C1 (-63)
        8'h7E: data <= 8'hD0; 
        8'h7F: data <= 8'hC1; // Offset corretto

        8'h80: data <= 8'hEA;
        8'h81: data <= 8'hEA;
        8'h82: data <= 8'hEA;
        8'h83: data <= 8'hEA;
        8'h84: data <= 8'hEA;

        // STORE ($FF85)
        8'h85: data <= 8'hB9; // LDA $0001,Y
        8'h86: data <= 8'h01;
        8'h87: data <= 8'h00;
        8'h88: data <= 8'hC8; // INY
        8'h89: data <= 8'h49; // EOR #$B0
        8'h8A: data <= 8'hB0;
        8'h8B: data <= 8'hC9; // CMP #$0A
        8'h8C: data <= 8'h0A;
        8'h8D: data <= 8'h90; // BCC STOREHEX1
        8'h8E: data <= 8'h02;
        8'h8F: data <= 8'h69; // ADC #$08
        8'h90: data <= 8'h08;
        // STOREHEX1
        8'h91: data <= 8'h0A; // ASL A
        8'h92: data <= 8'h0A;
        8'h93: data <= 8'h0A;
        8'h94: data <= 8'h0A;
        8'h95: data <= 8'h85; // STA $26
        8'h96: data <= 8'h26;
        8'h97: data <= 8'hB9; // LDA $0001,Y
        8'h98: data <= 8'h01;
        8'h99: data <= 8'h00;
        8'h9A: data <= 8'hC8; // INY
        8'h9B: data <= 8'h49; // EOR #$B0
        8'h9C: data <= 8'hB0;
        8'h9D: data <= 8'hC9; // CMP #$0A
        8'h9E: data <= 8'h0A;
        8'h9F: data <= 8'h90; // BCC STOREHEX2
        8'hA0: data <= 8'h02;
        8'hA1: data <= 8'h69; // ADC #$08
        8'hA2: data <= 8'h08;
        // STOREHEX2
        8'hA3: data <= 8'h05; // ORA $26
        8'hA4: data <= 8'h26;
        8'hA5: data <= 8'h92; // STA ($24)
        8'hA6: data <= 8'h24;
        8'hA7: data <= 8'hE6; // INC $24
        8'hA8: data <= 8'h24;
        8'hA9: data <= 8'hD0; // BNE NEXTITEM
        // FIX: $FF41 - $FFAB = $96 (-106)
        8'hAA: data <= 8'h96; 
        8'hAB: data <= 8'hE6; // INC $25
        8'hAC: data <= 8'h25;
        8'hAD: data <= 8'hD0; // BNE NEXTITEM
        8'hAE: data <= 8'h91; 
        
        8'hAF: data <= 8'hEA;

        // PRDATA ($FFB0)
        8'hB0: data <= 8'hA9; // LDA #$A0
        8'hB1: data <= 8'hA0;
        8'hB2: data <= 8'h20; // JSR ECHO
        8'hB3: data <= 8'hEF;
        8'hB4: data <= 8'hFF;
        8'hB5: data <= 8'hB2; // LDA ($24)
        8'hB6: data <= 8'h24;
        8'hB7: data <= 8'h20; // JSR PRBYTE
        8'hB8: data <= 8'hDC;
        8'hB9: data <= 8'hFF;
        
        // PRNEXT
        8'hBA: data <= 8'hA5; // LDA $24
        8'hBB: data <= 8'h24;
        8'hBC: data <= 8'hC5; // CMP $28
        8'hBD: data <= 8'h28;
        8'hBE: data <= 8'hA5; // LDA $25
        8'hBF: data <= 8'h25;
        8'hC0: data <= 8'hE5; // SBC $29
        8'hC1: data <= 8'h29;
        8'hC2: data <= 8'hB0; // BCS GETLINE
        8'hC3: data <= 8'h47;
        8'hC4: data <= 8'hE6; // INC $24
        8'hC5: data <= 8'h24;
        8'hC6: data <= 8'hD0; // BNE PRMOD8
        8'hC7: data <= 8'h02;
        8'hC8: data <= 8'hE6; // INC $25
        8'hC9: data <= 8'h25;
        // PRMOD8
        8'hCA: data <= 8'hA5;
        8'hCB: data <= 8'h24;
        8'hCC: data <= 8'h29; // AND #$07
        8'hCD: data <= 8'h07;
        8'hCE: data <= 8'hD0; // BNE PRDATA
        8'hCF: data <= 8'hE0; // Offset PRDATA
        
        // PRADDR
        8'hD0: data <= 8'hA9;
        8'hD1: data <= 8'h8D;
        8'hD2: data <= 8'h20; // JSR ECHO
        8'hD3: data <= 8'hEF;
        8'hD4: data <= 8'hFF;
        8'hD5: data <= 8'hA5;
        8'hD6: data <= 8'h25;
        8'hD7: data <= 8'h20; // JSR PRBYTE
        8'hD8: data <= 8'hDC;
        8'hD9: data <= 8'hFF;
        8'hDA: data <= 8'hA5;
        8'hDB: data <= 8'h24;
        // PRBYTE
        8'hDC: data <= 8'h48;
        8'hDD: data <= 8'h4A;
        8'hDE: data <= 8'h4A;
        8'hDF: data <= 8'h4A;
        8'hE0: data <= 8'h4A;
        8'hE1: data <= 8'h20; // JSR PRHEX
        8'hE2: data <= 8'hE5;
        8'hE3: data <= 8'hFF;
        8'hE4: data <= 8'h68;
        // PRHEX
        8'hE5: data <= 8'h29;
        8'hE6: data <= 8'h0F;
        8'hE7: data <= 8'h09;
        8'hE8: data <= 8'hB0;
        8'hE9: data <= 8'hC9;
        8'hEA: data <= 8'hBA;
        8'hEB: data <= 8'h90; // BCC ECHO
        8'hEC: data <= 8'h02;
        8'hED: data <= 8'h69;
        8'hEE: data <= 8'h06;
        // ECHO
        8'hEF: data <= 8'h2C; // BIT $D012
        8'hF0: data <= 8'h12;
        8'hF1: data <= 8'hD0;
        8'hF2: data <= 8'h30; // BMI ECHO
        8'hF3: data <= 8'hFB; 
        8'hF4: data <= 8'h8D; // STA $D012
        8'hF5: data <= 8'h12;
        8'hF6: data <= 8'hD0;
        8'hF7: data <= 8'h60; // RTS

        // VECTORS
        8'hF8: data <= 8'h6C;
        8'hF9: data <= 8'h24;
        8'hFA: data <= 8'h00;
        8'hFB: data <= 8'h00;
        8'hFC: data <= 8'h00;
        8'hFD: data <= 8'hFF;
        8'hFE: data <= 8'h00;
        8'hFF: data <= 8'hFF;
        
        default: data <= 8'hEA;
    endcase
end

endmodule