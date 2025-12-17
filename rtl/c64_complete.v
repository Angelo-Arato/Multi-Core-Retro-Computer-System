//==============================================================================
// C64 COMPLETE - SHARED RAM VERSION (CLEAN - NO VIRTUAL LOAD)
//==============================================================================
// Versione pulita per debug caricamento PRG
// Supporta dual resolution (640x480 / 800x600)
//==============================================================================

module c64_complete (
    input  wire        clk,           // 50 MHz
    input  wire        reset_n,
    input  wire        enable,
    input  wire        res_mode,      // 0=640x480, 1=800x600
    
    // SHARED RAM interface
    output wire [15:0] ext_ram_addr,
    output wire [7:0]  ext_ram_dout,
    input  wire [7:0]  ext_ram_din,
    output wire        ext_ram_we,
    
    // Non usato (mantenuto per compatibilita)
    output wire [15:0] video_ram_addr,
    input  wire [7:0]  video_ram_din,
    
    // ROM loader interface
    input  wire [15:0] rom_addr,
    input  wire [7:0]  rom_data,
    input  wire        rom_we,
    input  wire [1:0]  rom_bank,
    
    // PRG loader interface
    input  wire [15:0] prg_addr,
    input  wire [7:0]  prg_data,
    input  wire        prg_we,
    
    // Keyboard
    input  wire        key_strobe,
    input  wire [7:0]  key_code,
    
    // LOAD virtuale - STUB (non implementato)
    output wire        load_req,
    output wire [127:0] load_filename,
    output wire  [3:0] load_filename_len,
    output wire  [7:0] load_device,
    output wire        load_secondary,
    input  wire        load_active,
    input  wire        load_complete,
    input  wire        load_error,
    input  wire [15:0] load_end_addr,
    
    // Virtual Drive I/O - STUB
    output wire [4:0]  vdrive_addr,
    output wire [7:0]  vdrive_data_out,
    input  wire [7:0]  vdrive_data_in,
    output wire        vdrive_we,
    output wire        vdrive_cs,
    
    // VGA
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync
);

// LOAD virtuale disabilitato
assign load_req = 0;
assign load_filename = 0;
assign load_filename_len = 0;
assign load_device = 0;
assign load_secondary = 0;

// Virtual Drive STUB
assign vdrive_addr = 5'd0;
assign vdrive_data_out = 8'd0;
assign vdrive_we = 1'b0;
assign vdrive_cs = 1'b0;

