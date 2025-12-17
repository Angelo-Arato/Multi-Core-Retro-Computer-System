//==============================================================================
// VIC-20 LITE - Versione ottimizzata per DE10-Lite
// Con tastiera funzionante e cursore lampeggiante
//==============================================================================
module vic20_complete (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        enable,
    input  wire        res_mode,      // 0=640x480, 1=800x600
    output reg  [3:0]  vga_r, vga_g, vga_b,
    output wire        vga_hs, vga_vs,
    input  wire [7:0]  key_code,
    input  wire        key_strobe,
    output wire        audio_out,
    // ROM loading
    input  wire        rom_load_en,
    input  wire [15:0] rom_load_addr,
    input  wire [7:0]  rom_load_data,
    input  wire        rom_load_wr,
    input  wire [1:0]  rom_bank,
    // PRG loading (programmi BASIC/ML)
    input  wire        prg_load_en,
    input  wire [15:0] prg_load_addr,
    input  wire [7:0]  prg_load_data,
    input  wire        prg_load_wr,
    // Debug
    output wire [15:0] debug_pc,
    output wire [7:0]  debug_a,
    output wire        debug_irq
);

//==============================================================================
// BOOT DELAY - Attende che le ROM siano caricate
//==============================================================================
reg [23:0] boot_delay;
wire boot_done = boot_delay[23];

always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
        boot_delay <= 24'd0;
    else if (!enable)
        boot_delay <= 24'd0;
    else if (!boot_done)
        boot_delay <= boot_delay + 1'b1;
end

