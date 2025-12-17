//==============================================================================
// RETRO MULTICORE TOP - CPU 6502 + ROM caricabili via UART
//==============================================================================
// Autore: Angelo Arato
// Data: Novembre 2025
//
// ROM caricate da SD via ESP32 nei Memory Blocks M9K
//==============================================================================

module retro_multicore_top_cpu (
    input  wire        MAX10_CLK1_50,
    input  wire [1:0]  KEY,
    input  wire [9:0]  SW,
    output wire [9:0]  LEDR,
    output wire [3:0]  VGA_R,
    output wire [3:0]  VGA_G,
    output wire [3:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5,
    inout  wire [35:0] GPIO,
    
    // PS/2 Keyboard (pin dedicati)
    input  wire        PS2_CLK,
    input  wire        PS2_DATA
);

wire clk = MAX10_CLK1_50;
wire rst_n = KEY[0];

//==============================================================================
// SEGNALI INTERNI
//==============================================================================

reg [2:0] current_core;
reg core_reset_reg;
wire core_reset = core_reset_reg;

// UART - PIN_W10 = GPIO[1] è RX (da ESP32 TX), PIN_V10 = GPIO[0] è TX (a ESP32 RX)
wire uart_rx = GPIO[1];   // PIN_W10 riceve da ESP32 GPIO26 (TX)
wire uart_tx;
assign GPIO[0] = uart_tx; // PIN_V10 trasmette a ESP32 GPIO27 (RX)

wire [7:0] rx_data;
wire       rx_valid;
wire       tx_busy;

// TX dal command_parser
wire [7:0] cmd_tx_data;
wire       cmd_tx_start;

// TX dal rom_loader
wire [7:0] loader_tx_data;
wire       loader_tx_start;

// TX dal load_handler
wire [7:0] load_tx_data;
wire       load_tx_start;
wire       load_active;  // LOAD in corso

// mode_rom_data dal command_parser (dichiarato qui, definito dopo)
wire       mode_rom_data;

// Mux TX: load_handler ha priorità durante LOAD, poi rom_loader, poi command_parser
wire [7:0] tx_data = load_active ? load_tx_data : 
                     (mode_rom_data ? loader_tx_data : cmd_tx_data);
wire       tx_start = load_active ? load_tx_start : 
                      (mode_rom_data ? loader_tx_start : cmd_tx_start);

// ROM loader
wire        rom_write;
wire [15:0] rom_addr;
wire [7:0]  rom_data;
wire [2:0]  rom_bank;
wire        rom_loading;

// Keyboard
reg        key_strobe;
reg [7:0]  key_code;

// VGA
wire [3:0] test_vga_r, test_vga_g, test_vga_b;
wire       test_vga_hsync, test_vga_vsync;
wire [3:0] c64_vga_r, c64_vga_g, c64_vga_b;
wire       c64_vga_hsync, c64_vga_vsync;

// LED status - Debug UART
reg [23:0] rx_activity_counter;
reg rx_activity_led;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_activity_counter <= 0;
        rx_activity_led <= 0;
    end else begin
        if (rx_valid) begin
            rx_activity_counter <= 24'd5000000; // ~100ms a 50MHz
            rx_activity_led <= 1;
        end else if (rx_activity_counter > 0) begin
            rx_activity_counter <= rx_activity_counter - 1;
        end else begin
            rx_activity_led <= 0;
        end
    end
end

assign LEDR[2:0] = current_core;
assign LEDR[3] = rom_loading;
assign LEDR[4] = rx_activity_led;  // Lampeggia quando riceve dati

// Pulse stretchers per rendere visibili segnali brevi
reg [19:0] led5_stretch, led6_stretch, led7_stretch;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        led5_stretch <= 0;
        led6_stretch <= 0;
        led7_stretch <= 0;
    end else begin
        // LED5: rx_valid
        if (rx_valid)
            led5_stretch <= 20'd500000;  // ~10ms
        else if (led5_stretch > 0)
            led5_stretch <= led5_stretch - 1;
            
        // LED6: cmd_key_char
        if (cmd_key_char)
            led6_stretch <= 20'd500000;
        else if (led6_stretch > 0)
            led6_stretch <= led6_stretch - 1;
            
        // LED7: key_strobe
        if (key_strobe)
            led7_stretch <= 20'd500000;
        else if (led7_stretch > 0)
            led7_stretch <= led7_stretch - 1;
    end
end

assign LEDR[5] = (led5_stretch > 0);   // rx_valid (stretched)
assign LEDR[6] = (led6_stretch > 0);   // cmd_key_char (stretched)
assign LEDR[7] = (led7_stretch > 0);   // key_strobe (stretched)
assign LEDR[8] = (current_core == 3'd3) ? vic20_debug_irq : 
                 (current_core == 3'd4) ? apple1_debug : 1'b0;
assign LEDR[9] = (current_core == 3'd3) || (current_core == 3'd4); // Core 3 or 4 active

//==============================================================================
// UART CONTROLLER
//==============================================================================

uart_controller #(
    .CLK_FREQ(50000000),
    .BAUD_RATE(115200)
) uart_inst (
    .clk(clk),
    .reset_n(rst_n),
    .rx(uart_rx),
    .tx(uart_tx),
    .rx_data(rx_data),
    .rx_valid(rx_valid),
    .tx_data(tx_data),
    .tx_start(tx_start),
    .tx_busy(tx_busy)
);

//==============================================================================
// COMMAND PARSER
//==============================================================================

wire       cmd_ping;
wire       cmd_status;
wire       cmd_reset;
wire       cmd_select_core;
wire [2:0] cmd_core_id;
wire       cmd_rom_start;
wire [2:0] cmd_rom_id;
wire [15:0] cmd_rom_size;
wire       cmd_rom_end;
wire       cmd_boot;
wire       cmd_key_char;
wire [7:0] cmd_key_data;

// PRG loader signals
wire       cmd_prg_start;
wire [15:0] cmd_prg_addr;
wire [15:0] cmd_prg_size;
wire       cmd_prg_end;
wire       prg_data_mode;
wire [7:0] prg_byte;
wire       prg_byte_valid;
wire [15:0] prg_write_addr;

// Alias per compatibilità con VIC-20 e ZX Spectrum
wire        prg_write = prg_byte_valid;
wire [15:0] prg_addr = prg_write_addr;
wire [7:0]  prg_data = prg_byte;

command_parser cmd_parser_inst (
    .clk(clk),
    .reset_n(rst_n),
    .rx_valid(rx_valid),
    .rx_data(rx_data),
    .tx_start(cmd_tx_start),
    .tx_data(cmd_tx_data),
    .tx_busy(tx_busy),
    .cmd_ping(cmd_ping),
    .cmd_status(cmd_status),
    .cmd_reset(cmd_reset),
    .cmd_select_core(cmd_select_core),
    .cmd_core_id(cmd_core_id),
    .cmd_rom_start(cmd_rom_start),
    .cmd_rom_id(cmd_rom_id),
    .cmd_rom_size(cmd_rom_size),
    .cmd_rom_end(cmd_rom_end),
    .cmd_boot(cmd_boot),
    .cmd_key_char(cmd_key_char),
    .cmd_key_data(cmd_key_data),
    .cmd_prg_start(cmd_prg_start),
    .cmd_prg_addr(cmd_prg_addr),
    .cmd_prg_size(cmd_prg_size),
    .cmd_prg_end(cmd_prg_end),
    .prg_data_mode(prg_data_mode),
    .prg_byte(prg_byte),
    .prg_byte_valid(prg_byte_valid),
    .prg_write_addr(prg_write_addr),
    .current_core(current_core),
    .rom_loaded(1'b1),
    .mode_rom_data(mode_rom_data)
);

//==============================================================================
// ROM LOADER
//==============================================================================

rom_loader rom_loader_inst (
    .clk(clk),
    .reset_n(rst_n),
    .rx_data_valid(rx_valid & mode_rom_data),
    .rx_data(rx_data),
    .tx_start(loader_tx_start),
    .tx_data(loader_tx_data),
    .tx_busy(tx_busy),
    .cmd_rom_start(cmd_rom_start),
    .cmd_rom_id(cmd_rom_id),
    .cmd_rom_size(cmd_rom_size),
    .cmd_rom_end(cmd_rom_end),
    .rom_wr_en(rom_write),
    .rom_wr_addr(rom_addr),
    .rom_wr_data(rom_data),
    .loading_active(rom_loading),
    .loading_complete(),
    .loaded_rom_id(),
    .current_rom_bank(rom_bank),  // Usa ROM bank corrente durante caricamento
    .current_core(current_core)
);

// Calcolo indirizzo ROM per VIC-20
// ROM 0 (char): $0000-$0FFF (4KB)
//==============================================================================
// CORE SELECTION & RESET
//==============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_core <= 3'd0;  // Default: Test Pattern
        core_reset_reg <= 1'b1;
    end
    else begin
        core_reset_reg <= 1'b0;
        
        if (cmd_select_core) begin
            current_core <= cmd_core_id;
            core_reset_reg <= 1'b1;
        end
        
        if (cmd_reset || cmd_boot)
            core_reset_reg <= 1'b1;
    end
end

//==============================================================================
// PS/2 KEYBOARD
//==============================================================================

wire [7:0] ps2_key_code;
wire       ps2_key_strobe;
wire       ps2_key_shift;
wire       ps2_key_ctrl;

ps2_keyboard ps2_inst (
    .clk(clk),
    .reset_n(rst_n),
    
    // Pin PS/2
    .ps2_clk(PS2_CLK),
    .ps2_data(PS2_DATA),
    
    // Output
    .key_code(ps2_key_code),
    .key_strobe(ps2_key_strobe),
    .key_shift(ps2_key_shift),
    .key_ctrl(ps2_key_ctrl),
    .key_caps()
);

//==============================================================================
// KEYBOARD HANDLER (PS/2 + UART combined)
// SW[9] = 1: PS/2 keyboard priority
// SW[9] = 0: UART/ESP32 keyboard priority
//==============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_strobe <= 0;
        key_code <= 8'd0;
    end
    else begin
        key_strobe <= 0;
        
        // PS/2 ha priorità quando SW[9]=1, altrimenti UART
        if (SW[9]) begin
            // PS/2 keyboard mode
            if (ps2_key_strobe) begin
                key_strobe <= 1;
                key_code <= ps2_key_code;
            end
            // Fallback a UART se nessun PS/2
            else if (cmd_key_char) begin
                key_strobe <= 1;
                key_code <= cmd_key_data;
            end
        end
        else begin
            // UART/ESP32 keyboard mode
            if (cmd_key_char) begin
                key_strobe <= 1;
                key_code <= cmd_key_data;
            end
            // Fallback a PS/2 se nessun UART
            else if (ps2_key_strobe) begin
                key_strobe <= 1;
                key_code <= ps2_key_code;
            end
        end
    end
end

//==============================================================================
// TEST PATTERN GENERATOR
//==============================================================================

test_pattern_gen test_gen (
    .clk(clk),
    .reset_n(rst_n),  // Sempre attivo, non dipende da core_reset
    .res_mode(SW[8]),           // 0=640x480, 1=800x600
    .vga_r(test_vga_r),
    .vga_g(test_vga_g),
    .vga_b(test_vga_b),
    .vga_hsync(test_vga_hsync),
    .vga_vsync(test_vga_vsync)
);

//==============================================================================
// SHARED RAM 64KB - Usata da C64 e VIC-20
//==============================================================================
// Porta A: CPU (multiplexata tra C64 e VIC-20)
// Porta B: ROM/PRG Loader (scrittura durante caricamento)

// C64 ext_ram signals
wire [15:0] c64_ext_ram_addr;
wire [7:0]  c64_ext_ram_dout;
wire [7:0]  c64_ext_ram_din;
wire        c64_ext_ram_we;

// Port A: connessa direttamente al C64 (solo C64 usa shared RAM)
wire [15:0] shared_port_a_addr = c64_ext_ram_addr;
wire [7:0]  shared_port_a_din = c64_ext_ram_dout;
wire        shared_port_a_we = c64_ext_ram_we;
wire [7:0]  shared_port_a_dout;

// Distribuisci dati letti al C64
assign c64_ext_ram_din = shared_port_a_dout;

// Indirizzo loader (C64: BASIC $A000, KERNAL $E000, PRG diretto)
reg [15:0] loader_addr;
reg [7:0]  loader_data;
reg        loader_we;

always @(*) begin
    loader_we = 1'b0;
    loader_addr = 16'd0;
    loader_data = 8'd0;
    
    // C64 ROM loading
    if (rom_write && current_core == 3'd1) begin
        case (rom_bank[1:0])
            2'd0: begin // BASIC -> $A000-$BFFF
                loader_addr = 16'hA000 + {3'b000, rom_addr[12:0]};
                loader_data = rom_data;
                loader_we = 1'b1;
            end
            2'd1: begin // KERNAL -> $E000-$FFFF
                loader_addr = 16'hE000 + {3'b000, rom_addr[12:0]};
                loader_data = rom_data;
                loader_we = 1'b1;
            end
            default: loader_we = 1'b0;
        endcase
    end
    // C64 PRG loading
    else if (prg_byte_valid && prg_data_mode && current_core == 3'd1) begin
        loader_addr = prg_write_addr;
        loader_data = prg_byte;
        loader_we = 1'b1;
    end
    // VIC-20 PRG loading (scrive in shared RAM)
    else if (prg_byte_valid && prg_data_mode && current_core == 3'd3) begin
        loader_addr = prg_write_addr;
        loader_data = prg_byte;
        loader_we = 1'b1;
    end
end

// Port B address: multiplexato tra Loader (write) e Virtual Drive (read)
// Quando loader_we=1, usa loader_addr per scrivere
// Altrimenti usa vdrive_ram_addr per lettura filename
wire [15:0] port_b_addr_mux = loader_we ? loader_addr : vdrive_ram_addr;
wire [7:0]  shared_port_b_dout;

// Shared RAM instance
shared_ram shared_ram_inst (
    .clk(clk),
    // Porta A: CPU (multiplexata)
    .port_a_addr(shared_port_a_addr),
    .port_a_data_in(shared_port_a_din),
    .port_a_data_out(shared_port_a_dout),
    .port_a_we(shared_port_a_we),
    // Porta B: Loader (write) / Virtual Drive (read)
    .port_b_addr(port_b_addr_mux),
    .port_b_data_in(loader_data),
    .port_b_we(loader_we),
    .port_b_data_out(shared_port_b_dout)  // Usato da virtual_drive
);

//==============================================================================
// C64 COMPLETE (CPU 6502 + ROM da SD) - Core 1
//==============================================================================

// La CPU deve rimanere in reset SOLO durante il caricamento delle ROM
// Durante PRG loading, la CPU viene fermata con RDY, non resettata!
wire c64_prg_loading = prg_data_mode && current_core == 3'd1;
wire c64_reset_n = rst_n & ~core_reset & ~(rom_loading && current_core == 3'd1);

// Segnali LOAD virtuale C64 (dal virtual_drive)
wire        c64_load_req;
wire [127:0] c64_load_filename;
wire [3:0]  c64_load_filename_len;
wire [7:0]  c64_load_device;
wire        c64_load_secondary;
wire        c64_load_active;
wire        c64_load_complete;
wire        c64_load_error;
wire [15:0] c64_load_end_addr;

// Segnali Virtual Drive I/O
wire [4:0]  c64_vdrive_addr;
wire [7:0]  c64_vdrive_data_out;
wire [7:0]  c64_vdrive_data_in;
wire        c64_vdrive_we;
wire        c64_vdrive_cs;

// Segnali per lettura RAM dal virtual_drive
wire [15:0] vdrive_ram_addr;
wire        vdrive_ram_req;

c64_complete c64_inst (
    .clk(clk),
    .reset_n(c64_reset_n),
    .enable(current_core == 3'd1),
    .res_mode(SW[8]),           // 0=640x480, 1=800x600
    // Shared RAM - Porta A dedicata alla CPU
    .ext_ram_addr(c64_ext_ram_addr),
    .ext_ram_dout(c64_ext_ram_dout),
    .ext_ram_din(c64_ext_ram_din),
    .ext_ram_we(c64_ext_ram_we),
    // Video RAM (non usato)
    .video_ram_addr(),
    .video_ram_din(8'h00),
    // ROM loader (solo CharGen interno)
    .rom_addr(rom_addr),
    .rom_data(rom_data),
    .rom_we(rom_write && current_core == 3'd1),
    .rom_bank(rom_bank[1:0]),
    // PRG loader (per screen RAM locale)
    .prg_addr(prg_write_addr),
    .prg_data(prg_byte),
    .prg_we(prg_byte_valid && prg_data_mode && current_core == 3'd1),
    // Keyboard
    .key_strobe(key_strobe),
    .key_code(key_code),
    // LOAD virtuale (segnali passano attraverso virtual_drive)
    .load_req(),  // Non usato direttamente
    .load_filename(),
    .load_filename_len(),
    .load_device(),
    .load_secondary(),
    .load_active(c64_load_active),
    .load_complete(c64_load_complete),
    .load_error(c64_load_error),
    .load_end_addr(c64_load_end_addr),
    // Virtual Drive I/O ($DE00-$DE1F)
    .vdrive_addr(c64_vdrive_addr),
    .vdrive_data_out(c64_vdrive_data_out),
    .vdrive_data_in(c64_vdrive_data_in),
    .vdrive_we(c64_vdrive_we),
    .vdrive_cs(c64_vdrive_cs),
    // VGA
    .vga_r(c64_vga_r),
    .vga_g(c64_vga_g),
    .vga_b(c64_vga_b),
    .vga_hsync(c64_vga_hsync),
    .vga_vsync(c64_vga_vsync)
);

//==============================================================================
// VIRTUAL DRIVE - Gestisce LOAD via registri I/O $DE00-$DE1F
//==============================================================================
virtual_drive c64_vdrive (
    .clk(clk),
    .reset_n(rst_n),
    .enable(current_core == 3'd1),
    // CPU bus interface
    .addr(c64_vdrive_addr),
    .data_in(c64_vdrive_data_out),
    .data_out(c64_vdrive_data_in),
    .we(c64_vdrive_we),
    .cs(c64_vdrive_cs),
    // RAM read interface (usa Port B della shared_ram)
    .ram_read_addr(vdrive_ram_addr),
    .ram_read_data(shared_port_b_dout),  // Legge da Port B
    .ram_read_req(vdrive_ram_req),
    // LOAD request output
    .load_req(c64_load_req),
    .load_filename(c64_load_filename),
    .load_filename_len(c64_load_filename_len),
    .load_device(c64_load_device),
    .load_secondary(c64_load_secondary),
    // LOAD response input
    .load_active(c64_load_active),
    .load_complete(c64_load_complete),
    .load_error(c64_load_error),
    .load_end_addr(c64_load_end_addr)
);

//==============================================================================
// LOAD HANDLER - Gestisce LOAD virtuale per C64/VIC-20
//==============================================================================

// VIC-20 LOAD signals (non ancora implementato nel VIC-20)
wire vic20_load_req = 1'b0;
wire [127:0] vic20_load_filename = 128'd0;
wire [3:0] vic20_load_filename_len = 4'd0;
wire [7:0] vic20_load_device = 8'd0;
wire vic20_load_secondary = 1'b0;
wire vic20_load_active;
wire vic20_load_complete;
wire vic20_load_error;
wire [15:0] vic20_load_end_addr;

// Load active generale (per mux TX)
assign load_active = c64_load_active || vic20_load_active;

load_handler load_handler_inst (
    .clk(clk),
    .reset_n(rst_n),
    
    // UART TX
    .tx_start(load_tx_start),
    .tx_data(load_tx_data),
    .tx_busy(tx_busy),
    
    // UART RX (per risposte)
    .rx_valid(rx_valid),
    .rx_data(rx_data),
    
    // C64 LOAD interface
    .c64_load_req(c64_load_req),
    .c64_load_filename(c64_load_filename),
    .c64_load_filename_len(c64_load_filename_len),
    .c64_load_device(c64_load_device),
    .c64_load_secondary(c64_load_secondary),
    .c64_load_active(c64_load_active),
    .c64_load_complete(c64_load_complete),
    .c64_load_error(c64_load_error),
    .c64_load_end_addr(c64_load_end_addr),
    
    // VIC-20 LOAD interface (futuro)
    .vic20_load_req(vic20_load_req),
    .vic20_load_filename(vic20_load_filename),
    .vic20_load_filename_len(vic20_load_filename_len),
    .vic20_load_device(vic20_load_device),
    .vic20_load_secondary(vic20_load_secondary),
    .vic20_load_active(vic20_load_active),
    .vic20_load_complete(vic20_load_complete),
    .vic20_load_error(vic20_load_error),
    .vic20_load_end_addr(vic20_load_end_addr),
    
    // Current core
    .current_core(current_core)
);

//==============================================================================
// ZX SPECTRUM 48K (CPU Z80 + ROM da SD) - Core 2
//==============================================================================

wire [3:0] zx_vga_r, zx_vga_g, zx_vga_b;
wire       zx_vga_hsync, zx_vga_vsync;
wire       zx_audio;

zxspectrum_complete zx_inst (
    .clk(clk),
    .reset_n(rst_n & ~core_reset),
    .enable(current_core == 3'd2),
    .res_mode(SW[8]),           // 0=640x480, 1=800x600
    // VGA
    .vga_r(zx_vga_r),
    .vga_g(zx_vga_g),
    .vga_b(zx_vga_b),
    .vga_hs(zx_vga_hsync),
    .vga_vs(zx_vga_vsync),
    // Keyboard - key_addr contiene il carattere ASCII
    .key_row_data(8'hFF),
    .key_addr(key_code),
    // Keyboard - pass strobe unconditionally, core will handle internally
    .key_strobe(key_strobe),
    // Audio
    .audio_out(zx_audio),
    // ROM loading - attivo quando core=2 (ZX Spectrum)
    .rom_load_en(rom_write && current_core == 3'd2),
    .rom_load_addr(rom_addr[13:0]),
    .rom_load_data(rom_data),
    .rom_load_wr(rom_write && current_core == 3'd2),
    // RAM loading (per snapshot e programmi) - connesso al PRG loader
    .ram_load_en(prg_write && current_core == 3'd2),
    .ram_load_addr(prg_addr),
    .ram_load_data(prg_data),
    .ram_load_wr(prg_write && current_core == 3'd2),
    // Debug
    .debug_pc(),
    .debug_ir()
);

//==============================================================================
// VIC-20 CORE
//==============================================================================

wire [3:0] vic20_vga_r, vic20_vga_g, vic20_vga_b;
wire       vic20_vga_hsync, vic20_vga_vsync;
wire       vic20_audio;

// ROM address per VIC-20
// Il rom_loader già calcola: base_address + bytes_received
// Quindi rom_addr contiene già l'offset corretto, non serve aggiungere altro!
// Bank 0: 0x0000-0x0FFF (4KB char) - rom_addr già 0x0000+
// Bank 1: 0x2000-0x3FFF (8KB basic) - rom_addr già 0x2000+
// Bank 2: 0x4000-0x5FFF (8KB kernal) - rom_addr già 0x4000+
wire [14:0] vic20_rom_addr = rom_addr[14:0];
wire vic20_debug_irq;

vic20_complete vic20_inst (
    .clk(clk),
    .reset_n(rst_n & ~core_reset),
    .enable(current_core == 3'd3),
    .res_mode(SW[8]),           // 0=640x480, 1=800x600
    // VGA
    .vga_r(vic20_vga_r),
    .vga_g(vic20_vga_g),
    .vga_b(vic20_vga_b),
    .vga_hs(vic20_vga_hsync),
    .vga_vs(vic20_vga_vsync),
    // Keyboard
    .key_code(key_code),
    // Keyboard - pass strobe unconditionally, core will handle internally
    .key_strobe(key_strobe),
    // Audio
    .audio_out(vic20_audio),
    // ROM loading - IMPORTANTE: rom_bank seleziona quale ROM
    .rom_load_en(rom_write && current_core == 3'd3),
    .rom_load_addr(rom_addr[14:0]),
    .rom_load_data(rom_data),
    .rom_load_wr(rom_write && current_core == 3'd3),
    .rom_bank(rom_bank[1:0]),
    // PRG loading
    .prg_load_en(prg_write),
    .prg_load_addr(prg_addr),
    .prg_load_data(prg_data),
    .prg_load_wr(prg_write && current_core == 3'd3),
    // Debug
    .debug_pc(),
    .debug_a(),
    .debug_irq(vic20_debug_irq)
);

//==============================================================================
// APPLE I (CPU 6502 + Woz Monitor) - Core 4
//==============================================================================

wire [3:0] apple1_vga_r, apple1_vga_g, apple1_vga_b;
wire       apple1_vga_hsync, apple1_vga_vsync;
wire       apple1_audio;
wire       apple1_debug;

apple1_complete apple1_inst (
    .clk(clk),
    .reset_n(rst_n & ~core_reset),
    .enable(current_core == 3'd4),
    .res_mode(SW[8]),           // 0=640x480, 1=800x600
    // VGA
    .vga_r(apple1_vga_r),
    .vga_g(apple1_vga_g),
    .vga_b(apple1_vga_b),
    .vga_hs(apple1_vga_hsync),
    .vga_vs(apple1_vga_vsync),
    // Keyboard
    .key_code(key_code),
    .key_strobe(key_strobe),
    // Audio (Apple I non aveva audio)
    .audio_out(apple1_audio),
    // ROM loading (per caricare wozmon.bin da SD se necessario)
    .rom_load_en(rom_write && current_core == 3'd4),
    .rom_load_addr(rom_addr),
    .rom_load_data(rom_data),
    .rom_load_wr(rom_write && current_core == 3'd4),
    // Debug
    .debug_out(apple1_debug)
);

//==============================================================================
// VGA OUTPUT MUX (Test Pattern, C64, ZX Spectrum, VIC-20, Apple I)
//==============================================================================

reg [3:0] vga_r_out, vga_g_out, vga_b_out;
reg       vga_hs_out, vga_vs_out;

always @(*) begin
    case (current_core)
        3'd0: begin  // Test Pattern
            vga_r_out = test_vga_r;
            vga_g_out = test_vga_g;
            vga_b_out = test_vga_b;
            vga_hs_out = test_vga_hsync;
            vga_vs_out = test_vga_vsync;
        end
        3'd1: begin  // C64
            vga_r_out = c64_vga_r;
            vga_g_out = c64_vga_g;
            vga_b_out = c64_vga_b;
            vga_hs_out = c64_vga_hsync;
            vga_vs_out = c64_vga_vsync;
        end
        3'd2: begin  // ZX Spectrum
            vga_r_out = zx_vga_r;
            vga_g_out = zx_vga_g;
            vga_b_out = zx_vga_b;
            vga_hs_out = zx_vga_hsync;
            vga_vs_out = zx_vga_vsync;
        end
        3'd3: begin  // VIC-20
            vga_r_out = vic20_vga_r;
            vga_g_out = vic20_vga_g;
            vga_b_out = vic20_vga_b;
            vga_hs_out = vic20_vga_hsync;
            vga_vs_out = vic20_vga_vsync;
        end
        3'd4: begin  // Apple I
            vga_r_out = apple1_vga_r;
            vga_g_out = apple1_vga_g;
            vga_b_out = apple1_vga_b;
            vga_hs_out = apple1_vga_hsync;
            vga_vs_out = apple1_vga_vsync;
        end
        default: begin  // Default: Test Pattern
            vga_r_out = test_vga_r;
            vga_g_out = test_vga_g;
            vga_b_out = test_vga_b;
            vga_hs_out = test_vga_hsync;
            vga_vs_out = test_vga_vsync;
        end
    endcase
end

assign VGA_R = vga_r_out;
assign VGA_G = vga_g_out;
assign VGA_B = vga_b_out;
assign VGA_HS = vga_hs_out;
assign VGA_VS = vga_vs_out;

//==============================================================================
// 7-SEGMENT DISPLAY - Mostra numero core selezionato
//==============================================================================
// Active low: 0 = segment ON, 1 = segment OFF
//     --0--
//    |     |
//    5     1
//    |     |
//     --6--
//    |     |
//    4     2
//    |     |
//     --3--

function [6:0] seg7;
    input [3:0] digit;
    begin
        case (digit)
            4'd0: seg7 = 7'b1000000;  // 0
            4'd1: seg7 = 7'b1111001;  // 1
            4'd2: seg7 = 7'b0100100;  // 2
            4'd3: seg7 = 7'b0110000;  // 3
            4'd4: seg7 = 7'b0011001;  // 4
            4'd5: seg7 = 7'b0010010;  // 5
            4'd6: seg7 = 7'b0000010;  // 6
            4'd7: seg7 = 7'b1111000;  // 7
            4'd8: seg7 = 7'b0000000;  // 8
            4'd9: seg7 = 7'b0010000;  // 9
            default: seg7 = 7'b1111111;  // blank
        endcase
    end
endfunction

// HEX0 mostra il numero del core (0-3)
assign HEX0 = seg7({1'b0, current_core});

// HEX1-HEX5 mostrano nome abbreviato del sistema
// Core 0: tESt (Test Pattern)
// Core 1: C 64
// Core 2: SPEc (Spectrum)
// Core 3: U-20 (VIC-20)

reg [6:0] hex5_reg, hex4_reg, hex3_reg, hex2_reg, hex1_reg;

always @(*) begin
    case (current_core)
        3'd0: begin  // "tESt " + 0
            hex5_reg = 7'b0000111;  // t
            hex4_reg = 7'b0000110;  // E
            hex3_reg = 7'b0010010;  // S
            hex2_reg = 7'b0000111;  // t
            hex1_reg = 7'b1111111;  // blank
        end
        3'd1: begin  // "C 64" + 1
            hex5_reg = 7'b1000110;  // C
            hex4_reg = 7'b1111111;  // blank
            hex3_reg = 7'b0000010;  // 6
            hex2_reg = 7'b0011001;  // 4
            hex1_reg = 7'b1111111;  // blank
        end
        3'd2: begin  // "SPEc" + 2
            hex5_reg = 7'b0010010;  // S
            hex4_reg = 7'b0001100;  // P
            hex3_reg = 7'b0000110;  // E
            hex2_reg = 7'b1000110;  // c
            hex1_reg = 7'b1111111;  // blank
        end
        3'd3: begin  // "U-20" + 3
            hex5_reg = 7'b1000001;  // U
            hex4_reg = 7'b0111111;  // -
            hex3_reg = 7'b0100100;  // 2
            hex2_reg = 7'b1000000;  // 0
            hex1_reg = 7'b1111111;  // blank
        end
        3'd4: begin  // "APL 1" + 4 (Apple I)
            hex5_reg = 7'b0001000;  // A
            hex4_reg = 7'b0001100;  // P
            hex3_reg = 7'b1000111;  // L
            hex2_reg = 7'b1111111;  // blank
            hex1_reg = 7'b1111001;  // 1
        end
        default: begin
            hex5_reg = 7'b1111111;
            hex4_reg = 7'b1111111;
            hex3_reg = 7'b1111111;
            hex2_reg = 7'b1111111;
            hex1_reg = 7'b1111111;
        end
    endcase
end

assign HEX5 = hex5_reg;
assign HEX4 = hex4_reg;
assign HEX3 = hex3_reg;
assign HEX2 = hex2_reg;
assign HEX1 = hex1_reg;

endmodule
