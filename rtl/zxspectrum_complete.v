//==============================================================================
// ZX Spectrum 48K - Implementazione Completa
//==============================================================================
// Autore: Angelo Arato  
// Data: Dicembre 2025
//
// Emulazione ZX Spectrum 48K:
// - CPU Z80 @ 3.5 MHz (T80 core)
// - 48KB RAM + 16KB ROM
// - ULA: Video 256x192, attributi colore 32x24
// - Tastiera matrice 8x5
// - Border color
// - Audio beeper
//==============================================================================

module zxspectrum_complete (
    input  wire        clk,           // 50 MHz
    input  wire        reset_n,
    input  wire        enable,
    input  wire        res_mode,      // 0=640x480, 1=800x600
    
    // VGA output
    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b,
    output reg         vga_hs,
    output reg         vga_vs,
    
    // Keyboard input - supporta anche token diretti (>= 0xA5)
    input  wire [7:0]  key_row_data,
    input  wire [7:0]  key_addr,
    input  wire        key_strobe,
    
    // Audio output
    output wire        audio_out,
    
    // ROM loading interface  
    input  wire        rom_load_en,
    input  wire [13:0] rom_load_addr,
    input  wire [7:0]  rom_load_data,
    input  wire        rom_load_wr,
    
    // RAM loading interface (usato anche per inserire linee BASIC tokenizzate)
    input  wire        ram_load_en,
    input  wire [15:0] ram_load_addr,
    input  wire [7:0]  ram_load_data,
    input  wire        ram_load_wr,
    
    // Debug
    output wire [15:0] debug_pc,
    output wire [7:0]  debug_ir
);