//==============================================================================
// CPU CLOCK - 1.1MHz da 50MHz (divisione per 45)
//==============================================================================
reg [5:0] clk_div;
wire cpu_clk_en = (clk_div == 6'd0) && enable && boot_done;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) 
        clk_div <= 6'd0;
    else if (enable && boot_done)
        clk_div <= (clk_div >= 6'd44) ? 6'd0 : clk_div + 6'd1;
end

//==============================================================================
// CPU 6502
//==============================================================================
wire [15:0] cpu_addr;
wire [7:0] cpu_dout;
reg [7:0] cpu_din;
wire cpu_we;

wire cpu_reset_n = reset_n && boot_done;

// IRQ dalla VIA1
wire irq_n;

T65_wrapper cpu (
    .clk(clk),
    .reset_n(cpu_reset_n),
    .enable(cpu_clk_en),
    .addr(cpu_addr),
    .data_in(cpu_din),
    .data_out(cpu_dout),
    .we(cpu_we),
    .irq_n(irq_n),
    .nmi_n(1'b1),
    .rdy(1'b1)
);

wire cpu_wr = cpu_we & cpu_clk_en;
assign debug_pc = cpu_addr;
assign debug_a = cpu_dout;
assign debug_irq = ~irq_n;

//==============================================================================
// MEMORY DECODE
//==============================================================================
wire sel_ram0   = (cpu_addr[15:10] == 6'b000000);                    // $0000-$03FF (1KB)
wire sel_ram1   = (cpu_addr[15:12] == 4'h1);                         // $1000-$1FFF (4KB)
wire sel_char   = (cpu_addr[15:12] == 4'h8);                         // $8000-$8FFF
wire sel_vic    = (cpu_addr[15:4]  == 12'h900);                      // $9000-$900F
wire sel_via1   = (cpu_addr[15:4]  == 12'h911);                      // $9110-$911F
wire sel_via2   = (cpu_addr[15:4]  == 12'h912);                      // $9120-$912F
wire sel_color  = (cpu_addr[15:10] == 6'b100101);                    // $9400-$97FF
wire sel_basic  = (cpu_addr[15:13] == 3'b110);                       // $C000-$DFFF
wire sel_kernal = (cpu_addr[15:13] == 3'b111);                       // $E000-$FFFF

//==============================================================================
// VIA1 - Timer T1 per IRQ (necessario per cursore lampeggiante)
//==============================================================================
reg [15:0] via1_t1_counter;
reg [15:0] via1_t1_latch;
reg [7:0]  via1_acr;           // Auxiliary Control Register
reg [7:0]  via1_ifr;           // Interrupt Flag Register
reg [7:0]  via1_ier;           // Interrupt Enable Register
reg [7:0]  via1_ora;           // Output Register A (keyboard column select)
reg [7:0]  via1_orb;           // Output Register B
reg [7:0]  via1_ddra;          // Data Direction Register A
reg [7:0]  via1_ddrb;          // Data Direction Register B
reg        via1_t1_running;    // Timer running flag

// IRQ definito più sotto dopo VIA2

// VIA1 Timer e registri
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        via1_t1_counter <= 16'h4000;
        via1_t1_latch <= 16'h4000;  // ~16ms @ 1.1MHz
        via1_acr <= 8'h40;          // T1 free-running mode by default
        via1_ifr <= 8'h00;
        via1_ier <= 8'h40;          // Enable T1 interrupt by default!
        via1_ora <= 8'hFF;
        via1_orb <= 8'hFF;
        via1_ddra <= 8'hFF;         // Port A = all outputs (keyboard columns)
        via1_ddrb <= 8'h00;         // Port B = all inputs
        via1_t1_running <= 1'b1;    // Start running immediately!
    end else if (cpu_clk_en && enable) begin
        // Timer T1 SEMPRE decrementa quando running
        if (via1_t1_running) begin
            if (via1_t1_counter == 16'h0000) begin
                via1_ifr[6] <= 1'b1;  // Set T1 interrupt flag
                if (via1_acr[6]) begin
                    // Free-running mode: ricarica e continua
                    via1_t1_counter <= via1_t1_latch;
                end else begin
                    // One-shot mode: ferma il timer
                    via1_t1_running <= 1'b0;
                end
            end else begin
                via1_t1_counter <= via1_t1_counter - 1'd1;
            end
        end
        
        // Register writes
        if (cpu_we && sel_via1) begin
            case (cpu_addr[3:0])
                4'h0: via1_orb <= cpu_dout;             // ORB
                4'h1: via1_ora <= cpu_dout;             // ORA
                4'h2: via1_ddrb <= cpu_dout;            // DDRB
                4'h3: via1_ddra <= cpu_dout;            // DDRA
                4'h4: via1_t1_latch[7:0] <= cpu_dout;   // T1C-L write: write to latch
                4'h5: begin  // T1C-H write: load counter, START timer, clear IFR
                    via1_t1_counter <= {cpu_dout, via1_t1_latch[7:0]};
                    via1_t1_running <= 1'b1;  // START!
                    via1_ifr[6] <= 1'b0;
                end
                4'h6: via1_t1_latch[7:0] <= cpu_dout;   // T1L-L
                4'h7: begin  // T1L-H write: also clears interrupt
                    via1_t1_latch[15:8] <= cpu_dout;
                    via1_ifr[6] <= 1'b0;
                end
                4'hB: via1_acr <= cpu_dout;             // ACR
                4'hD: via1_ifr <= via1_ifr & ~cpu_dout; // IFR: write 1 to clear
                4'hE: begin  // IER
                    if (cpu_dout[7])
                        via1_ier <= via1_ier | (cpu_dout & 8'h7F);
                    else
                        via1_ier <= via1_ier & ~(cpu_dout & 8'h7F);
                end
            endcase
        end
        
        // Clear T1 interrupt on T1C-L read
        if (!cpu_we && sel_via1 && cpu_addr[3:0] == 4'h4) begin
            via1_ifr[6] <= 1'b0;
        end
    end
end

//==============================================================================
// KEYBOARD HANDLING - VIC-20 Keyboard Matrix
//==============================================================================
// VIC-20 usa VIA2 per la tastiera (NON VIA1!):
// - VIA2 Port B ($9120) = OUTPUT, seleziona quale COLONNA scansionare (bit=0)
// - VIA2 Port A ($9121) = INPUT, legge quali RIGHE hanno tasti premuti (bit=0)
//
// Matrice VIC-20 (8 righe x 8 colonne) - DA LEMON64:
// Write to Port B($9120)column / Read from Port A($9121)row
//        Col7   Col6   Col5   Col4   Col3   Col2   Col1   Col0
// Row7:  F7     F5     F3     F1     CDN    CRT    RET    DEL
// Row6:  HOME   ^      =      RSHIFT /      ;      *      £
// Row5:  -      @      :      .      ,      L      P      +
// Row4:  0      O      K      M      N      J      I      9
// Row3:  8      U      H      B      V      G      Y      7
// Row2:  6      T      F      C      X      D      R      5
// Row1:  4      E      S      Z      LSHIFT A      W      3
// Row0:  2      Q      C=     SPACE  STOP   CTRL   <-     1
//==============================================================================

reg [7:0] key_matrix [0:7];  // key_matrix[COL] = ROWS (bit=0 = pressed)
reg [23:0] key_timer;

// Sincronizzazione key_strobe semplificata
reg key_strobe_r1, key_strobe_r2;
wire key_strobe_edge = key_strobe_r1 && !key_strobe_r2;

integer i;
initial begin
    for (i = 0; i < 8; i = i + 1) key_matrix[i] = 8'hFF;
    key_timer = 0;
end

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        key_strobe_r1 <= 1'b0;
        key_strobe_r2 <= 1'b0;
    end else begin
        key_strobe_r1 <= key_strobe;
        key_strobe_r2 <= key_strobe_r1;
    end
end

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        key_timer <= 0;
        for (i = 0; i < 8; i = i + 1) key_matrix[i] <= 8'hFF;
    end
    else begin
        // Decrementa timer
        if (key_timer > 0)
            key_timer <= key_timer - 1'd1;
        
        // Quando timer scade, rilascia tutti i tasti
        if (key_timer == 1) begin
            key_matrix[0] <= 8'hFF;
            key_matrix[1] <= 8'hFF;
            key_matrix[2] <= 8'hFF;
            key_matrix[3] <= 8'hFF;
            key_matrix[4] <= 8'hFF;
            key_matrix[5] <= 8'hFF;
            key_matrix[6] <= 8'hFF;
            key_matrix[7] <= 8'hFF;
        end
        
        // Nuovo tasto premuto (usa edge sincronizzato!)
        if (key_strobe_edge) begin
            key_timer <= 24'd2500000;  // ~50ms @ 50MHz (più lungo!)
            
            // Reset matrice prima
            key_matrix[0] <= 8'hFF;
            key_matrix[1] <= 8'hFF;
            key_matrix[2] <= 8'hFF;
            key_matrix[3] <= 8'hFF;
            key_matrix[4] <= 8'hFF;
            key_matrix[5] <= 8'hFF;
            key_matrix[6] <= 8'hFF;
            key_matrix[7] <= 8'hFF;
            
            // Poi imposta il tasto - NUOVO MAPPING da Lemon64!
            // key_matrix[COLONNA] bit RIGA = 0 quando premuto
            case (key_code)
                // MAPPING CORRETTO DA LEMON64!
                // Write to Port B($9120)column / Read from Port A($9121)row
                //        Col7   Col6   Col5   Col4   Col3   Col2   Col1   Col0
                // Row7:  F7     F5     F3     F1     CDN    CRT    RET    DEL
                // Row6:  HOME   ^      =      RSHIFT /      ;      *      £
                // Row5:  -      @      :      .      ,      L      P      +
                // Row4:  0      O      K      M      N      J      I      9
                // Row3:  8      U      H      B      V      G      Y      7
                // Row2:  6      T      F      C      X      D      R      5
                // Row1:  4      E      S      Z      LSHIFT A      W      3
                // Row0:  2      Q      C=     SPACE  STOP   CTRL   <-     1
                
                // Column 0: 1,3,5,7,9,+,£,DEL (dal basso verso l'alto)
                8'h31: key_matrix[0] <= 8'b11111110;  // '1' -> Row0
                8'h33: key_matrix[0] <= 8'b11111101;  // '3' -> Row1
                8'h35: key_matrix[0] <= 8'b11111011;  // '5' -> Row2
                8'h37: key_matrix[0] <= 8'b11110111;  // '7' -> Row3
                8'h39: key_matrix[0] <= 8'b11101111;  // '9' -> Row4
                8'h2B: key_matrix[0] <= 8'b11011111;  // '+' -> Row5
                // £ = Row6 (non mappato da ASCII standard)
                8'h08, 8'h7F: key_matrix[0] <= 8'b01111111;  // DEL -> Row7
                
                // Column 1: <-,W,R,Y,I,P,*,RET
                // <- = Row0 (left arrow, non mappato)
                8'h57, 8'h77: key_matrix[1] <= 8'b11111101;  // 'W' -> Row1
                8'h52, 8'h72: key_matrix[1] <= 8'b11111011;  // 'R' -> Row2
                8'h59, 8'h79: key_matrix[1] <= 8'b11110111;  // 'Y' -> Row3
                8'h49, 8'h69: key_matrix[1] <= 8'b11101111;  // 'I' -> Row4
                8'h50, 8'h70: key_matrix[1] <= 8'b11011111;  // 'P' -> Row5
                8'h2A: key_matrix[1] <= 8'b10111111;         // '*' -> Row6
                8'h0D, 8'h0A: key_matrix[1] <= 8'b01111111;  // RETURN -> Row7
                
                // Column 2: CTRL,A,D,G,J,L,;,CRS-R
                // CTRL = Row0 (non mappato)
                8'h41, 8'h61: key_matrix[2] <= 8'b11111101;  // 'A' -> Row1
                8'h44, 8'h64: key_matrix[2] <= 8'b11111011;  // 'D' -> Row2
                8'h47, 8'h67: key_matrix[2] <= 8'b11110111;  // 'G' -> Row3
                8'h4A, 8'h6A: key_matrix[2] <= 8'b11101111;  // 'J' -> Row4
                8'h4C, 8'h6C: key_matrix[2] <= 8'b11011111;  // 'L' -> Row5
                8'h3B: key_matrix[2] <= 8'b10111111;         // ';' -> Row6
                // CRS-R = Row7 (cursor right)
                
                // Column 3: STOP,LSHIFT,X,V,N,comma,/,CRS-D
                // STOP = Row0 (RUN/STOP key)
                // LSHIFT = Row1
                8'h58, 8'h78: key_matrix[3] <= 8'b11111011;  // 'X' -> Row2
                8'h56, 8'h76: key_matrix[3] <= 8'b11110111;  // 'V' -> Row3
                8'h4E, 8'h6E: key_matrix[3] <= 8'b11101111;  // 'N' -> Row4
                8'h2C: key_matrix[3] <= 8'b11011111;         // ',' -> Row5
                8'h2F: key_matrix[3] <= 8'b10111111;         // '/' -> Row6
                // CRS-D = Row7 (cursor down)
                
                // Column 4: SPACE,Z,C,B,M,.,RSHIFT,F1
                8'h20: key_matrix[4] <= 8'b11111110;         // SPACE -> Row0
                8'h5A, 8'h7A: key_matrix[4] <= 8'b11111101;  // 'Z' -> Row1 (ERA SBAGLIATO!)
                8'h43, 8'h63: key_matrix[4] <= 8'b11111011;  // 'C' -> Row2
                8'h42, 8'h62: key_matrix[4] <= 8'b11110111;  // 'B' -> Row3
                8'h4D, 8'h6D: key_matrix[4] <= 8'b11101111;  // 'M' -> Row4
                8'h2E: key_matrix[4] <= 8'b11011111;         // '.' -> Row5
                // RSHIFT = Row6
                // F1 = Row7
                
                // Column 5: C=,S,F,H,K,:,=,F3
                // C= = Row0 (Commodore key)
                8'h53, 8'h73: key_matrix[5] <= 8'b11111101;  // 'S' -> Row1
                8'h46, 8'h66: key_matrix[5] <= 8'b11111011;  // 'F' -> Row2
                8'h48, 8'h68: key_matrix[5] <= 8'b11110111;  // 'H' -> Row3
                8'h4B, 8'h6B: key_matrix[5] <= 8'b11101111;  // 'K' -> Row4
                8'h3A: key_matrix[5] <= 8'b11011111;         // ':' -> Row5
                8'h3D: key_matrix[5] <= 8'b10111111;         // '=' -> Row6
                // F3 = Row7
                
                // Column 6: Q,E,T,U,O,@,^,F5
                8'h51, 8'h71: key_matrix[6] <= 8'b11111110;  // 'Q' -> Row0
                8'h45, 8'h65: key_matrix[6] <= 8'b11111101;  // 'E' -> Row1
                8'h54, 8'h74: key_matrix[6] <= 8'b11111011;  // 'T' -> Row2
                8'h55, 8'h75: key_matrix[6] <= 8'b11110111;  // 'U' -> Row3
                8'h4F, 8'h6F: key_matrix[6] <= 8'b11101111;  // 'O' -> Row4
                8'h40: key_matrix[6] <= 8'b11011111;         // '@' -> Row5
                8'h5E: key_matrix[6] <= 8'b10111111;         // '^' -> Row6
                // F5 = Row7
                
                // Column 7: 2,4,6,8,0,-,HOME,F7
                8'h32: key_matrix[7] <= 8'b11111110;  // '2' -> Row0
                8'h34: key_matrix[7] <= 8'b11111101;  // '4' -> Row1
                8'h36: key_matrix[7] <= 8'b11111011;  // '6' -> Row2
                8'h38: key_matrix[7] <= 8'b11110111;  // '8' -> Row3
                8'h30: key_matrix[7] <= 8'b11101111;  // '0' -> Row4
                8'h2D: key_matrix[7] <= 8'b11011111;  // '-' -> Row5
                // HOME = Row6
                // F7 = Row7
                
                //==============================================================
                // CARATTERI SPECIALI CHE RICHIEDONO SHIFT
                // LSHIFT è in Col3, Row1 -> key_matrix[3] bit 1 = 0
                //==============================================================
                
                // " (virgolette) = SHIFT + 2
                8'h22: begin
                    key_matrix[3] <= 8'b11111101;  // LSHIFT (Col3, Row1)
                    key_matrix[7] <= 8'b11111110;  // 2 (Col7, Row0)
                end
                
                // ! = SHIFT + 1
                8'h21: begin
                    key_matrix[3] <= 8'b11111101;  // LSHIFT (Col3, Row1)
                    key_matrix[0] <= 8'b11111110;  // 1 (Col0, Row0)
                end
                
                // # = SHIFT + 3
                8'h23: begin
                    key_matrix[3] <= 8'b11111101;  // LSHIFT (Col3, Row1)
                    key_matrix[0] <= 8'b11111101;  // 3 (Col0, Row1)
                end
                
                // $ = SHIFT + 4
                8'h24: begin
                    key_matrix[3] <= 8'b11111101;  // LSHIFT (Col3, Row1)
                    key_matrix[7] <= 8'b11111101;  // 4 (Col7, Row1)
                end
                
                // % = SHIFT + 5
                8'h25: begin
                    key_matrix[3] <= 8'b11111101;  // LSHIFT (Col3, Row1)
                    key_matrix[0] <= 8'b11111011;  // 5 (Col0, Row2)
                end
                
                // & = SHIFT + 6
                8'h26: begin
                    key_matrix[3] <= 8'b11111101;  // LSHIFT (Col3, Row1)
                    key_matrix[7] <= 8'b11111011;  // 6 (Col7, Row2)
                end
                
                // ' (apostrofo) = SHIFT + 7
                8'h27: begin
                    key_matrix[3] <= 8'b11111101;  // LSHIFT (Col3, Row1)
                    key_matrix[0] <= 8'b11110111;  // 7 (Col0, Row3)
                end
                
                // ( = SHIFT + 8
                8'h28: begin
                    key_matrix[3] <= 8'b11111101;  // LSHIFT (Col3, Row1)
                    key_matrix[7] <= 8'b11110111;  // 8 (Col7, Row3)
                end
                
                // ) = SHIFT + 9
                8'h29: begin
                    key_matrix[3] <= 8'b11111101;  // LSHIFT (Col3, Row1)
                    key_matrix[0] <= 8'b11101111;  // 9 (Col0, Row4)
                end
                
                // ? = SHIFT + /  (/ è Col3 Row6, LSHIFT è Col3 Row1)
                8'h3F: begin
                    key_matrix[3] <= 8'b10111101;  // LSHIFT (Row1) + / (Row6) entrambi Col3
                end
                
                // > = SHIFT + .
                8'h3E: begin
                    key_matrix[3] <= 8'b11111101;  // LSHIFT (Col3, Row1)
                    key_matrix[4] <= 8'b11011111;  // . (Col4, Row5)
                end
                
                // < = SHIFT + ,  (, è Col3 Row5, LSHIFT è Col3 Row1)
                8'h3C: begin
                    key_matrix[3] <= 8'b11011101;  // LSHIFT (Row1) + , (Row5) entrambi Col3
                end
                
                // £ = Col0, Row6
                8'h9C: key_matrix[0] <= 8'b10111111;  // £
                8'h5C: key_matrix[0] <= 8'b10111111;  // £ alternate code
                
                // Arrow keys (PETSCII codes from PS/2 keyboard)
                // CDN (cursor down) = Col4, Row7 -> key_matrix[4] bit 7 = 0
                // CRT (cursor right) = Col3, Row7 -> key_matrix[3] bit 7 = 0
                // LSHIFT = Col3, Row1 -> key_matrix[3] bit 1 = 0
                8'h11: key_matrix[4] <= 8'b01111111;  // Down = CDN
                8'h91: begin  // Up = SHIFT + CDN
                    key_matrix[3] <= 8'b11111101;  // LSHIFT
                    key_matrix[4] <= 8'b01111111;  // CDN
                end
                8'h1D: key_matrix[3] <= 8'b01111111;  // Right = CRT
                8'h9D: key_matrix[3] <= 8'b01111101;  // Left = SHIFT + CRT (both bits in same col)
                8'h13: key_matrix[2] <= 8'b01111111;  // Home = HOME key (Col2, Row7)
                
                // Function keys F1-F8 (codes 0x85-0x8C from PS/2)
                // VIC-20 Row7: F7(Col7) F5(Col6) F3(Col5) F1(Col4)
                // F2,F4,F6,F8 = SHIFT + F1,F3,F5,F7
                8'h85: key_matrix[4] <= 8'b01111111;  // F1 = Col4, Row7
                8'h86: begin  // F2 = SHIFT + F1
                    key_matrix[3] <= 8'b11111101;  // LSHIFT
                    key_matrix[4] <= 8'b01111111;  // F1
                end
                8'h87: key_matrix[5] <= 8'b01111111;  // F3 = Col5, Row7
                8'h88: begin  // F4 = SHIFT + F3
                    key_matrix[3] <= 8'b11111101;  // LSHIFT
                    key_matrix[5] <= 8'b01111111;  // F3
                end
                8'h89: key_matrix[6] <= 8'b01111111;  // F5 = Col6, Row7
                8'h8A: begin  // F6 = SHIFT + F5
                    key_matrix[3] <= 8'b11111101;  // LSHIFT
                    key_matrix[6] <= 8'b01111111;  // F5
                end
                8'h8B: key_matrix[7] <= 8'b01111111;  // F7 = Col7, Row7
                8'h8C: begin  // F8 = SHIFT + F7
                    key_matrix[3] <= 8'b11111101;  // LSHIFT
                    key_matrix[7] <= 8'b01111111;  // F7
                end

                
                default: ;
            endcase
        end
    end
end

// Keyboard read - scansione matrice
// VIC-20: VIA2 Port B ($9120) seleziona le COLONNE (bit=0 attiva colonna)
//         VIA2 Port A ($9121) legge le RIGHE (bit=0 = tasto premuto)
wire [7:0] keyboard_read;
assign keyboard_read = (via2_orb[0] ? 8'hFF : key_matrix[0]) &
                       (via2_orb[1] ? 8'hFF : key_matrix[1]) &
                       (via2_orb[2] ? 8'hFF : key_matrix[2]) &
                       (via2_orb[3] ? 8'hFF : key_matrix[3]) &
                       (via2_orb[4] ? 8'hFF : key_matrix[4]) &
                       (via2_orb[5] ? 8'hFF : key_matrix[5]) &
                       (via2_orb[6] ? 8'hFF : key_matrix[6]) &
                       (via2_orb[7] ? 8'hFF : key_matrix[7]);

//==============================================================================
// VIDEO TIMING - Dual Resolution Support
// res_mode=0: 640x480 @ 60Hz (25 MHz pixel clock)
// res_mode=1: 800x600 @ 72Hz (50 MHz pixel clock)
//==============================================================================
reg [10:0] hc;
reg [9:0] vc;

// Pixel clock divider per 640x480
reg pix_clk_div;
always @(posedge clk or negedge reset_n)
    if (!reset_n) pix_clk_div <= 0;
    else pix_clk_div <= ~pix_clk_div;

wire pix_clk_en = res_mode ? 1'b1 : pix_clk_div;

// Timing parameters
wire [10:0] H_TOTAL      = res_mode ? 11'd1040 : 11'd800;
wire [10:0] H_SYNC_START = res_mode ? 11'd856  : 11'd656;
wire [10:0] H_SYNC_END   = res_mode ? 11'd976  : 11'd752;
wire [10:0] H_VISIBLE    = res_mode ? 11'd800  : 11'd640;
wire [9:0]  V_TOTAL      = res_mode ? 10'd666  : 10'd525;
wire [9:0]  V_SYNC_START = res_mode ? 10'd637  : 10'd490;
wire [9:0]  V_SYNC_END   = res_mode ? 10'd643  : 10'd492;
wire [9:0]  V_VISIBLE    = res_mode ? 10'd600  : 10'd480;

// VIC-20: 22x23 chars, 8x8 pixels = 176x184, scaling 2x = 352x368
// 800x600: Centro (800-352)/2=224, (600-368)/2=116
// 640x480: Centro (640-352)/2=144, (480-368)/2=56
wire [10:0] CHAR_X = res_mode ? 11'd224 : 11'd144;
wire [9:0]  CHAR_Y = res_mode ? 10'd116 : 10'd56;

wire [4:0] char_col = (hc >= CHAR_X) ? ((hc - CHAR_X) >> 4) : 5'd0;
wire [4:0] char_row = (vc >= CHAR_Y) ? ((vc - CHAR_Y) >> 4) : 5'd0;
wire [2:0] pixel_col = (hc - CHAR_X) >> 1;
wire [2:0] pixel_row = (vc - CHAR_Y) >> 1;

//==============================================================================
// RAM
//==============================================================================
// PRG load scrive direttamente in RAM
wire prg_wr_ram0 = prg_load_wr && (prg_load_addr[15:10] == 6'b000000);
wire prg_wr_ram1 = prg_load_wr && (prg_load_addr[15:12] == 4'h1);

(* ramstyle = "M9K" *) reg [7:0] ram0 [0:1023];
reg [7:0] ram0_q;
always @(posedge clk) begin
    if (cpu_wr && sel_ram0) ram0[cpu_addr[9:0]] <= cpu_dout;
    else if (prg_wr_ram0) ram0[prg_load_addr[9:0]] <= prg_load_data;
    ram0_q <= ram0[cpu_addr[9:0]];
end

(* ramstyle = "M9K" *) reg [7:0] ram1 [0:4095];
reg [7:0] ram1_q;
reg [7:0] screen_data;

wire [8:0] row_x22 = {char_row, 4'b0} + {char_row, 2'b0} + {char_row, 1'b0};
wire [11:0] screen_addr = 12'hE00 + row_x22 + char_col;

always @(posedge clk) begin
    if (cpu_wr && sel_ram1) ram1[cpu_addr[11:0]] <= cpu_dout;
    else if (prg_wr_ram1) ram1[prg_load_addr[11:0]] <= prg_load_data;
    ram1_q <= ram1[cpu_addr[11:0]];
    screen_data <= ram1[screen_addr];
end

//==============================================================================
// COLOR RAM ($9400-$97FF) - 1KB, solo 4 bit usati
// Usa logica distribuita per risparmiare M9K
//==============================================================================
(* ramstyle = "logic" *) reg [3:0] color_ram [0:1023];
reg [3:0] color_data;
reg [3:0] screen_color_r1;  // Primo stadio pipeline
reg [3:0] screen_color;     // Secondo stadio - allineato con char_line

// Inizializza color_ram con colore BLU (6) come VIC-20 originale
integer c;
initial begin
    for (c = 0; c < 1024; c = c + 1)
        color_ram[c] = 4'h6;  // Blue
end

always @(posedge clk) begin
    if (cpu_wr && sel_color) color_ram[cpu_addr[9:0]] <= cpu_dout[3:0];
    color_data <= color_ram[cpu_addr[9:0]];
    screen_color_r1 <= color_ram[row_x22 + char_col];  // Primo stadio
    screen_color <= screen_color_r1;                    // Secondo stadio - allineato con char_line
end

//==============================================================================
// ROM - Caricabili via UART
//==============================================================================
wire basic_we   = rom_load_wr && (rom_bank == 2'd0);
wire kernal_we  = rom_load_wr && (rom_bank == 2'd1);
wire char_we    = rom_load_wr && (rom_bank == 2'd2);

(* ramstyle = "M9K" *) reg [7:0] basic_rom [0:8191];
reg [7:0] basic_q;
always @(posedge clk) begin
    if (basic_we) basic_rom[rom_load_addr[12:0]] <= rom_load_data;
    basic_q <= basic_rom[cpu_addr[12:0]];
end

(* ramstyle = "M9K" *) reg [7:0] kernal_rom [0:8191];
reg [7:0] kernal_q;
always @(posedge clk) begin
    if (kernal_we) kernal_rom[rom_load_addr[12:0]] <= rom_load_data;
    kernal_q <= kernal_rom[cpu_addr[12:0]];
end

// Character ROM - solo lettura video (risparmia M9K)
(* ramstyle = "M9K" *) reg [7:0] char_rom [0:4095];
reg [7:0] char_line;
always @(posedge clk) begin
    if (char_we) char_rom[rom_load_addr[11:0]] <= rom_load_data;
    char_line <= char_rom[{screen_data, pixel_row}];
end

// CPU read from char ROM - restituisce 0xFF (non usato normalmente)
wire [7:0] char_q = 8'hFF;

//==============================================================================
// VIC REGISTERS
//==============================================================================
reg [7:0] vic_reg [0:15];

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        vic_reg[0] <= 8'h0C;   // Screen X origin
        vic_reg[1] <= 8'h26;   // Screen Y origin
        vic_reg[2] <= 8'h16;   // Columns (22)
        vic_reg[3] <= 8'hAE;   // Rows + char size
        vic_reg[5] <= 8'hF0;   // Video/color address
        vic_reg[14] <= 8'h00;  // Aux color
        vic_reg[15] <= 8'h1B;  // Border/BG colors
    end
    else if (cpu_wr && sel_vic) begin
        vic_reg[cpu_addr[3:0]] <= cpu_dout;
    end
end

//==============================================================================
// VIA2 ($9120-$912F) - Timer di sistema per IRQ e KEYBOARD READ
//==============================================================================
reg [15:0] via2_t1_counter;
reg [15:0] via2_t1_latch;
reg [7:0]  via2_acr;
reg [7:0]  via2_ifr;
reg [7:0]  via2_ier;
reg [7:0]  via2_ora;
reg [7:0]  via2_orb;
reg [7:0]  via2_ddra;
reg [7:0]  via2_ddrb;
reg        via2_t1_running;

//==============================================================================
// VIA2 - Timer T1 per IRQ - FLIP-FLOP APPROACH
//==============================================================================
// IRQ flag viene SETTATO dal fallback 60Hz
// IRQ flag viene CLEARATO dalla lettura di T1C-L ($9124)
// Questo è il comportamento corretto dell'hardware reale.
//==============================================================================

// IRQ flip-flop - settato dal fallback, clearato dalla lettura T1C-L
reg        irq_flag;

// Fallback 60Hz (50MHz / 60 = 833333)
reg [19:0] fallback_counter;
reg        fallback_pulse;  // Pulse di 1 ciclo

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        fallback_counter <= 20'd833333;
        fallback_pulse <= 1'b0;
    end
    else begin
        fallback_pulse <= 1'b0;
        if (fallback_counter == 20'd0) begin
            fallback_counter <= 20'd833333;
            fallback_pulse <= 1'b1;
        end
        else begin
            fallback_counter <= fallback_counter - 1'd1;
        end
    end
end

// IRQ flags per lettura registri
wire via1_irq = |(via1_ifr[6:0] & via1_ier[6:0]);

// IRQ attivo quando flag è settato E IER[6] abilitato
wire via2_irq = |(via2_ifr[6:0] & via2_ier[6:0]);
// IRQ CPU = OR delle sorgenti (VIA1 e VIA2)
wire cpu_irq = via1_irq | via2_irq;
assign irq_n = ~cpu_irq;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        via2_t1_counter <= 16'h4240;
        via2_t1_latch <= 16'h4240;
        via2_acr <= 8'h40;
        via2_ifr <= 8'h00;
        via2_ier <= 8'h40;
        via2_ora <= 8'hFF;
        via2_orb <= 8'hFF;
        via2_ddra <= 8'h00;
        via2_ddrb <= 8'hFF;
        via2_t1_running <= 1'b1;
        irq_flag <= 1'b0;
    end else begin
        // FALLBACK: Setta il flag IRQ (pulse di 1 ciclo a 50MHz)
        if (fallback_pulse) begin
            irq_flag <= 1'b1;
            via2_ifr[6] <= 1'b1;
        end
        
        if (enable && cpu_clk_en) begin
            // Timer T1 countdown - setta flag quando underflow
            if (via2_t1_running) begin
                if (via2_t1_counter == 16'h0000) begin
                    irq_flag <= 1'b1;
                    via2_ifr[6] <= 1'b1;
                    if (via2_acr[6]) begin
                        via2_t1_counter <= via2_t1_latch;
                    end else begin
                        via2_t1_running <= 1'b0;
                    end
                end else begin
                    via2_t1_counter <= via2_t1_counter - 1'd1;
                end
            end
            
            // Register writes
            if (cpu_we && sel_via2) begin
                case (cpu_addr[3:0])
                    4'h0: via2_orb <= cpu_dout;
                    4'h1: via2_ora <= cpu_dout;
                    4'h2: via2_ddrb <= cpu_dout;
                    4'h3: via2_ddra <= cpu_dout;
                    4'h4: via2_t1_latch[7:0] <= cpu_dout;
                    4'h5: begin
                        via2_t1_counter <= {cpu_dout, via2_t1_latch[7:0]};
                        via2_t1_running <= 1'b1;
                        irq_flag <= 1'b0;  // Clear flag on T1C-H write
                    end
                    4'h6: via2_t1_latch[7:0] <= cpu_dout;
                    4'h7: via2_t1_latch[15:8] <= cpu_dout;
                    4'hB: via2_acr <= cpu_dout;
                    4'hD: begin
                        // IFR write - clear bits che sono 1 nel dato scritto
                        if (cpu_dout[6]) begin irq_flag <= 1'b0; via2_ifr[6] <= 1'b0; end
                    end
                    4'hE: begin
                        if (cpu_dout[7])
                            via2_ier <= via2_ier | (cpu_dout & 8'h7F);
                        else
                            via2_ier <= via2_ier & ~(cpu_dout & 8'h7F);
                    end
                endcase
            end
            
            // LETTURA T1C-L ($9124) CLEARA IL FLAG - questo è cruciale!
            if (!cpu_we && sel_via2 && cpu_addr[3:0] == 4'h4) begin
                irq_flag <= 1'b0;
                via2_ifr[6] <= 1'b0;
            end
        end
    end
end

//==============================================================================
// CPU DATA MUX
//==============================================================================
always @(*) begin
    cpu_din = 8'hFF;
    if (sel_ram0)        cpu_din = ram0_q;
    else if (sel_ram1)   cpu_din = ram1_q;
    else if (sel_char)   cpu_din = char_q;
    else if (sel_color)  cpu_din = {4'hF, color_data};  // High nibble = 1
    else if (sel_basic)  cpu_din = basic_q;
    else if (sel_kernal) cpu_din = kernal_q;
    else if (sel_vic)    cpu_din = vic_reg[cpu_addr[3:0]];
    else if (sel_via1) begin
        case (cpu_addr[3:0])
            4'h0: cpu_din = via1_orb;                   // Port B (NMI, cassette, etc)
            4'h1: cpu_din = via1_ora;                   // Port A (keyboard cols select)
            4'h2: cpu_din = via1_ddrb;                  // DDRB
            4'h3: cpu_din = via1_ddra;                  // DDRA
            4'h4: cpu_din = via1_t1_counter[7:0];       // T1C-L
            4'h5: cpu_din = via1_t1_counter[15:8];      // T1C-H
            4'h6: cpu_din = via1_t1_latch[7:0];         // T1L-L
            4'h7: cpu_din = via1_t1_latch[15:8];        // T1L-H
            4'hB: cpu_din = via1_acr;                   // ACR
            4'hD: cpu_din = {via1_irq, via1_ifr[6:0]};  // IFR
            4'hE: cpu_din = {1'b1, via1_ier[6:0]};      // IER
            default: cpu_din = 8'hFF;
        endcase
    end
    else if (sel_via2) begin
        case (cpu_addr[3:0])
            4'h0: cpu_din = via2_orb;                  // Port B = keyboard COLUMN select
            4'h1: cpu_din = keyboard_read;            // Port A = keyboard ROW read!
            4'h2: cpu_din = via2_ddrb;                // DDRB
            4'h3: cpu_din = via2_ddra;                // DDRA
            4'h4: cpu_din = via2_t1_counter[7:0];
            4'h5: cpu_din = via2_t1_counter[15:8];
            4'h6: cpu_din = via2_t1_latch[7:0];
            4'h7: cpu_din = via2_t1_latch[15:8];
            4'hB: cpu_din = via2_acr;
            4'hD: cpu_din = {via2_irq, via2_ifr[6:0]};
            4'hE: cpu_din = {1'b1, via2_ier[6:0]};
            default: cpu_din = 8'hFF;
        endcase
    end
end

//==============================================================================
// VIDEO OUTPUT - Dual Resolution
//==============================================================================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        hc <= 11'd0;
        vc <= 10'd0;
    end else if (pix_clk_en) begin
        hc <= (hc == H_TOTAL-1) ? 11'd0 : hc + 11'd1;
        if (hc == H_TOTAL-1)
            vc <= (vc == V_TOTAL-1) ? 10'd0 : vc + 10'd1;
    end
end

assign vga_hs = ~(hc >= H_SYNC_START && hc < H_SYNC_END);
assign vga_vs = ~(vc >= V_SYNC_START && vc < V_SYNC_END);

wire in_screen = (hc >= CHAR_X) && (hc < CHAR_X + 352) &&
                 (vc >= CHAR_Y) && (vc < CHAR_Y + 368) &&
                 (char_col < 22) && (char_row < 23);

wire pixel_on = char_line[7 - pixel_col[2:0]];

// VIC-20 palette (16 colori)
reg [3:0] fg_r, fg_g, fg_b;
always @(*) begin
    case (screen_color)
        4'h0: begin fg_r=4'h0; fg_g=4'h0; fg_b=4'h0; end  // Black
        4'h1: begin fg_r=4'hF; fg_g=4'hF; fg_b=4'hF; end  // White
        4'h2: begin fg_r=4'hA; fg_g=4'h3; fg_b=4'h3; end  // Red
        4'h3: begin fg_r=4'h6; fg_g=4'hD; fg_b=4'hD; end  // Cyan
        4'h4: begin fg_r=4'hA; fg_g=4'h4; fg_b=4'hA; end  // Purple
        4'h5: begin fg_r=4'h5; fg_g=4'hA; fg_b=4'h5; end  // Green
        4'h6: begin fg_r=4'h3; fg_g=4'h3; fg_b=4'hA; end  // Blue
        4'h7: begin fg_r=4'hD; fg_g=4'hD; fg_b=4'h6; end  // Yellow
        4'h8: begin fg_r=4'hA; fg_g=4'h6; fg_b=4'h3; end  // Orange
        4'h9: begin fg_r=4'hD; fg_g=4'hA; fg_b=4'h6; end  // Light Orange
        4'hA: begin fg_r=4'hD; fg_g=4'h8; fg_b=4'h8; end  // Pink
        4'hB: begin fg_r=4'hA; fg_g=4'hF; fg_b=4'hF; end  // Light Cyan
        4'hC: begin fg_r=4'hD; fg_g=4'h8; fg_b=4'hD; end  // Light Purple
        4'hD: begin fg_r=4'hA; fg_g=4'hF; fg_b=4'hA; end  // Light Green
        4'hE: begin fg_r=4'h8; fg_g=4'h8; fg_b=4'hF; end  // Light Blue
        4'hF: begin fg_r=4'hF; fg_g=4'hF; fg_b=4'hA; end  // Light Yellow
    endcase
end

always @(posedge clk) begin
    if (hc >= H_VISIBLE || vc >= V_VISIBLE) begin
        vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h0;
    end else if (!enable) begin
        vga_r <= 4'h0; vga_g <= 4'hF; vga_b <= 4'hF;
    end else if (!boot_done) begin
        vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'hF;
    end else if (!in_screen) begin
        // Border color from VIC register $900F
        vga_r <= 4'h0; vga_g <= 4'hF; vga_b <= 4'hF;
    end else begin
        if (pixel_on) begin
            vga_r <= fg_r; vga_g <= fg_g; vga_b <= fg_b;
        end else begin
            vga_r <= 4'hF; vga_g <= 4'hF; vga_b <= 4'hF;  // BG white
        end
    end
end

assign audio_out = 1'b0;

endmodule
