//==============================================================================
// APPLE I COMPLETE CORE - FIXED VERSION
// With proper PIA display busy timing
//==============================================================================

module apple1_complete (
    input  wire        clk,           // 50MHz
    input  wire        reset_n,       // Active low reset
    input  wire        enable,        // Core enable
    input  wire        res_mode,      // 0=640x480, 1=800x600
    
    // Keyboard input
    input  wire [7:0]  key_code,
    input  wire        key_strobe,
    
    // ROM loading interface
    input  wire        rom_load_en,
    input  wire [15:0] rom_load_addr,
    input  wire [7:0]  rom_load_data,
    input  wire        rom_load_wr,
    
    // VGA output
    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b,
    output reg         vga_hs,
    output reg         vga_vs,
    
    // Audio
    output wire        audio_out,
    
    // Debug
    output wire        debug_out
);

//==============================================================================
// RESET & POWER-ON DELAY
//==============================================================================
reg [5:0] reset_delay;
wire cpu_reset = !enable || !reset_n || (reset_delay < 6'd63);

always @(posedge clk) begin
    if (!reset_n || !enable)
        reset_delay <= 6'd0;
    else if (reset_delay < 6'd63)
        reset_delay <= reset_delay + 6'd1;
end

//==============================================================================
// CPU CLOCK - 1MHz from 50MHz
//==============================================================================
reg [5:0] clk_div;
wire cpu_clk_en = (clk_div == 6'd0);

always @(posedge clk) begin
    if (cpu_reset)
        clk_div <= 6'd0;
    else if (clk_div >= 6'd49)
        clk_div <= 6'd0;
    else
        clk_div <= clk_div + 6'd1;
end

//==============================================================================
// CPU - T65 Core
//==============================================================================
wire [15:0] cpu_addr;
wire [7:0]  cpu_data_out;
reg  [7:0]  cpu_data_in;
wire        cpu_we;

T65_wrapper cpu (
    .clk(clk),
    .enable(cpu_clk_en),
    .reset_n(~cpu_reset),    // Active LOW
    .addr(cpu_addr),
    .data_in(cpu_data_in),
    .data_out(cpu_data_out),
    .we(cpu_we),
    .irq_n(1'b1),            // No IRQ
    .nmi_n(1'b1),            // No NMI
    .rdy(1'b1)               // Always ready
);

//==============================================================================
// ADDRESS DECODING
//==============================================================================
wire ram_cs   = (cpu_addr < 16'h2000);                              // $0000-$1FFF (8KB)
wire pia_cs   = (cpu_addr >= 16'hD010 && cpu_addr <= 16'hD013);     // $D010-$D013
wire basic_cs = (cpu_addr >= 16'hE000 && cpu_addr <= 16'hEFFF);     // $E000-$EFFF
wire rom_cs   = (cpu_addr >= 16'hFF00);                              // $FF00-$FFFF

//==============================================================================
// RAM - 8KB
//==============================================================================
(* ramstyle = "M9K" *) reg [7:0] ram [0:8191];
reg [7:0] ram_data_out;

integer i;

always @(posedge clk) begin
    if (ram_cs && cpu_we && cpu_clk_en)
        ram[cpu_addr[12:0]] <= cpu_data_out;
    ram_data_out <= ram[cpu_addr[12:0]];
end

//==============================================================================
// SIMPLE MONITOR ROM ($FF00-$FFFF) - Funzionante!
// Comandi: indirizzo hex, : per store, R per run
//==============================================================================
reg [7:0] wozmon_rom [0:255];
reg [7:0] rom_data_out;

initial begin
    // Initialize all to NOP
    for (i = 0; i < 256; i = i + 1)
        wozmon_rom[i] = 8'hEA;
    
    // =============================================
    // RESET - $FF00
    // =============================================
    wozmon_rom[8'h00] = 8'hD8; // CLD
    wozmon_rom[8'h01] = 8'h58; // CLI
    wozmon_rom[8'h02] = 8'hA2; // LDX #$FF (init stack)
    wozmon_rom[8'h03] = 8'hFF;
    wozmon_rom[8'h04] = 8'h9A; // TXS
    wozmon_rom[8'h05] = 8'hA9; // LDA #$DC ('\')
    wozmon_rom[8'h06] = 8'hDC;
    wozmon_rom[8'h07] = 8'h20; // JSR ECHO ($FFDC)
    wozmon_rom[8'h08] = 8'hDC;
    wozmon_rom[8'h09] = 8'hFF;
    
    // =============================================  
    // NEWLINE - $FF0A: print CR and get input
    // =============================================
    wozmon_rom[8'h0A] = 8'hA9; // LDA #$8D (CR)
    wozmon_rom[8'h0B] = 8'h8D;
    wozmon_rom[8'h0C] = 8'h20; // JSR ECHO
    wozmon_rom[8'h0D] = 8'hDC;
    wozmon_rom[8'h0E] = 8'hFF;
    wozmon_rom[8'h0F] = 8'hA0; // LDY #$00 (buffer index)
    wozmon_rom[8'h10] = 8'h00;
    wozmon_rom[8'h11] = 8'h84; // STY $27 (MODE=0)
    wozmon_rom[8'h12] = 8'h27;
    
    // =============================================
    // GETKEY - $FF13: wait for key
    // =============================================
    wozmon_rom[8'h13] = 8'hAD; // LDA $D011 (keyboard status)
    wozmon_rom[8'h14] = 8'h11;
    wozmon_rom[8'h15] = 8'hD0;
    wozmon_rom[8'h16] = 8'h10; // BPL GETKEY (wait for bit 7)
    wozmon_rom[8'h17] = 8'hFB;
    wozmon_rom[8'h18] = 8'hAD; // LDA $D010 (read key)
    wozmon_rom[8'h19] = 8'h10;
    wozmon_rom[8'h1A] = 8'hD0;
    
    // =============================================
    // Process key - $FF1B
    // =============================================
    wozmon_rom[8'h1B] = 8'hC9; // CMP #$8D (CR?)
    wozmon_rom[8'h1C] = 8'h8D;
    wozmon_rom[8'h1D] = 8'hF0; // BEQ PARSE ($FF40)
    wozmon_rom[8'h1E] = 8'h21;
    
    wozmon_rom[8'h1F] = 8'hC9; // CMP #$9B (ESC?)
    wozmon_rom[8'h20] = 8'h9B;
    wozmon_rom[8'h21] = 8'hF0; // BEQ RESET ($FF00)
    wozmon_rom[8'h22] = 8'hDD; // offset = $FF00 - $FF23 = -35 = $DD
    
    // Store char in buffer and echo
    wozmon_rom[8'h23] = 8'h99; // STA $0200,Y
    wozmon_rom[8'h24] = 8'h00;
    wozmon_rom[8'h25] = 8'h02;
    wozmon_rom[8'h26] = 8'h20; // JSR ECHO
    wozmon_rom[8'h27] = 8'hDC;
    wozmon_rom[8'h28] = 8'hFF;
    wozmon_rom[8'h29] = 8'hC8; // INY
    wozmon_rom[8'h2A] = 8'hC0; // CPY #$40 (buffer full?)
    wozmon_rom[8'h2B] = 8'h40;
    wozmon_rom[8'h2C] = 8'h90; // BCC GETKEY
    wozmon_rom[8'h2D] = 8'hE5; // offset = $FF13 - $FF2E = -27 = $E5
    wozmon_rom[8'h2E] = 8'h4C; // JMP NEWLINE (overflow)
    wozmon_rom[8'h2F] = 8'h0A;
    wozmon_rom[8'h30] = 8'hFF;
    
    // Padding
    wozmon_rom[8'h31] = 8'hEA;
    wozmon_rom[8'h32] = 8'hEA;
    wozmon_rom[8'h33] = 8'hEA;
    wozmon_rom[8'h34] = 8'hEA;
    wozmon_rom[8'h35] = 8'hEA;
    wozmon_rom[8'h36] = 8'hEA;
    wozmon_rom[8'h37] = 8'hEA;
    wozmon_rom[8'h38] = 8'hEA;
    wozmon_rom[8'h39] = 8'hEA;
    wozmon_rom[8'h3A] = 8'hEA;
    wozmon_rom[8'h3B] = 8'hEA;
    wozmon_rom[8'h3C] = 8'hEA;
    wozmon_rom[8'h3D] = 8'hEA;
    wozmon_rom[8'h3E] = 8'hEA;
    wozmon_rom[8'h3F] = 8'hEA;
    
    // =============================================
    // PARSE - $FF40: parse input line
    // =============================================
    wozmon_rom[8'h40] = 8'hA0; // LDY #$00
    wozmon_rom[8'h41] = 8'h00;
    wozmon_rom[8'h42] = 8'hA9; // LDA #$00
    wozmon_rom[8'h43] = 8'h00;
    wozmon_rom[8'h44] = 8'h85; // STA $28 (addr low)
    wozmon_rom[8'h45] = 8'h28;
    wozmon_rom[8'h46] = 8'h85; // STA $29 (addr high)
    wozmon_rom[8'h47] = 8'h29;
    
    // =============================================
    // NEXTCHAR - $FF48
    // =============================================
    wozmon_rom[8'h48] = 8'hB9; // LDA $0200,Y
    wozmon_rom[8'h49] = 8'h00;
    wozmon_rom[8'h4A] = 8'h02;
    wozmon_rom[8'h4B] = 8'hC9; // CMP #$8D (CR = done)
    wozmon_rom[8'h4C] = 8'h8D;
    wozmon_rom[8'h4D] = 8'hF0; // BEQ ENDPARSE ($FF98)
    wozmon_rom[8'h4E] = 8'h49;
    
    // Check for ':'
    wozmon_rom[8'h4F] = 8'hC9; // CMP #$BA (':')
    wozmon_rom[8'h50] = 8'hBA;
    wozmon_rom[8'h51] = 8'hD0; // BNE NOTCOLON
    wozmon_rom[8'h52] = 8'h09;
    // Set store mode
    wozmon_rom[8'h53] = 8'hA5; // LDA $28
    wozmon_rom[8'h54] = 8'h28;
    wozmon_rom[8'h55] = 8'h85; // STA $24 (store addr low)
    wozmon_rom[8'h56] = 8'h24;
    wozmon_rom[8'h57] = 8'hA5; // LDA $29
    wozmon_rom[8'h58] = 8'h29;
    wozmon_rom[8'h59] = 8'h85; // STA $25 (store addr high)
    wozmon_rom[8'h5A] = 8'h25;
    wozmon_rom[8'h5B] = 8'h4C; // JMP SKIPCHR ($FF90)
    wozmon_rom[8'h5C] = 8'h90;
    wozmon_rom[8'h5D] = 8'hFF;
    
    // NOTCOLON - $FF5D: Check for 'R'
    wozmon_rom[8'h5D] = 8'hC9; // CMP #$D2 ('R')
    wozmon_rom[8'h5E] = 8'hD2;
    wozmon_rom[8'h5F] = 8'hD0; // BNE NOTHEXR
    wozmon_rom[8'h60] = 8'h04;
    // RUN - jump to address
    wozmon_rom[8'h61] = 8'h6C; // JMP ($28)
    wozmon_rom[8'h62] = 8'h28;
    wozmon_rom[8'h63] = 8'h00;
    wozmon_rom[8'h64] = 8'hEA; // NOP (never reached)
    
    // NOTHEXR - $FF65: Try hex digit
    wozmon_rom[8'h65] = 8'h38; // SEC
    wozmon_rom[8'h66] = 8'hE9; // SBC #$B0 ('0')
    wozmon_rom[8'h67] = 8'hB0;
    wozmon_rom[8'h68] = 8'h30; // BMI SKIPCHR (not digit)
    wozmon_rom[8'h69] = 8'h26;
    wozmon_rom[8'h6A] = 8'hC9; // CMP #$0A
    wozmon_rom[8'h6B] = 8'h0A;
    wozmon_rom[8'h6C] = 8'h90; // BCC GOTDIG ($FF76)
    wozmon_rom[8'h6D] = 8'h08;
    // Try A-F
    wozmon_rom[8'h6E] = 8'hE9; // SBC #$07 ('A'-'0'-10)
    wozmon_rom[8'h6F] = 8'h07;
    wozmon_rom[8'h70] = 8'hC9; // CMP #$0A
    wozmon_rom[8'h71] = 8'h0A;
    wozmon_rom[8'h72] = 8'h90; // BCC SKIPCHR (invalid)
    wozmon_rom[8'h73] = 8'h1C;
    wozmon_rom[8'h74] = 8'hC9; // CMP #$10
    wozmon_rom[8'h75] = 8'h10;
    wozmon_rom[8'h76] = 8'hB0; // BCS SKIPCHR (invalid)
    wozmon_rom[8'h77] = 8'h18;
    
    // GOTDIG - $FF78: shift digit into address
    wozmon_rom[8'h78] = 8'hA2; // LDX #$04
    wozmon_rom[8'h79] = 8'h04;
    wozmon_rom[8'h7A] = 8'h0A; // ASL A (shift digit left)
    wozmon_rom[8'h7B] = 8'h0A;
    wozmon_rom[8'h7C] = 8'h0A;
    wozmon_rom[8'h7D] = 8'h0A;
    // SHIFTLOOP - $FF7E
    wozmon_rom[8'h7E] = 8'h0A; // ASL A
    wozmon_rom[8'h7F] = 8'h26; // ROL $28
    wozmon_rom[8'h80] = 8'h28;
    wozmon_rom[8'h81] = 8'h26; // ROL $29
    wozmon_rom[8'h82] = 8'h29;
    wozmon_rom[8'h83] = 8'hCA; // DEX
    wozmon_rom[8'h84] = 8'hD0; // BNE SHIFTLOOP
    wozmon_rom[8'h85] = 8'hF7;
    
    // Check if in store mode
    wozmon_rom[8'h86] = 8'hA5; // LDA $24
    wozmon_rom[8'h87] = 8'h24;
    wozmon_rom[8'h88] = 8'h05; // ORA $25
    wozmon_rom[8'h89] = 8'h25;
    wozmon_rom[8'h8A] = 8'hF0; // BEQ SKIPCHR (not storing)
    wozmon_rom[8'h8B] = 8'h04;
    // Store byte
    wozmon_rom[8'h8C] = 8'hA5; // LDA $28
    wozmon_rom[8'h8D] = 8'h28;
    wozmon_rom[8'h8E] = 8'h81; // STA ($24,X) - X=0
    wozmon_rom[8'h8F] = 8'h24;
    
    // SKIPCHR - $FF90
    wozmon_rom[8'h90] = 8'hC8; // INY
    wozmon_rom[8'h91] = 8'h4C; // JMP NEXTCHAR
    wozmon_rom[8'h92] = 8'h48;
    wozmon_rom[8'h93] = 8'hFF;
    
    // Padding  
    wozmon_rom[8'h94] = 8'hEA;
    wozmon_rom[8'h95] = 8'hEA;
    wozmon_rom[8'h96] = 8'hEA;
    wozmon_rom[8'h97] = 8'hEA;
    
    // ENDPARSE - $FF98: done, go to newline
    wozmon_rom[8'h98] = 8'h4C; // JMP NEWLINE
    wozmon_rom[8'h99] = 8'h0A;
    wozmon_rom[8'h9A] = 8'hFF;
    
    // =============================================
    // ECHO - $FFDC: output character
    // =============================================
    wozmon_rom[8'hDC] = 8'h48; // PHA
    wozmon_rom[8'hDD] = 8'hAD; // LDA $D012 (display status)
    wozmon_rom[8'hDE] = 8'h12;
    wozmon_rom[8'hDF] = 8'hD0;
    wozmon_rom[8'hE0] = 8'h30; // BMI ECHO+1 (wait if busy)
    wozmon_rom[8'hE1] = 8'hFA;
    wozmon_rom[8'hE2] = 8'h68; // PLA
    wozmon_rom[8'hE3] = 8'h8D; // STA $D012 (write char)
    wozmon_rom[8'hE4] = 8'h12;
    wozmon_rom[8'hE5] = 8'hD0;
    wozmon_rom[8'hE6] = 8'h60; // RTS
    
    // =============================================
    // VECTORS - $FFFA
    // =============================================
    wozmon_rom[8'hFA] = 8'h00; // NMI
    wozmon_rom[8'hFB] = 8'hFF;
    wozmon_rom[8'hFC] = 8'h00; // RESET
    wozmon_rom[8'hFD] = 8'hFF;
    wozmon_rom[8'hFE] = 8'h00; // IRQ
    wozmon_rom[8'hFF] = 8'hFF;
end

always @(posedge clk)
    rom_data_out <= wozmon_rom[cpu_addr[7:0]];

// ROM loading from ESP32
// wozmon.bin viene caricato con offset 0x0000-0x00FF
// ma deve andare in $FF00-$FFFF
always @(posedge clk) begin
    if (rom_load_en && rom_load_wr) begin
        // WozMon: indirizzi 0x0000-0x00FF (ROM 0 dal loader)
        if (rom_load_addr[15:8] == 8'h00)
            wozmon_rom[rom_load_addr[7:0]] <= rom_load_data;
        // BASIC ROM: indirizzi 0x2000-0x2FFF (ROM 1 dal loader, 4KB)
        else if (rom_load_addr[15:12] == 4'h2)
            basic_rom[rom_load_addr[11:0]] <= rom_load_data;
    end
end

//==============================================================================
// BASIC ROM - 4KB ($E000-$EFFF) - Caricabile da SD
//==============================================================================
(* ramstyle = "M9K" *) reg [7:0] basic_rom [0:4095];
reg [7:0] basic_data_out;

always @(posedge clk) begin
    basic_data_out <= basic_rom[cpu_addr[11:0]];
end

//==============================================================================
// PIA 6821 EMULATION - WITH DISPLAY BUSY TIMING
//==============================================================================

// Keyboard - with synchronization and edge detection
reg [7:0] kbd_data_reg;
reg       kbd_ready;

// Synchronize key_strobe - semplificato
reg key_strobe_r1, key_strobe_r2;
always @(posedge clk) begin
    if (cpu_reset) begin
        key_strobe_r1 <= 1'b0;
        key_strobe_r2 <= 1'b0;
    end else begin
        key_strobe_r1 <= key_strobe;
        key_strobe_r2 <= key_strobe_r1;
    end
end
wire key_strobe_edge = key_strobe_r1 && !key_strobe_r2;

// Uppercase conversion AND LF->CR conversion
wire [7:0] key_converted = (key_code == 8'h0A) ? 8'h0D :  // LF -> CR
                           (key_code >= 8'h61 && key_code <= 8'h7A) ? 
                           (key_code - 8'h20) : key_code;

always @(posedge clk) begin
    if (cpu_reset) begin
        kbd_data_reg <= 8'h00;
        kbd_ready <= 1'b0;
    end
    else begin
        // New key arrived - latch it with bit 7 set
        if (key_strobe_edge) begin
            kbd_data_reg <= key_converted | 8'h80;
            kbd_ready <= 1'b1;
        end
        // Clear ready when CPU reads $D010
        else if (pia_cs && !cpu_we && cpu_clk_en && cpu_addr[1:0] == 2'b00) begin
            kbd_ready <= 1'b0;
        end
    end
end

// Display with BUSY TIMING
reg [7:0] dsp_data_reg;
reg       dsp_write_strobe;
reg [9:0] dsp_busy_counter;  // Increased to 10 bits
wire      dsp_busy = (dsp_busy_counter > 10'd0);

always @(posedge clk) begin
    if (cpu_reset) begin
        dsp_data_reg <= 8'h00;
        dsp_write_strobe <= 1'b0;
        dsp_busy_counter <= 10'd0;
    end
    else begin
        dsp_write_strobe <= 1'b0;
        
        // Decrement busy counter each CPU cycle
        if (dsp_busy_counter > 10'd0 && cpu_clk_en)
            dsp_busy_counter <= dsp_busy_counter - 10'd1;
        
        // Write to display
        if (pia_cs && cpu_we && cpu_clk_en && cpu_addr[1:0] == 2'b10) begin
            dsp_data_reg <= cpu_data_out;
            dsp_write_strobe <= 1'b1;
            dsp_busy_counter <= 10'd200;  // ~200us busy time for reliable display
        end
    end
end

// PIA data output
reg [7:0] pia_data_out;
always @(*) begin
    case (cpu_addr[1:0])
        2'b00: pia_data_out = kbd_data_reg;              // $D010 - keyboard data
        2'b01: pia_data_out = {kbd_ready, 7'b0000000};   // $D011 - keyboard ready
        2'b10: pia_data_out = {dsp_busy, 7'b0000000};    // $D012 - display busy!
        2'b11: pia_data_out = 8'h00;                      // $D013
    endcase
end

//==============================================================================
// CPU DATA BUS
//==============================================================================
always @(*) begin
    casez ({rom_cs, basic_cs, pia_cs, ram_cs})
        4'b1???: cpu_data_in = rom_data_out;
        4'b01??: cpu_data_in = basic_data_out;
        4'b001?: cpu_data_in = pia_data_out;
        4'b0001: cpu_data_in = ram_data_out;
        default: cpu_data_in = 8'hFF;
    endcase
end

//==============================================================================
// TERMINAL DISPLAY - 32x16 characters with SCROLL
//==============================================================================
localparam COLS = 32;
localparam ROWS = 16;

reg [6:0] video_ram [0:511];
reg [4:0] cursor_x;
reg [3:0] cursor_y;
reg [3:0] scroll_offset;  // Quale riga fisica è la riga 0 logica

// Video RAM clear counter
reg [8:0] vram_clear_cnt;
reg       vram_clearing;

// Scroll state machine
reg       scrolling;
reg [4:0] scroll_col;

initial begin
    for (i = 0; i < 512; i = i + 1) 
        video_ram[i] = 7'h20;
    cursor_x = 5'd0;
    cursor_y = 4'd0;
    scroll_offset = 4'd0;
end

wire [6:0] dsp_char = dsp_data_reg[6:0];

// Calcola riga fisica da riga logica
wire [3:0] phys_row = cursor_y + scroll_offset;

always @(posedge clk) begin
    if (cpu_reset) begin
        cursor_x <= 5'd0;
        cursor_y <= 4'd0;
        scroll_offset <= 4'd0;
        vram_clear_cnt <= 9'd0;
        vram_clearing <= 1'b1;
        scrolling <= 1'b0;
    end
    else if (vram_clearing) begin
        // Clear video RAM at reset
        video_ram[vram_clear_cnt] <= 7'h20;  // Space
        if (vram_clear_cnt == 9'd511) begin
            vram_clearing <= 1'b0;
        end
        else begin
            vram_clear_cnt <= vram_clear_cnt + 9'd1;
        end
    end
    else if (scrolling) begin
        // Clear la nuova riga in fondo (ora è la vecchia riga 0)
        video_ram[{scroll_offset, scroll_col}] <= 7'h20;
        if (scroll_col == 5'd31) begin
            scrolling <= 1'b0;
        end
        else begin
            scroll_col <= scroll_col + 5'd1;
        end
    end
    else if (dsp_write_strobe) begin
        if (dsp_char == 7'h0D) begin
            // CR - new line
            cursor_x <= 5'd0;
            if (cursor_y < ROWS - 1) begin
                cursor_y <= cursor_y + 4'd1;
            end
            else begin
                // SCROLL! Incrementa offset invece di wrap
                scroll_offset <= scroll_offset + 4'd1;
                // Avvia pulizia della nuova riga vuota
                scrolling <= 1'b1;
                scroll_col <= 5'd0;
            end
        end
        else if (dsp_char == 7'h08 || dsp_char == 7'h5F) begin
            // BACKSPACE (0x08) o UNDERSCORE (0x5F) - rubout come Apple I originale
            if (cursor_x > 0) begin
                cursor_x <= cursor_x - 5'd1;
                // Cancella il carattere precedente con spazio
                video_ram[{phys_row, cursor_x - 5'd1}] <= 7'h20;
            end
        end
        else if (dsp_char >= 7'h20 && dsp_char < 7'h7F) begin
            // Printable character - scrivi nella riga fisica
            video_ram[{phys_row, cursor_x}] <= dsp_char;
            if (cursor_x < COLS - 1)
                cursor_x <= cursor_x + 5'd1;
            else begin
                cursor_x <= 5'd0;
                if (cursor_y < ROWS - 1) begin
                    cursor_y <= cursor_y + 4'd1;
                end
                else begin
                    // SCROLL quando si raggiunge fine riga sull'ultima riga
                    scroll_offset <= scroll_offset + 4'd1;
                    scrolling <= 1'b1;
                    scroll_col <= 5'd0;
                end
            end
        end
    end
end

//==============================================================================
// VGA TIMING - Dual Resolution Support
// res_mode=0: 640x480 @ 60Hz (25 MHz pixel clock)
// res_mode=1: 800x600 @ 72Hz (50 MHz pixel clock)
//==============================================================================

// Pixel clock divider per 640x480
reg pix_clk_div;
always @(posedge clk)
    if (cpu_reset) pix_clk_div <= 0;
    else pix_clk_div <= ~pix_clk_div;

wire pix_clk_en = res_mode ? 1'b1 : pix_clk_div;

// Timing parameters
wire [10:0] H_VISIBLE = res_mode ? 11'd800  : 11'd640;
wire [10:0] H_FRONT   = res_mode ? 11'd56   : 11'd16;
wire [10:0] H_SYNC    = res_mode ? 11'd120  : 11'd96;
wire [10:0] H_TOTAL   = res_mode ? 11'd1040 : 11'd800;
wire [9:0]  V_VISIBLE = res_mode ? 10'd600  : 10'd480;
wire [9:0]  V_FRONT   = res_mode ? 10'd37   : 10'd10;
wire [9:0]  V_SYNC    = res_mode ? 10'd6    : 10'd2;
wire [9:0]  V_TOTAL   = res_mode ? 10'd666  : 10'd525;

// Apple I: 32x16 chars, 8x8 pixels = 256x128, scaling 2x = 512x256
// 800x600: Centro (800-512)/2=144, (600-256)/2=172
// 640x480: Centro (640-512)/2=64, (480-256)/2=112
wire [10:0] DISP_H_START = res_mode ? 11'd144 : 11'd64;
wire [10:0] DISP_H_END   = res_mode ? 11'd656 : 11'd576;
wire [9:0]  DISP_V_START = res_mode ? 10'd172 : 10'd112;
wire [9:0]  DISP_V_END   = res_mode ? 10'd428 : 10'd368;

reg [10:0] h_count;
reg [9:0] v_count;

always @(posedge clk) begin
    if (cpu_reset) begin
        h_count <= 11'd0;
        v_count <= 10'd0;
    end
    else if (pix_clk_en) begin
        if (h_count == H_TOTAL - 1) begin
            h_count <= 11'd0;
            if (v_count == V_TOTAL - 1)
                v_count <= 10'd0;
            else
                v_count <= v_count + 10'd1;
        end
        else
            h_count <= h_count + 11'd1;
    end
end

always @(posedge clk) begin
    if (cpu_reset) begin
        vga_hs <= 1'b1;
        vga_vs <= 1'b1;
    end
    else begin
        vga_hs <= ~(h_count >= (H_VISIBLE + H_FRONT) && 
                    h_count < (H_VISIBLE + H_FRONT + H_SYNC));
        vga_vs <= ~(v_count >= (V_VISIBLE + V_FRONT) && 
                    v_count < (V_VISIBLE + V_FRONT + V_SYNC));
    end
end

//==============================================================================
// CHARACTER RENDERING
//==============================================================================
wire visible = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);

// Display area - centered
wire in_display = (h_count >= DISP_H_START && h_count < DISP_H_END) &&
                  (v_count >= DISP_V_START && v_count < DISP_V_END);

wire [4:0] disp_col = (h_count - DISP_H_START) >> 4;
wire [3:0] disp_row = (v_count - DISP_V_START) >> 4;

// Aggiungi scroll_offset per ottenere la riga fisica
wire [3:0] phys_disp_row = disp_row + scroll_offset;
wire [8:0] char_addr = {phys_disp_row, disp_col};
wire [6:0] current_char = video_ram[char_addr];

// Font lookup
wire [2:0] pixel_row = ((v_count - DISP_V_START) >> 1) & 3'b111;
wire [2:0] pixel_col = 3'd7 - (((h_count - DISP_H_START) >> 1) & 3'b111);

wire [5:0] font_char = (current_char >= 7'h20 && current_char < 7'h60) ? 
                       (current_char - 7'h20) : 6'd0;
wire [8:0] font_addr = {font_char, pixel_row};
wire [7:0] font_data;

apple1_font_rom font (
    .clk(clk),
    .addr(font_addr),
    .data(font_data)
);

wire char_pixel = font_data[pixel_col];

// Cursor blink
reg [22:0] blink_counter;
wire cursor_on = blink_counter[22];
always @(posedge clk) blink_counter <= blink_counter + 23'd1;

wire at_cursor = (disp_col == cursor_x) && (disp_row == cursor_y);
wire show_pixel = char_pixel || (at_cursor && cursor_on);

// Green phosphor
always @(posedge clk) begin
    if (!visible) begin
        vga_r <= 4'h0;
        vga_g <= 4'h0;
        vga_b <= 4'h0;
    end
    else if (in_display && show_pixel) begin
        vga_r <= 4'h0;
        vga_g <= 4'hF;
        vga_b <= 4'h0;
    end
    else begin
        vga_r <= 4'h0;
        vga_g <= 4'h1;  // Slight glow
        vga_b <= 4'h0;
    end
end

assign audio_out = 1'b0;
assign debug_out = cpu_addr[8];

endmodule
