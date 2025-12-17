//==============================================================================
// ROM LOADER - Versione semplificata per flusso continuo
//==============================================================================
// Autore: Angelo Arato
// Data: Novembre 2025
//
// Protocollo:
//   1. Comando ROM_START id size -> risponde ROM_READY
//   2. Riceve 'size' bytes di dati continui (senza checksum intermedi)
//   3. Comando ROM_END xx -> risponde ROM_OK (rilevato internamente)
//==============================================================================

module rom_loader (
    input  wire        clk,
    input  wire        reset_n,
    
    // Dati UART
    input  wire        rx_data_valid,
    input  wire [7:0]  rx_data,
    
    // TX UART
    output reg         tx_start,
    output reg  [7:0]  tx_data,
    input  wire        tx_busy,
    
    // Comandi dal parser
    input  wire        cmd_rom_start,
    input  wire [2:0]  cmd_rom_id,
    input  wire [15:0] cmd_rom_size,
    input  wire        cmd_rom_end,
    
    // Interfaccia scrittura ROM
    output reg         rom_wr_en,
    output reg  [15:0] rom_wr_addr,
    output reg  [7:0]  rom_wr_data,
    
    // Status
    output reg         loading_active,
    output reg         loading_complete,
    output reg  [2:0]  loaded_rom_id,
    output wire [2:0]  current_rom_bank,  // ROM attualmente in caricamento
    
    // Core selezionato
    input  wire [2:0]  current_core
);

//==============================================================================
// STATI FSM
//==============================================================================

localparam [2:0]
    ST_IDLE       = 3'd0,
    ST_SEND_READY = 3'd1,
    ST_RECEIVE    = 3'd2,
    ST_WAIT_END   = 3'd3,
    ST_SEND_OK    = 3'd4;

//==============================================================================
// REGISTRI
//==============================================================================

reg [2:0]  state;
reg [15:0] bytes_expected;
reg [15:0] bytes_received;
reg [2:0]  current_rom_id;
reg [15:0] base_address;

// Esporta current_rom_id durante caricamento
assign current_rom_bank = current_rom_id;

// Buffer messaggi TX
reg [7:0]  msg_buffer [0:15];
reg [3:0]  msg_length;
reg [3:0]  msg_index;

// Rilevamento ROM_END - cerca sequenza "ROM_END" seguita da newline
reg [2:0]  end_match_count;
wire       detected_rom_end;