//==============================================================================
// CLOCK GENERATION - 1 MHz CPU clock
//==============================================================================
reg [5:0] clk_div;
wire cpu_clk_en = (clk_div == 6'd49);

always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
        clk_div <= 0;
    else if (clk_div == 6'd49)
        clk_div <= 0;
    else
        clk_div <= clk_div + 1'd1;
end

//==============================================================================
// CPU 6502
//==============================================================================
wire [15:0] cpu_addr;
wire [7:0]  cpu_data_out;
reg  [7:0]  cpu_data_in;
wire        cpu_we;
wire        cpu_irq_n;

T65_wrapper cpu (
    .clk(clk),
    .enable(cpu_clk_en & enable),
    .reset_n(reset_n),
    .addr(cpu_addr),
    .data_in(cpu_data_in),
    .data_out(cpu_data_out),
    .we(cpu_we),
    .irq_n(cpu_irq_n),
    .nmi_n(1'b1),
    .rdy(1'b1),
    .sync()
);

//==============================================================================
// SHARED RAM ACCESS
//==============================================================================
// CPU puo scrivere in RAM ($0000-$9FFF, $C000-$CFFF)
wire cpu_ram_area = (cpu_addr < 16'hA000) || 
                    (cpu_addr >= 16'hC000 && cpu_addr < 16'hD000);

assign ext_ram_addr = cpu_addr;
assign ext_ram_dout = cpu_data_out;
assign ext_ram_we = cpu_we && enable && cpu_ram_area;

assign video_ram_addr = 16'h0000;

//==============================================================================
// CHARACTER ROM 4KB (interno)
//==============================================================================
wire chargen_we = rom_we && (rom_bank == 2'd2);
wire [11:0] char_rom_addr;
wire [7:0]  char_data;

rom_chargen chargen (
    .clk(clk),
    .addr_read(char_rom_addr),
    .data_read(char_data),
    .addr_write(rom_addr[11:0]),
    .data_write(rom_data),
    .we(chargen_we)
);

//==============================================================================
// Screen RAM 1KB e Color RAM 1KB (interno)
//==============================================================================
reg [7:0] screen_ram [0:1023];
reg [7:0] screen_data;
reg [7:0] color_ram [0:1023];
reg [7:0] color_data;

integer i;
initial begin
    for (i = 0; i < 1024; i = i + 1) begin
        screen_ram[i] = 8'h20;
        color_ram[i] = 8'h0E;
    end
end

wire screen_sel = (cpu_addr >= 16'h0400 && cpu_addr <= 16'h07FF);
wire color_sel = (cpu_addr >= 16'hD800 && cpu_addr <= 16'hDBFF);
wire [9:0] scr_offset = cpu_addr[9:0];

// PRG loader puo scrivere in screen RAM
wire prg_screen_sel = (prg_addr >= 16'h0400 && prg_addr <= 16'h07FF);
wire [9:0] prg_scr_offset = prg_addr[9:0];

always @(posedge clk) begin
    // Read
    screen_data <= screen_ram[scr_offset];
    color_data <= color_ram[cpu_addr[9:0]];
    
    // Write da CPU
    if (cpu_we && enable && screen_sel)
        screen_ram[scr_offset] <= cpu_data_out;
    if (cpu_we && enable && color_sel)
        color_ram[cpu_addr[9:0]] <= cpu_data_out;
    
    // Write da PRG loader
    if (prg_we && prg_screen_sel)
        screen_ram[prg_scr_offset] <= prg_data;
end

//==============================================================================
// VIC-II Registers (semplificati)
//==============================================================================
reg [7:0] vic_border;
reg [7:0] vic_bgcolor;

initial begin
    vic_border = 8'h0E;   // Light blue
    vic_bgcolor = 8'h06;  // Blue
end


//==============================================================================
// VIC-II IRQ (MINIMALE) - solo raster IRQ per far avanzare il jiffy clock
//==============================================================================
// Il KERNAL del C64 usa normalmente il raster IRQ del VIC-II per il tick 50/60Hz.
// Qui implementiamo solo:
// - $D019: IRQ flags (bit0=raster), clear scrivendo 1 sul bit
// - $D01A: IRQ enable (bit0=raster enable)
// Generiamo un evento "raster" usando lo stesso fallback_pulse (60Hz) usato per il CIA.
//==============================================================================
reg  [7:0] vic_irq_flags;   // $D019
reg  [7:0] vic_irq_enable;  // $D01A

// System tick IRQ latch (fallback): garantisce IRQ periodico anche senza VIC/CIA completi
reg        sys_irq_flag;

wire vic_irq;

wire vic_irq_pending = vic_irq_flags[0];
assign vic_irq = vic_irq_pending && vic_irq_enable[0];

initial begin
    vic_irq_flags  = 8'h00;
    vic_irq_enable = 8'h00;
    sys_irq_flag   = 1'b0;
end

//==============================================================================
// CIA1 - Timer A per IRQ - FLIP-FLOP APPROACH
//==============================================================================
// IRQ flag viene SETTATO dal fallback 60Hz
// IRQ flag viene CLEARATO dalla lettura di $DC0D
// Questo è il comportamento corretto dell'hardware reale.
//==============================================================================
reg [15:0] cia1_ta;
reg [15:0] cia1_ta_latch;
reg [7:0]  cia1_cra;
reg [7:0]  cia1_pra;
reg [4:0]  cia1_icr_mask;

// IRQ flip-flop - settato dal fallback, clearato dalla lettura ICR
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

// IRQ attivo quando flag è settato E maschera abilitata
wire cia1_irq = irq_flag && cia1_icr_mask[0];
// VIC-II IRQ (minimal): raster event via fallback tick
wire sys_irq = sys_irq_flag;
assign cpu_irq_n = ~(cia1_irq | vic_irq | sys_irq);

initial begin
    cia1_ta = 16'h4295;
    cia1_ta_latch = 16'h4295;
    cia1_cra = 8'h01;
    cia1_pra = 8'hFF;
    cia1_icr_mask = 5'h01;
    irq_flag = 1'b0;
end

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        cia1_ta <= 16'h4295;
        cia1_ta_latch <= 16'h4295;
        cia1_cra <= 8'h01;
        cia1_pra <= 8'hFF;
        cia1_icr_mask <= 5'h01;
        irq_flag <= 1'b0;
        vic_irq_flags <= 8'h00;
        vic_irq_enable <= 8'h00;
        sys_irq_flag   <= 1'b0;
    end
    else begin
        // FALLBACK: Setta il flag IRQ (pulse di 1 ciclo a 50MHz)
        if (fallback_pulse) begin
            irq_flag <= 1'b1;
            // Raster event (simulato)
            vic_irq_flags[0] <= 1'b1;
            // IRQ di sistema (fallback)
            sys_irq_flag <= 1'b1;
        end
        
        if (enable) begin
            // Timer countdown - setta flag quando underflow
            if (cpu_clk_en && cia1_cra[0]) begin
                if (cia1_ta == 16'h0000) begin
                    cia1_ta <= cia1_ta_latch;
                    irq_flag <= 1'b1;
                    if (cia1_cra[3])
                        cia1_cra[0] <= 1'b0;
                end
                else begin
                    cia1_ta <= cia1_ta - 1'd1;
                end
            end
            
            // Register writes
            if (cpu_we && cpu_clk_en) begin
                case (cpu_addr)
                    16'hD019: begin
                        // Clear IRQ flags scrivendo 1 sui bit da azzerare
                        vic_irq_flags <= vic_irq_flags & ~cpu_data_out;
                        // Tipico ACK nel KERNAL: scrive $D019
                        sys_irq_flag <= 1'b0;
                    end
                    16'hD01A: begin
                        vic_irq_enable <= cpu_data_out;
                    end
                    16'hD020: vic_border <= cpu_data_out;
                    16'hD021: vic_bgcolor <= cpu_data_out;
                    16'hDC00: cia1_pra <= cpu_data_out;
                    16'hDC04: cia1_ta_latch[7:0] <= cpu_data_out;
                    16'hDC05: begin
                        cia1_ta_latch[15:8] <= cpu_data_out;
                        cia1_ta <= {cpu_data_out, cia1_ta_latch[7:0]};
                    end
                    16'hDC0D: begin
                        if (cpu_data_out[7])
                            cia1_icr_mask <= cia1_icr_mask | cpu_data_out[4:0];
                        else
                            cia1_icr_mask <= cia1_icr_mask & ~cpu_data_out[4:0];
                    end
                    16'hDC0E: begin
                        cia1_cra <= cpu_data_out;
                        if (cpu_data_out[4])
                            cia1_ta <= cia1_ta_latch;
                    end
                endcase
            end
            
            // LETTURA ICR ($DC0D) CLEARA IL FLAG - questo è cruciale!
            if (!cpu_we && cpu_addr == 16'hDC0D && cpu_clk_en) begin
                irq_flag <= 1'b0;
                // Tipico ACK nel KERNAL: legge $DC0D
                sys_irq_flag <= 1'b0;
            end
        end
    end
end

// ICR read value: bit 7 = IRQ attivo, bit 0 = timer A flag
wire [7:0] cia1_icr_read = {cia1_irq, 2'b00, 4'b0000, irq_flag};

// Keyboard matrix read
wire [7:0] keyboard_read;
assign keyboard_read = (cia1_pra[0] ? 8'hFF : key_matrix[0]) &
                       (cia1_pra[1] ? 8'hFF : key_matrix[1]) &
                       (cia1_pra[2] ? 8'hFF : key_matrix[2]) &
                       (cia1_pra[3] ? 8'hFF : key_matrix[3]) &
                       (cia1_pra[4] ? 8'hFF : key_matrix[4]) &
                       (cia1_pra[5] ? 8'hFF : key_matrix[5]) &
                       (cia1_pra[6] ? 8'hFF : key_matrix[6]) &
                       (cia1_pra[7] ? 8'hFF : key_matrix[7]);

//==============================================================================
// MEMORY MAP DECODER
//==============================================================================
always @(*) begin
    casez (cpu_addr)
        // RAM $0000-$7FFF
        16'b0???_????_????_????: begin
            if (screen_sel)
                cpu_data_in = screen_data;
            else
                cpu_data_in = ext_ram_din;
        end
        // RAM $8000-$9FFF
        16'b100?_????_????_????: cpu_data_in = ext_ram_din;
        // BASIC ROM $A000-$BFFF
        16'b101?_????_????_????: cpu_data_in = ext_ram_din;
        // RAM $C000-$CFFF
        16'b1100_????_????_????: cpu_data_in = ext_ram_din;
        
        // I/O $D000-$DFFF
        16'b1101_00??_????_????: begin
            // VIC-II $D000-$D3FF
            case (cpu_addr[5:0])
                6'h19: cpu_data_in = {(|vic_irq_flags), vic_irq_flags[6:0]}; // $D019
                6'h1A: cpu_data_in = vic_irq_enable;                         // $D01A
                6'h20: cpu_data_in = vic_border;
                6'h21: cpu_data_in = vic_bgcolor;
                default: cpu_data_in = 8'h00;
            endcase
        end
        16'b1101_01??_????_????: cpu_data_in = 8'h00;  // SID
        16'b1101_10??_????_????: cpu_data_in = color_data;  // Color RAM
        16'b1101_1100_????_????: begin
            // CIA1 $DC00-$DCFF
            case (cpu_addr[3:0])
                4'h0: cpu_data_in = cia1_pra;
                4'h1: cpu_data_in = keyboard_read;
                4'h4: cpu_data_in = cia1_ta[7:0];
                4'h5: cpu_data_in = cia1_ta[15:8];
                4'hD: cpu_data_in = cia1_icr_read;
                4'hE: cpu_data_in = cia1_cra;
                default: cpu_data_in = 8'hFF;
            endcase
        end
        16'b1101_1101_????_????: cpu_data_in = 8'hFF;  // CIA2
        
        // KERNAL ROM $E000-$FFFF
        16'b111?_????_????_????: cpu_data_in = ext_ram_din;
        
        default: cpu_data_in = 8'hFF;
    endcase
end

//==============================================================================
// KEYBOARD - C64 Matrix (ASCII codes from ESP32)
//==============================================================================
reg [7:0] key_matrix [0:7];
reg [23:0] key_timer;

// Sincronizzazione key_strobe semplificata
reg key_strobe_r1, key_strobe_r2;
wire key_strobe_edge = key_strobe_r1 && !key_strobe_r2;

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
        if (key_timer > 0)
            key_timer <= key_timer - 1'd1;
        
        if (key_timer == 1)
            for (i = 0; i < 8; i = i + 1) key_matrix[i] <= 8'hFF;
        
        // Rimuovo && enable - la tastiera deve funzionare sempre
        if (key_strobe_edge) begin
            key_timer <= 24'd2500000;
            for (i = 0; i < 8; i = i + 1) key_matrix[i] <= 8'hFF;
            
            case (key_code)  // Uso key_code diretto, non latched
                // Letters (key_matrix[ROW] bit COL = 0)
                8'h41, 8'h61: key_matrix[1] <= 8'b11111011;  // A
                8'h42, 8'h62: key_matrix[3] <= 8'b11101111;  // B
                8'h43, 8'h63: key_matrix[2] <= 8'b11101111;  // C
                8'h44, 8'h64: key_matrix[2] <= 8'b11111011;  // D
                8'h45, 8'h65: key_matrix[1] <= 8'b10111111;  // E
                8'h46, 8'h66: key_matrix[2] <= 8'b11011111;  // F
                8'h47, 8'h67: key_matrix[3] <= 8'b11111011;  // G
                8'h48, 8'h68: key_matrix[3] <= 8'b11011111;  // H
                8'h49, 8'h69: key_matrix[4] <= 8'b11111101;  // I
                8'h4A, 8'h6A: key_matrix[4] <= 8'b11111011;  // J
                8'h4B, 8'h6B: key_matrix[4] <= 8'b11011111;  // K
                8'h4C, 8'h6C: key_matrix[5] <= 8'b11111011;  // L
                8'h4D, 8'h6D: key_matrix[4] <= 8'b11101111;  // M
                8'h4E, 8'h6E: key_matrix[4] <= 8'b01111111;  // N
                8'h4F, 8'h6F: key_matrix[4] <= 8'b10111111;  // O
                8'h50, 8'h70: key_matrix[5] <= 8'b11111101;  // P
                8'h51, 8'h71: key_matrix[7] <= 8'b10111111;  // Q
                8'h52, 8'h72: key_matrix[2] <= 8'b11111101;  // R
                8'h53, 8'h73: key_matrix[1] <= 8'b11011111;  // S
                8'h54, 8'h74: key_matrix[2] <= 8'b10111111;  // T
                8'h55, 8'h75: key_matrix[3] <= 8'b10111111;  // U
                8'h56, 8'h76: key_matrix[3] <= 8'b01111111;  // V
                8'h57, 8'h77: key_matrix[1] <= 8'b11111101;  // W
                8'h58, 8'h78: key_matrix[2] <= 8'b01111111;  // X
                8'h59, 8'h79: key_matrix[3] <= 8'b11111101;  // Y
                8'h5A, 8'h7A: key_matrix[1] <= 8'b11101111;  // Z
                
                // Numbers
                8'h30: key_matrix[4] <= 8'b11110111;  // 0
                8'h31: key_matrix[7] <= 8'b11111110;  // 1
                8'h32: key_matrix[7] <= 8'b11110111;  // 2
                8'h33: key_matrix[1] <= 8'b11111110;  // 3
                8'h34: key_matrix[1] <= 8'b11110111;  // 4
                8'h35: key_matrix[2] <= 8'b11111110;  // 5
                8'h36: key_matrix[2] <= 8'b11110111;  // 6
                8'h37: key_matrix[3] <= 8'b11111110;  // 7
                8'h38: key_matrix[3] <= 8'b11110111;  // 8
                8'h39: key_matrix[4] <= 8'b11111110;  // 9
                
                // Special keys
                8'h20: key_matrix[7] <= 8'b11101111;  // Space
                8'h0D: key_matrix[0] <= 8'b11111101;  // Enter
                8'h08, 8'h7F: key_matrix[0] <= 8'b11111110;  // DEL
                
                // Punctuation
                8'h2C: key_matrix[5] <= 8'b01111111;  // ,
                8'h2E: key_matrix[5] <= 8'b11101111;  // .
                8'h3A: key_matrix[5] <= 8'b11011111;  // :
                8'h3B: key_matrix[6] <= 8'b11111011;  // ;
                8'h2D: key_matrix[5] <= 8'b11110111;  // -
                8'h2B: key_matrix[5] <= 8'b11111110;  // +
                8'h2A: key_matrix[6] <= 8'b11111101;  // *
                8'h2F: key_matrix[6] <= 8'b01111111;  // /
                8'h3D: key_matrix[6] <= 8'b11011111;  // =
                8'h40: key_matrix[5] <= 8'b10111111;  // @
                8'h22: begin key_matrix[7] <= 8'b11110111; key_matrix[1] <= 8'b01111111; end  // " (Shift+2)
                
                // SHIFT + Numbers for symbols (Italian layout)
                8'h21: begin key_matrix[7] <= 8'b11111110; key_matrix[1] <= 8'b01111111; end  // ! = SHIFT+1
                8'h9C: key_matrix[6] <= 8'b11111110;  // £ = Row6, Col0
                8'h5C: key_matrix[6] <= 8'b11111110;  // £ alternate code
                8'h24: begin key_matrix[1] <= 8'b01110111; end  // $ = SHIFT+4 (Row1 bit3 + SHIFT bit7)
                8'h25: begin key_matrix[2] <= 8'b11111110; key_matrix[1] <= 8'b01111111; end  // % = SHIFT+5
                8'h26: begin key_matrix[2] <= 8'b11110111; key_matrix[1] <= 8'b01111111; end  // & = SHIFT+6
                8'h28: begin key_matrix[3] <= 8'b11110111; key_matrix[1] <= 8'b01111111; end  // ( = SHIFT+8
                8'h29: begin key_matrix[4] <= 8'b11111110; key_matrix[1] <= 8'b01111111; end  // ) = SHIFT+9
                8'h3F: begin key_matrix[6] <= 8'b01111111; key_matrix[1] <= 8'b01111111; end  // ? = SHIFT+/
                8'h3C: begin key_matrix[5] <= 8'b01111111; key_matrix[1] <= 8'b01111111; end  // < = SHIFT+,
                8'h3E: begin key_matrix[5] <= 8'b11101111; key_matrix[1] <= 8'b01111111; end  // > = SHIFT+.
                
                // Arrow keys (PETSCII codes from PS/2 keyboard)
                8'h91: begin key_matrix[0] <= 8'b01111111; key_matrix[1] <= 8'b01111111; end  // Up = SHIFT + CRSR DOWN
                8'h11: key_matrix[0] <= 8'b01111111;  // Down = CRSR DOWN
                8'h9D: begin key_matrix[0] <= 8'b11111011; key_matrix[1] <= 8'b01111111; end  // Left = SHIFT + CRSR RIGHT
                8'h1D: key_matrix[0] <= 8'b11111011;  // Right = CRSR RIGHT
                8'h13: key_matrix[0] <= 8'b11110111;  // Home = CLR/HOME
                8'h94: begin key_matrix[0] <= 8'b11110111; key_matrix[1] <= 8'b01111111; end  // Insert = SHIFT + INST/DEL
                
                // Function keys F1-F8 (codes 0x85-0x8C from PS/2)
                // C64: F1=Row4/Col0, F3=Row5/Col0, F5=Row6/Col0, F7=Row3/Col0
                // F2,F4,F6,F8 = SHIFT + F1,F3,F5,F7
                8'h85: key_matrix[0] <= 8'b11101111;  // F1 -> key_matrix[0] bit 4
                8'h86: begin key_matrix[0] <= 8'b11101111; key_matrix[1] <= 8'b01111111; end  // F2 = SHIFT+F1
                8'h87: key_matrix[0] <= 8'b11011111;  // F3 -> key_matrix[0] bit 5
                8'h88: begin key_matrix[0] <= 8'b11011111; key_matrix[1] <= 8'b01111111; end  // F4 = SHIFT+F3
                8'h89: key_matrix[0] <= 8'b10111111;  // F5 -> key_matrix[0] bit 6
                8'h8A: begin key_matrix[0] <= 8'b10111111; key_matrix[1] <= 8'b01111111; end  // F6 = SHIFT+F5
                8'h8B: key_matrix[0] <= 8'b11110111;  // F7 -> key_matrix[0] bit 3 (same as HOME but different row)
                8'h8C: begin key_matrix[0] <= 8'b11110111; key_matrix[1] <= 8'b01111111; end  // F8 = SHIFT+F7
            endcase
        end
    end
end

//==============================================================================
// VGA OUTPUT - DUAL RESOLUTION
//==============================================================================
reg pix_clk_div;
always @(posedge clk or negedge reset_n)
    if (!reset_n) pix_clk_div <= 0;
    else pix_clk_div <= ~pix_clk_div;

// Timing parameters
wire [10:0] H_TOTAL   = res_mode ? 11'd1040 : 11'd800;
wire [10:0] H_VISIBLE = res_mode ? 11'd800  : 11'd640;
wire [10:0] H_FRONT   = res_mode ? 11'd56   : 11'd16;
wire [10:0] H_SYNC    = res_mode ? 11'd120  : 11'd96;
wire [9:0]  V_TOTAL   = res_mode ? 10'd666  : 10'd525;
wire [9:0]  V_VISIBLE = res_mode ? 10'd600  : 10'd480;
wire [9:0]  V_FRONT   = res_mode ? 10'd37   : 10'd10;
wire [9:0]  V_SYNC    = res_mode ? 10'd6    : 10'd2;

wire [10:0] TEXT_H_START = res_mode ? 11'd80  : 11'd0;
wire [10:0] TEXT_H_END   = res_mode ? 11'd720 : 11'd640;
wire [9:0]  TEXT_V_START = res_mode ? 10'd100 : 10'd40;
wire [9:0]  TEXT_V_END   = res_mode ? 10'd500 : 10'd440;

wire pix_clk_en = res_mode ? 1'b1 : pix_clk_div;

reg [10:0] h_count;
reg [9:0] v_count;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        h_count <= 0;
        v_count <= 0;
    end
    else if (pix_clk_en) begin
        if (h_count == H_TOTAL - 1) begin
            h_count <= 0;
            v_count <= (v_count == V_TOTAL - 1) ? 0 : v_count + 1'd1;
        end
        else h_count <= h_count + 1'd1;
    end
end

reg vga_hsync_r, vga_vsync_r;
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        vga_hsync_r <= 1;
        vga_vsync_r <= 1;
    end
    else begin
        vga_hsync_r <= ~(h_count >= H_VISIBLE + H_FRONT && h_count < H_VISIBLE + H_FRONT + H_SYNC);
        vga_vsync_r <= ~(v_count >= V_VISIBLE + V_FRONT && v_count < V_VISIBLE + V_FRONT + V_SYNC);
    end
end
assign vga_hsync = vga_hsync_r;
assign vga_vsync = vga_vsync_r;

// Text area
wire in_text_h = (h_count >= TEXT_H_START && h_count < TEXT_H_END);
wire in_text_v = (v_count >= TEXT_V_START && v_count < TEXT_V_END);
wire in_text = in_text_h && in_text_v;
wire in_border = (h_count < H_VISIBLE && v_count < V_VISIBLE) && !in_text;

// Character position
wire [8:0] text_x = (h_count - TEXT_H_START) >> 1;
wire [8:0] text_y = (v_count - TEXT_V_START) >> 1;
wire [5:0] char_col = text_x[8:3];
wire [4:0] char_row = text_y[7:3];
wire [9:0] video_addr = char_row * 40 + char_col;
wire [2:0] pixel_x = text_x[2:0];
wire [2:0] pixel_y = text_y[2:0];

// Character fetch
reg [7:0] current_char, current_color;
always @(posedge clk) begin
    current_char <= screen_ram[video_addr];
    current_color <= color_ram[video_addr];
end

assign char_rom_addr = {current_char, pixel_y};
wire pixel_on = char_data[7 - pixel_x];

// C64 color palette
function [11:0] c64_color;
    input [3:0] idx;
    case (idx)
        4'h0: c64_color = 12'h000;  // Black
        4'h1: c64_color = 12'hFFF;  // White
        4'h2: c64_color = 12'h811;  // Red
        4'h3: c64_color = 12'h6CE;  // Cyan
        4'h4: c64_color = 12'h828;  // Purple
        4'h5: c64_color = 12'h5A3;  // Green
        4'h6: c64_color = 12'h229;  // Blue
        4'h7: c64_color = 12'hEE7;  // Yellow
        4'h8: c64_color = 12'h852;  // Orange
        4'h9: c64_color = 12'h530;  // Brown
        4'hA: c64_color = 12'hC66;  // Light Red
        4'hB: c64_color = 12'h444;  // Dark Grey
        4'hC: c64_color = 12'h777;  // Medium Grey
        4'hD: c64_color = 12'h9F9;  // Light Green
        4'hE: c64_color = 12'h66C;  // Light Blue
        4'hF: c64_color = 12'hAAA;  // Light Grey
    endcase
endfunction

wire [11:0] border_color = c64_color(vic_border[3:0]);
wire [11:0] bg_color = c64_color(vic_bgcolor[3:0]);
wire [11:0] fg_color = c64_color(current_color[3:0]);

reg [3:0] out_r, out_g, out_b;
always @(posedge clk) begin
    if (h_count >= H_VISIBLE || v_count >= V_VISIBLE) begin
        out_r <= 0; out_g <= 0; out_b <= 0;
    end
    else if (in_border) begin
        out_r <= border_color[11:8];
        out_g <= border_color[7:4];
        out_b <= border_color[3:0];
    end
    else if (in_text) begin
        if (pixel_on) begin
            out_r <= fg_color[11:8];
            out_g <= fg_color[7:4];
            out_b <= fg_color[3:0];
        end else begin
            out_r <= bg_color[11:8];
            out_g <= bg_color[7:4];
            out_b <= bg_color[3:0];
        end
    end
    else begin
        out_r <= 0; out_g <= 0; out_b <= 0;
    end
end

assign vga_r = out_r;
assign vga_g = out_g;
assign vga_b = out_b;

endmodule