//==============================================================================
// CLOCK GENERATION
//==============================================================================
reg [3:0] clk_div;
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) clk_div <= 4'd0;
    else clk_div <= (clk_div == 4'd13) ? 4'd0 : clk_div + 4'd1;
end
wire cpu_clk_en = (clk_div == 4'd0) && enable;

//==============================================================================
// CPU Z80 (T80)
//==============================================================================
wire [15:0] cpu_addr;
wire [7:0]  cpu_data_out;
reg  [7:0]  cpu_data_in;
wire        cpu_wr;
wire        cpu_rd;
wire        cpu_iorq;
wire        cpu_mreq;
wire        cpu_m1_n;
wire        cpu_halt_n;
wire        cpu_rfsh_n;
reg         cpu_int_n;

T80_wrapper cpu (
    .clk(clk), .reset_n(reset_n), .enable(cpu_clk_en),
    .addr(cpu_addr), .data_in(cpu_data_in), .data_out(cpu_data_out),
    .we(cpu_wr), .rd(cpu_rd), .iorq(cpu_iorq), .mreq(cpu_mreq),
    .m1_n(cpu_m1_n), .int_n(cpu_int_n), .nmi_n(1'b1), .wait_n(1'b1),
    .halt_n(cpu_halt_n), .rfsh_n(cpu_rfsh_n)
);

assign debug_pc = cpu_addr;
assign debug_ir = cpu_data_in;

//==============================================================================
// MEMORIA
//==============================================================================
wire [7:0] rom_data_out;
wire [7:0] ram_data_out;
wire [7:0] vram_data_out;
wire rom_sel = (cpu_addr[15:14] == 2'b00);
wire ram_sel = (cpu_addr[15:14] != 2'b00);
wire [15:0] ram_addr = cpu_addr - 16'h4000;

// Video RAM address wiring (generato dalla ULA sotto)
wire [15:0] video_addr; 

zx_rom_16k rom_inst (
    .clk(clk), .addr_a(cpu_addr[13:0]), .q_a(rom_data_out),
    .addr_b(rom_load_addr), .data_b(rom_load_data), .we_b(rom_load_en && rom_load_wr)
);

zx_ram_48k ram_inst (
    .clk(clk),
    .addr_a(ram_addr[15:0]), .data_a(cpu_data_out), .we_a(ram_sel && cpu_wr && cpu_mreq && !cpu_iorq && enable), .q_a(ram_data_out),
    .addr_b(video_addr), .q_b(vram_data_out),
    .load_addr(ram_load_addr - 16'h4000), .load_data(ram_load_data), .load_we(ram_load_en && ram_load_wr && ram_load_addr >= 16'h4000)
);

//==============================================================================
// I/O PORTS & KEYBOARD
//==============================================================================
reg [2:0] border_color;
reg       beeper;
reg [4:0] key_matrix [0:7];
wire io_fe_sel = cpu_iorq && (cpu_addr[0] == 1'b0);

reg [19:0] key_release_timer;
reg key_pending;
reg [7:0] key_latched;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        border_color <= 3'd7; // Default Bordo Bianco
        beeper <= 1'b0;
        key_release_timer <= 20'd0;
        key_pending <= 1'b0;
        key_latched <= 8'h00;
        key_matrix[0]<=5'b11111; key_matrix[1]<=5'b11111; key_matrix[2]<=5'b11111; key_matrix[3]<=5'b11111;
        key_matrix[4]<=5'b11111; key_matrix[5]<=5'b11111; key_matrix[6]<=5'b11111; key_matrix[7]<=5'b11111;
    end
    else begin
        // Key latching logic (identica a prima)
        if (key_strobe) begin
            key_pending <= 1'b1;
            key_latched <= key_addr;
        end else if (key_release_timer > 20'd999000) begin
            key_pending <= 1'b0;
        end
        
        if (key_release_timer > 0) key_release_timer <= key_release_timer - 1'd1;
        else begin
            key_matrix[0]<=5'b11111; key_matrix[1]<=5'b11111; key_matrix[2]<=5'b11111; key_matrix[3]<=5'b11111;
            key_matrix[4]<=5'b11111; key_matrix[5]<=5'b11111; key_matrix[6]<=5'b11111; key_matrix[7]<=5'b11111;
        end
        
        if (key_pending && enable) begin
            key_release_timer <= 20'd1000000;
            key_matrix[0]<=5'b11111; key_matrix[1]<=5'b11111; key_matrix[2]<=5'b11111; key_matrix[3]<=5'b11111;
            key_matrix[4]<=5'b11111; key_matrix[5]<=5'b11111; key_matrix[6]<=5'b11111; key_matrix[7]<=5'b11111;
            
            case (key_latched)
                "A", "a": key_matrix[1] <= 5'b11110; "B", "b": key_matrix[7] <= 5'b01111;
                "C", "c": key_matrix[0] <= 5'b10111; "D", "d": key_matrix[1] <= 5'b11011;
                "E", "e": key_matrix[2] <= 5'b11011; "F", "f": key_matrix[1] <= 5'b10111;
                "G", "g": key_matrix[1] <= 5'b01111; "H", "h": key_matrix[6] <= 5'b01111;
                "I", "i": key_matrix[5] <= 5'b11011; "J", "j": key_matrix[6] <= 5'b10111;
                "K", "k": key_matrix[6] <= 5'b11011; "L", "l": key_matrix[6] <= 5'b11101;
                "M", "m": key_matrix[7] <= 5'b11011; "N", "n": key_matrix[7] <= 5'b10111;
                "O", "o": key_matrix[5] <= 5'b11101; "P", "p": key_matrix[5] <= 5'b11110;
                "Q", "q": key_matrix[2] <= 5'b11110; "R", "r": key_matrix[2] <= 5'b10111;
                "S", "s": key_matrix[1] <= 5'b11101; "T", "t": key_matrix[2] <= 5'b01111;
                "U", "u": key_matrix[5] <= 5'b10111; "V", "v": key_matrix[0] <= 5'b01111;
                "W", "w": key_matrix[2] <= 5'b11101; "X", "x": key_matrix[0] <= 5'b11011;
                "Y", "y": key_matrix[5] <= 5'b01111; "Z", "z": key_matrix[0] <= 5'b11101;
                "0": key_matrix[4] <= 5'b11110; "1": key_matrix[3] <= 5'b11110;
                "2": key_matrix[3] <= 5'b11101; "3": key_matrix[3] <= 5'b11011;
                "4": key_matrix[3] <= 5'b10111; "5": key_matrix[3] <= 5'b01111;
                "6": key_matrix[4] <= 5'b01111; "7": key_matrix[4] <= 5'b10111;
                "8": key_matrix[4] <= 5'b11011; "9": key_matrix[4] <= 5'b11101;
                8'd34: begin key_matrix[7] <= 5'b11101; key_matrix[5] <= 5'b11110; end // "
                8'd36: begin key_matrix[7] <= 5'b11101; key_matrix[3] <= 5'b10111; end // $
                8'd61: begin key_matrix[7] <= 5'b11101; key_matrix[6] <= 5'b11101; end // =
                8'd43: begin key_matrix[7] <= 5'b11101; key_matrix[6] <= 5'b11011; end // +
                8'd45: begin key_matrix[7] <= 5'b11101; key_matrix[6] <= 5'b10111; end // -
                8'd42: begin key_matrix[7] <= 5'b01101; end // * (SYM+B)
                8'd47: begin key_matrix[7] <= 5'b11101; key_matrix[0] <= 5'b01111; end // /
                8'd60: begin key_matrix[7] <= 5'b11101; key_matrix[2] <= 5'b10111; end // <
                8'd62: begin key_matrix[7] <= 5'b11101; key_matrix[2] <= 5'b01111; end // >
                8'd59: begin key_matrix[7] <= 5'b11101; key_matrix[5] <= 5'b11101; end // ;
                8'd58: begin key_matrix[7] <= 5'b11101; key_matrix[0] <= 5'b11101; end // :
                8'd40: begin key_matrix[7] <= 5'b11101; key_matrix[4] <= 5'b11011; end // (
                8'd41: begin key_matrix[7] <= 5'b11101; key_matrix[4] <= 5'b11101; end // )
                8'd13: key_matrix[6] <= 5'b11110; // ENTER
                8'd32: key_matrix[7] <= 5'b11110; // SPACE
                8'd33: begin key_matrix[7] <= 5'b11101; key_matrix[3] <= 5'b11110; end // !
                8'd35: begin key_matrix[7] <= 5'b11101; key_matrix[3] <= 5'b11011; end // #
                8'd37: begin key_matrix[7] <= 5'b11101; key_matrix[3] <= 5'b01111; end // %
                8'd38: begin key_matrix[7] <= 5'b11101; key_matrix[4] <= 5'b01111; end // &
                8'd39: begin key_matrix[7] <= 5'b11101; key_matrix[4] <= 5'b10111; end // '
                8'd44: begin key_matrix[7] <= 5'b10101; end // ,
                8'd46: begin key_matrix[7] <= 5'b11001; end // .
                8'd63: begin key_matrix[7] <= 5'b11101; key_matrix[0] <= 5'b10111; end // ?
                8'd64: begin key_matrix[7] <= 5'b11101; key_matrix[3] <= 5'b11101; end // @
                8'd95: begin key_matrix[7] <= 5'b11101; key_matrix[4] <= 5'b11110; end // _
                8'd8, 8'd127: begin key_matrix[0] <= 5'b11110; key_matrix[4] <= 5'b11110; end // Backspace
                
                // ========== ZX SPECTRUM TOKENS (corretti) ==========
                // I token vengono convertiti nelle pressioni K-mode corrispondenti
                
                // === Token K-mode (0xE6-0xFF) ===
                // Questi sono i token delle keyword principali
                
                8'hE6: key_matrix[1] <= 5'b11110;  // NEW (0xE6) -> A
                8'hE7: key_matrix[7] <= 5'b01111;  // BORDER (0xE7) -> B
                8'hE8: key_matrix[0] <= 5'b10111;  // CONTINUE (0xE8) -> C
                8'hE9: key_matrix[1] <= 5'b11011;  // DIM (0xE9) -> D
                8'hEA: key_matrix[2] <= 5'b11011;  // REM (0xEA) -> E
                8'hEB: key_matrix[1] <= 5'b10111;  // FOR (0xEB) -> F
                8'hEC: key_matrix[1] <= 5'b01111;  // GOTO (0xEC) -> G
                8'hED: key_matrix[6] <= 5'b01111;  // GOSUB (0xED) -> H
                8'hEE: key_matrix[5] <= 5'b11011;  // INPUT (0xEE) -> I
                8'hEF: key_matrix[6] <= 5'b10111;  // LOAD (0xEF) -> J
                8'hF0: key_matrix[6] <= 5'b11011;  // LIST (0xF0) -> K
                8'hF1: key_matrix[6] <= 5'b11101;  // LET (0xF1) -> L
                8'hF2: key_matrix[7] <= 5'b11011;  // PAUSE (0xF2) -> M
                8'hF3: key_matrix[7] <= 5'b10111;  // NEXT (0xF3) -> N
                8'hF4: key_matrix[5] <= 5'b11101;  // POKE (0xF4) -> O
                8'hF5: key_matrix[5] <= 5'b11110;  // PRINT (0xF5) -> P
                8'hF6: key_matrix[2] <= 5'b11110;  // PLOT (0xF6) -> Q
                8'hF7: key_matrix[2] <= 5'b10111;  // RUN (0xF7) -> R
                8'hF8: key_matrix[1] <= 5'b11101;  // SAVE (0xF8) -> S
                8'hF9: key_matrix[2] <= 5'b01111;  // RANDOMIZE (0xF9) -> T
                8'hFA: key_matrix[5] <= 5'b10111;  // IF (0xFA) -> U
                8'hFB: key_matrix[0] <= 5'b01111;  // CLS (0xFB) -> V
                8'hFC: key_matrix[2] <= 5'b11101;  // DRAW (0xFC) -> W
                8'hFD: key_matrix[0] <= 5'b11011;  // CLEAR (0xFD) -> X
                8'hFE: key_matrix[5] <= 5'b01111;  // RETURN (0xFE) -> Y
                8'hFF: key_matrix[0] <= 5'b11101;  // COPY (0xFF) -> Z
                
                // === Token SYMBOL SHIFT (0xC0-0xE5) ===
                // Questi richiedono SYMBOL SHIFT + tasto
                
                8'hCB: begin key_matrix[7] <= 5'b11101; key_matrix[1] <= 5'b01111; end  // THEN = SYM+G
                8'hCC: begin key_matrix[7] <= 5'b11101; key_matrix[1] <= 5'b10111; end  // TO = SYM+F
                8'hCD: begin key_matrix[7] <= 5'b11101; key_matrix[1] <= 5'b11011; end  // STEP = SYM+D
                8'hC6: begin key_matrix[7] <= 5'b11101; key_matrix[5] <= 5'b01111; end  // AND = SYM+Y
                8'hC5: begin key_matrix[7] <= 5'b11101; key_matrix[5] <= 5'b10111; end  // OR = SYM+U
                8'hC3: begin key_matrix[7] <= 5'b11101; key_matrix[1] <= 5'b11101; end  // NOT = SYM+S
                8'hBE: begin key_matrix[7] <= 5'b11101; key_matrix[5] <= 5'b11101; end  // PEEK = SYM+O
                8'hDF: begin key_matrix[7] <= 5'b11101; key_matrix[5] <= 5'b11110; end  // OUT = SYM+P (nota: diverso da K-mode)
                8'hE4: begin key_matrix[7] <= 5'b11101; key_matrix[2] <= 5'b11011; end  // DATA = SYM+E
                8'hE3: begin key_matrix[7] <= 5'b11101; key_matrix[1] <= 5'b11110; end  // READ = SYM+A
                8'hE5: begin key_matrix[7] <= 5'b11101; key_matrix[0] <= 5'b10111; end  // RESTORE = SYM+C
                8'hE2: begin key_matrix[7] <= 5'b11101; key_matrix[1] <= 5'b11110; end  // STOP = SYM+A (stesso di READ!)
                
                // === Token funzioni (0xB0-0xBF) ===
                8'hB0: begin key_matrix[7] <= 5'b11101; key_matrix[6] <= 5'b10111; end  // VAL = SYM+J
                8'hB1: begin key_matrix[7] <= 5'b11101; key_matrix[6] <= 5'b11011; end  // LEN = SYM+K
                8'hBA: begin key_matrix[7] <= 5'b11101; key_matrix[2] <= 5'b10111; end  // INT = SYM+R
                8'hBD: begin key_matrix[7] <= 5'b11101; key_matrix[1] <= 5'b01111; end  // ABS = SYM+G (conflict!)
                8'hC0: begin key_matrix[7] <= 5'b11101; key_matrix[6] <= 5'b11101; end  // USR = SYM+L
                8'hC1: begin key_matrix[7] <= 5'b11101; key_matrix[5] <= 5'b01111; end  // STR$ = SYM+Y (conflict!)
                8'hC2: begin key_matrix[7] <= 5'b11101; key_matrix[5] <= 5'b10111; end  // CHR$ = SYM+U (conflict!)
                
                // === Altri token grafici ===
                8'hD7: begin key_matrix[7] <= 5'b11101; key_matrix[0] <= 5'b11101; end  // BEEP = SYM+Z
                8'hD8: begin key_matrix[7] <= 5'b11101; key_matrix[6] <= 5'b01111; end  // CIRCLE = SYM+H
                8'hD9: begin key_matrix[7] <= 5'b11101; key_matrix[0] <= 5'b11011; end  // INK = SYM+X
                8'hDA: begin key_matrix[7] <= 5'b11101; key_matrix[0] <= 5'b10111; end  // PAPER = SYM+C
                8'hDB: begin key_matrix[7] <= 5'b11101; key_matrix[0] <= 5'b01111; end  // FLASH = SYM+V
                8'hDC: begin key_matrix[7] <= 5'b11101; key_matrix[7] <= 5'b01111; end  // BRIGHT = SYM+B
                8'hDE: begin key_matrix[7] <= 5'b11101; key_matrix[7] <= 5'b10111; end  // OVER = SYM+N
                8'hD6: begin key_matrix[7] <= 5'b11101; key_matrix[2] <= 5'b10111; end  // VERIFY = SYM+R
                8'hE0: begin key_matrix[7] <= 5'b11101; key_matrix[0] <= 5'b10111; end  // LPRINT = SYM+C
                8'hE1: begin key_matrix[7] <= 5'b11101; key_matrix[0] <= 5'b01111; end  // LLIST = SYM+V
                
                default: ;
            endcase
        end
        
        if (enable && io_fe_sel && cpu_wr) begin
            border_color <= cpu_data_out[2:0];
            beeper <= cpu_data_out[4];
        end
    end
end

wire [4:0] key_data;
assign key_data = (cpu_addr[8]  ? 5'b11111 : key_matrix[0]) &
                  (cpu_addr[9]  ? 5'b11111 : key_matrix[1]) &
                  (cpu_addr[10] ? 5'b11111 : key_matrix[2]) &
                  (cpu_addr[11] ? 5'b11111 : key_matrix[3]) &
                  (cpu_addr[12] ? 5'b11111 : key_matrix[4]) &
                  (cpu_addr[13] ? 5'b11111 : key_matrix[5]) &
                  (cpu_addr[14] ? 5'b11111 : key_matrix[6]) &
                  (cpu_addr[15] ? 5'b11111 : key_matrix[7]);

assign audio_out = beeper;

//==============================================================================
// CPU DATA BUS MUX
//==============================================================================
always @(*) begin
    if (cpu_iorq && !cpu_mreq) begin
        if (io_fe_sel) cpu_data_in = {1'b1, 1'b1, 1'b1, key_data};
        else cpu_data_in = 8'hFF;
    end
    else if (cpu_mreq) begin
        if (rom_sel) cpu_data_in = rom_data_out;
        else cpu_data_in = ram_data_out;
    end
    else cpu_data_in = 8'hFF;
end

//==============================================================================
// VIDEO - ULA (CORRECTED FETCH CYCLE & DEFAULT COLORS)
//==============================================================================

//==============================================================================
// VGA TIMING - Dual Resolution Support
// res_mode=0: 640x480 @ 60Hz (25 MHz pixel clock)
// res_mode=1: 800x600 @ 72Hz (50 MHz pixel clock)
//==============================================================================

// Pixel clock divider per 640x480
reg pix_clk_div;
always @(posedge clk or negedge reset_n)
    if (!reset_n) pix_clk_div <= 0;
    else pix_clk_div <= ~pix_clk_div;

wire pix_clk_en = res_mode ? 1'b1 : pix_clk_div;

// Timing parameters
wire [10:0] H_TOTAL   = res_mode ? 11'd1040 : 11'd800;
wire [10:0] H_VISIBLE = res_mode ? 11'd800  : 11'd640;
wire [10:0] H_FRONT   = res_mode ? 11'd56   : 11'd16;
wire [10:0] H_SYNC    = res_mode ? 11'd120  : 11'd96;
wire [9:0]  V_TOTAL   = res_mode ? 10'd666  : 10'd525;
wire [9:0]  V_VISIBLE = res_mode ? 10'd600  : 10'd480;
wire [9:0]  V_FRONT   = res_mode ? 10'd37   : 10'd10;
wire [9:0]  V_SYNC    = res_mode ? 10'd6    : 10'd2;

// ZX Spectrum: 256x192 nativo, scaling 2x = 512x384
// 800x600: Centro H=(800-512)/2=144, V=(600-384)/2=108
// 640x480: Centro H=(640-512)/2=64, V=(480-384)/2=48
wire [10:0] DISP_H_START = res_mode ? 11'd144 : 11'd64;
wire [10:0] DISP_H_END   = res_mode ? 11'd656 : 11'd576;
wire [9:0]  DISP_V_START = res_mode ? 10'd108 : 10'd48;
wire [9:0]  DISP_V_END   = res_mode ? 10'd492 : 10'd432;

reg [10:0] h_count;
reg [9:0] v_count;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin h_count <= 0; v_count <= 0; end
    else if (enable && pix_clk_en) begin
        if (h_count == H_TOTAL - 1) begin
            h_count <= 0;
            if (v_count == V_TOTAL - 1) v_count <= 0;
            else v_count <= v_count + 1;
        end else h_count <= h_count + 1;
    end
end

always @(posedge clk) begin
    vga_hs <= ~(h_count >= (H_VISIBLE + H_FRONT) && h_count < (H_VISIBLE + H_FRONT + H_SYNC));
    vga_vs <= ~(v_count >= (V_VISIBLE + V_FRONT) && v_count < (V_VISIBLE + V_FRONT + V_SYNC));
end

// Area display Spectrum
wire in_display = (h_count >= DISP_H_START && h_count < DISP_H_END) && 
                  (v_count >= DISP_V_START && v_count < DISP_V_END);
wire in_border  = (h_count < H_VISIBLE) && (v_count < V_VISIBLE) && !in_display;

wire [8:0] raw_x = h_count - DISP_H_START;
wire [8:0] raw_y = v_count - DISP_V_START;
wire [7:0] spec_x = raw_x[8:1];
wire [7:0] spec_y = raw_y[8:1];

// --- Calcolo Indirizzi RAM Video ---
wire [12:0] addr_pix  = {spec_y[7:6], spec_y[2:0], spec_y[5:3], spec_x[7:3]};
wire [12:0] addr_attr = {3'b110, spec_y[7:3], spec_x[7:3]};

// --- FETCH SEQUENCER ---
reg [15:0] vga_addr_reg;
assign video_addr = vga_addr_reg;
reg [7:0] fetched_pixel;
reg [7:0] fetched_attr;
reg [7:0] shift_reg;
reg [7:0] attr_latch;
reg [7:0] spec_x_prev;

always @(posedge clk) begin
    if (h_count[2:0] == 3'b000) vga_addr_reg <= {3'b000, addr_attr};
    if (h_count[2:0] == 3'b010) fetched_attr <= vram_data_out;
    if (h_count[2:0] == 3'b010) vga_addr_reg <= {3'b000, addr_pix};
    if (h_count[2:0] == 3'b100) fetched_pixel <= vram_data_out;
    
    spec_x_prev <= spec_x;
    if (in_display) begin
        if (spec_x[2:0] == 3'b000 && spec_x != spec_x_prev) begin
            shift_reg  <= fetched_pixel;
            attr_latch <= fetched_attr;
        end
        else if (spec_x != spec_x_prev) begin
            shift_reg <= {shift_reg[6:0], 1'b0};
        end
    end
end

// --- COLOR DECODING (CON FIX PER RAM VUOTA) ---
// Se attr_latch è 0x00 (RAM non inizializzata), forza il default Sinclair:
// PAPER = 7 (Bianco), INK = 0 (Nero), Bright=0, Flash=0.
wire attr_is_zero = (attr_latch == 8'h00);
// Attributo standard ROM: paper=0 (nero), ink=7 (bianco) = 8'b00111000 = 8'h38
wire attr_is_default = (attr_latch == 8'h38) || (attr_latch == 8'h00);

wire flash_en = attr_is_zero ? 1'b0 : attr_latch[7];
wire bright   = attr_is_zero ? 1'b0 : attr_latch[6];
// Se attributi sono default/zero, usa grigio(7)/nero(0), altrimenti usa dinamici
wire [2:0] paper = attr_is_default ? 3'd7 : attr_latch[5:3];
wire [2:0] ink   = attr_is_default ? 3'd0 : attr_latch[2:0];

// Flash counter
reg [4:0] f_cnt; reg f_state;
always @(posedge clk) begin
    if (v_count == 0 && h_count == 0) f_cnt <= f_cnt + 1;
    if (f_cnt == 16) begin f_cnt <= 0; f_state <= ~f_state; end
end

// Pixel finale
wire p_bit = shift_reg[7];
wire use_ink = flash_en ? (f_state ? ~p_bit : p_bit) : p_bit;
wire [2:0] final_col = use_ink ? ink : paper;

// Palette Spectrum
function [11:0] get_color;
    input [2:0] col; input br;
    begin
        case ({br, col})
            4'b0000: get_color = 12'h000; // Black
            4'b0001: get_color = 12'h00A; // Blue
            4'b0010: get_color = 12'hA00; // Red
            4'b0011: get_color = 12'hA0A; // Magenta
            4'b0100: get_color = 12'h0A0; // Green
            4'b0101: get_color = 12'h0AA; // Cyan
            4'b0110: get_color = 12'hAA0; // Yellow
            4'b0111: get_color = 12'hAAA; // White
            4'b1000: get_color = 12'h000; // Bright Black
            4'b1001: get_color = 12'h00F; // Bright Blue
            4'b1010: get_color = 12'hF00; // Bright Red
            4'b1011: get_color = 12'hF0F; // Bright Magenta
            4'b1100: get_color = 12'h0F0; // Bright Green
            4'b1101: get_color = 12'h0FF; // Bright Cyan
            4'b1110: get_color = 12'hFF0; // Bright Yellow
            4'b1111: get_color = 12'hFFF; // Bright White
        endcase
    end
endfunction

wire [11:0] rgb_out = get_color(final_col, bright);
wire [11:0] brd_out = get_color(border_color, 1'b0);  // Border color dal registro ULA 

always @(posedge clk) begin
    if (in_display) begin
        vga_r <= rgb_out[11:8]; 
        vga_g <= rgb_out[7:4]; 
        vga_b <= rgb_out[3:0];
    end else if (in_border) begin
        // Se border_color è 7 (bianco), brd_out sarà FFF (bianco).
        vga_r <= brd_out[11:8]; 
        vga_g <= brd_out[7:4]; 
        vga_b <= brd_out[3:0];
    end else begin
        vga_r <= 0; vga_g <= 0; vga_b <= 0; // Blanking (fuori schermo)
    end
end

//==============================================================================
// INTERRUPT GENERATION
//==============================================================================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) cpu_int_n <= 1'b1;
    else if (enable) begin
        if (v_count == V_VISIBLE && h_count == 0) cpu_int_n <= 1'b0;
        else if (v_count == V_VISIBLE + 1) cpu_int_n <= 1'b1;
    end
end

endmodule