// ROM_END rilevato quando match completo + newline
assign detected_rom_end = (end_match_count == 3'd7) && rx_data_valid && 
                          (rx_data == 8'h0A || rx_data == 8'h0D);

// Segnale combinato
wire rom_end_signal = cmd_rom_end | detected_rom_end;

//==============================================================================
// INDIRIZZI BASE ROM (dipende dal core)
//==============================================================================
// 
// C64 (core 1): BASIC(8K), KERNAL(8K), CHAR(4K)
//   rom_id 0 → 0x0000 (BASIC)
//   rom_id 1 → 0x2000 (KERNAL)
//   rom_id 2 → 0x4000 (CHAR)
//
// ZX Spectrum (core 2): ROM singola 16K
//   rom_id 3 → 0x0000
//
// VIC-20 (core 3): BASIC(8K), KERNAL(8K), CHAR(4K)
//   ESP32 manda: BASIC, KERNAL, CHAR
//   rom_id 0 → 0x2000 (BASIC va qui)
//   rom_id 1 → 0x4000 (KERNAL va qui)
//   rom_id 2 → 0x0000 (CHAR va qui)
//
// Apple II (core 4): ROM singola
//   rom_id 0 → 0x0000
//==============================================================================

function [15:0] get_rom_base;
    input [2:0] rom_id;
    begin
        case (current_core)
            3'd3: begin  // VIC-20: ordine CHAR, BASIC, KERNAL (come da ESP32)
                case (rom_id)
                    3'd0: get_rom_base = 16'h0000;  // CHAR → 0x0000 (4KB)
                    3'd1: get_rom_base = 16'h2000;  // BASIC → 0x2000 (8KB)
                    3'd2: get_rom_base = 16'h4000;  // KERNAL → 0x4000 (8KB)
                    default: get_rom_base = 16'h0000;
                endcase
            end
            default: begin  // C64, ZX Spectrum, Apple II
                case (rom_id)
                    3'd0: get_rom_base = 16'h0000;
                    3'd1: get_rom_base = 16'h2000;
                    3'd2: get_rom_base = 16'h4000;
                    3'd3: get_rom_base = 16'h0000;  // ZX Spectrum
                    default: get_rom_base = 16'h0000;
                endcase
            end
        endcase
    end
endfunction

//==============================================================================
// RILEVAMENTO ROM_END
//==============================================================================

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        end_match_count <= 3'd0;
    end else if (state == ST_IDLE) begin
        end_match_count <= 3'd0;
    end else if (rx_data_valid && (state == ST_WAIT_END)) begin
        case (end_match_count)
            3'd0: end_match_count <= (rx_data == "R") ? 3'd1 : 3'd0;
            3'd1: end_match_count <= (rx_data == "O") ? 3'd2 : (rx_data == "R") ? 3'd1 : 3'd0;
            3'd2: end_match_count <= (rx_data == "M") ? 3'd3 : (rx_data == "R") ? 3'd1 : 3'd0;
            3'd3: end_match_count <= (rx_data == "_") ? 3'd4 : (rx_data == "R") ? 3'd1 : 3'd0;
            3'd4: end_match_count <= (rx_data == "E") ? 3'd5 : (rx_data == "R") ? 3'd1 : 3'd0;
            3'd5: end_match_count <= (rx_data == "N") ? 3'd6 : (rx_data == "R") ? 3'd1 : 3'd0;
            3'd6: end_match_count <= (rx_data == "D") ? 3'd7 : (rx_data == "R") ? 3'd1 : 3'd0;
            3'd7: end_match_count <= 3'd7; // Mantieni fino al newline
            default: end_match_count <= 3'd0;
        endcase
    end
end

//==============================================================================
// FSM PRINCIPALE
//==============================================================================

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= ST_IDLE;
        bytes_expected <= 16'd0;
        bytes_received <= 16'd0;
        current_rom_id <= 3'd0;
        base_address <= 16'd0;
        loading_active <= 1'b0;
        loading_complete <= 1'b0;
        loaded_rom_id <= 3'd0;
        rom_wr_en <= 1'b0;
        rom_wr_addr <= 16'd0;
        rom_wr_data <= 8'd0;
        tx_start <= 1'b0;
        tx_data <= 8'd0;
        msg_length <= 4'd0;
        msg_index <= 4'd0;
        
    end else begin
        // Default
        rom_wr_en <= 1'b0;
        tx_start <= 1'b0;
        
        case (state)
            //------------------------------------------------------------------
            ST_IDLE: begin
                loading_complete <= 1'b0;
                
                if (cmd_rom_start) begin
                    current_rom_id <= cmd_rom_id;
                    bytes_expected <= cmd_rom_size;
                    bytes_received <= 16'd0;
                    base_address <= get_rom_base(cmd_rom_id);
                    loading_active <= 1'b1;
                    
                    // Prepara risposta "ROM_READY\n"
                    msg_buffer[0] <= "R";
                    msg_buffer[1] <= "O";
                    msg_buffer[2] <= "M";
                    msg_buffer[3] <= "_";
                    msg_buffer[4] <= "R";
                    msg_buffer[5] <= "E";
                    msg_buffer[6] <= "A";
                    msg_buffer[7] <= "D";
                    msg_buffer[8] <= "Y";
                    msg_buffer[9] <= 8'h0A;
                    msg_length <= 4'd10;
                    msg_index <= 4'd0;
                    state <= ST_SEND_READY;
                end
            end
            
            //------------------------------------------------------------------
            ST_SEND_READY: begin
                if (!tx_busy && msg_index < msg_length) begin
                    tx_data <= msg_buffer[msg_index];
                    tx_start <= 1'b1;
                    msg_index <= msg_index + 1'd1;
                end else if (msg_index >= msg_length) begin
                    state <= ST_RECEIVE;
                end
            end
            
            //------------------------------------------------------------------
            ST_RECEIVE: begin
                if (rx_data_valid) begin
                    // Scrivi byte in ROM
                    rom_wr_en <= 1'b1;
                    rom_wr_addr <= base_address + bytes_received;
                    rom_wr_data <= rx_data;
                    bytes_received <= bytes_received + 1'd1;
                    
                    // Controlla se abbiamo ricevuto tutto
                    if (bytes_received + 1 >= bytes_expected) begin
                        state <= ST_WAIT_END;
                    end
                end
            end
            
            //------------------------------------------------------------------
            ST_WAIT_END: begin
                // Rileva ROM_END sia dal parser che internamente
                if (rom_end_signal) begin
                    // Prepara risposta "ROM_OK\n"
                    msg_buffer[0] <= "R";
                    msg_buffer[1] <= "O";
                    msg_buffer[2] <= "M";
                    msg_buffer[3] <= "_";
                    msg_buffer[4] <= "O";
                    msg_buffer[5] <= "K";
                    msg_buffer[6] <= 8'h0A;
                    msg_length <= 4'd7;
                    msg_index <= 4'd0;
                    loading_complete <= 1'b1;
                    loaded_rom_id <= current_rom_id;
                    state <= ST_SEND_OK;
                end
            end
            
            //------------------------------------------------------------------
            ST_SEND_OK: begin
                if (!tx_busy && msg_index < msg_length) begin
                    tx_data <= msg_buffer[msg_index];
                    tx_start <= 1'b1;
                    msg_index <= msg_index + 1'd1;
                end else if (msg_index >= msg_length) begin
                    loading_active <= 1'b0;
                    state <= ST_IDLE;
                end
            end
            
            //------------------------------------------------------------------
            default: state <= ST_IDLE;
            
        endcase
    end
end

endmodule
