//==============================================================================
// COMMAND PARSER - Versione ottimizzata (buffer ridotti)
//==============================================================================
// Autore: Angelo Arato  
// Data: Novembre 2025
//
// Comandi: PING, STATUS, RESET, SELECT_CORE X, ROM_START X Y, ROM_END, BOOT, KEY_CHAR X, KEY_RET
//==============================================================================

module command_parser (
    input  wire        clk,
    input  wire        reset_n,
    
    input  wire        rx_valid,
    input  wire [7:0]  rx_data,
    
    output reg         tx_start,
    output reg  [7:0]  tx_data,
    input  wire        tx_busy,
    
    output reg         cmd_ping,
    output reg         cmd_status,
    output reg         cmd_reset,
    output reg         cmd_select_core,
    output reg  [2:0]  cmd_core_id,
    output reg         cmd_rom_start,
    output reg  [2:0]  cmd_rom_id,
    output reg  [15:0] cmd_rom_size,
    output reg         cmd_rom_end,
    output reg         cmd_boot,
    output reg         cmd_key_char,
    output reg  [7:0]  cmd_key_data,
    
    // PRG loader
    output reg         cmd_prg_start,
    output reg  [15:0] cmd_prg_addr,
    output reg  [15:0] cmd_prg_size,
    output reg         cmd_prg_end,
    output reg         prg_data_mode,    // Modalità ricezione dati PRG
    output reg  [7:0]  prg_byte,         // Byte PRG ricevuto
    output reg         prg_byte_valid,   // Byte PRG valido
    output reg  [15:0] prg_write_addr,   // Indirizzo dove scrivere il byte
    
    input  wire [2:0]  current_core,
    input  wire        rom_loaded,
    
    output reg         mode_rom_data
);

//==============================================================================
// PARAMETRI - Buffer ridotti per risparmiare LABs
//==============================================================================

localparam MAX_CMD_LEN = 20;  // Ridotto da 32

localparam [2:0]
    ST_IDLE     = 3'd0,
    ST_RECEIVE  = 3'd1,
    ST_PARSE    = 3'd2,
    ST_RESPOND  = 3'd3,
    ST_PRG_DATA = 3'd4;  // Ricezione dati PRG

//==============================================================================
// REGISTRI
//==============================================================================

reg [2:0]  state;
reg [7:0]  cmd_buf_0, cmd_buf_1, cmd_buf_2, cmd_buf_3;
reg [7:0]  cmd_buf_4, cmd_buf_5, cmd_buf_6, cmd_buf_7;
reg [7:0]  cmd_buf_8, cmd_buf_9, cmd_buf_10, cmd_buf_11;
reg [7:0]  cmd_buf_12, cmd_buf_13, cmd_buf_14, cmd_buf_15;
reg [7:0]  cmd_buf_16, cmd_buf_17, cmd_buf_18, cmd_buf_19;  // Extra per PROG_START
reg [4:0]  cmd_length;

// Risposta - registri separati
reg [7:0]  resp_0, resp_1, resp_2, resp_3, resp_4, resp_5, resp_6, resp_7;
reg [7:0]  resp_8, resp_9, resp_10, resp_11, resp_12, resp_13, resp_14, resp_15;
reg [4:0]  resp_length;
reg [4:0]  resp_index;

// PRG loader
reg [15:0] prg_load_addr;    // Indirizzo corrente di caricamento
reg [15:0] prg_bytes_left;   // Bytes rimanenti

//==============================================================================
// FUNZIONI HELPER
//==============================================================================

// Converte carattere ASCII digit in valore, 0 se non valido
function [3:0] digit_val;
    input [7:0] c;
    begin
        if (c >= "0" && c <= "9")
            digit_val = c - "0";
        else
            digit_val = 4'd0;
    end
endfunction

// Converte carattere hex ASCII in valore 4-bit
function [3:0] hex_to_bin;
    input [7:0] c;
    begin
        if (c >= "0" && c <= "9")
            hex_to_bin = c - "0";
        else if (c >= "A" && c <= "F")
            hex_to_bin = c - "A" + 10;
        else if (c >= "a" && c <= "f")
            hex_to_bin = c - "a" + 10;
        else
            hex_to_bin = 4'd0;
    end
endfunction

// Controlla se carattere è digit
function is_digit;
    input [7:0] c;
    begin
        is_digit = (c >= "0" && c <= "9");
    end
endfunction

// Parse numero decimale da max 5 caratteri (supporta fino a 65535)
function [15:0] parse_decimal;
    input [7:0] c0, c1, c2, c3, c4, c5;
    input [4:0] len;
    reg [15:0] val;
    begin
        val = 0;
        // Posizione 12 (c0)
        if (len > 12 && is_digit(c0)) val = digit_val(c0);
        // Posizione 13 (c1)
        if (len > 13 && is_digit(c1)) val = val * 10 + digit_val(c1);
        // Posizione 14 (c2)
        if (len > 14 && is_digit(c2)) val = val * 10 + digit_val(c2);
        // Posizione 15 (c3)
        if (len > 15 && is_digit(c3)) val = val * 10 + digit_val(c3);
        // Posizione 16 (c4)
        if (len > 16 && is_digit(c4)) val = val * 10 + digit_val(c4);
        // Posizione 17 (c5) - per numeri tipo 16384
        if (len > 17 && is_digit(c5)) val = val * 10 + digit_val(c5);
        parse_decimal = val;
    end
endfunction

function [7:0] get_cmd_byte;
    input [4:0] idx;
    begin
        case (idx)
            5'd0:  get_cmd_byte = cmd_buf_0;
            5'd1:  get_cmd_byte = cmd_buf_1;
            5'd2:  get_cmd_byte = cmd_buf_2;
            5'd3:  get_cmd_byte = cmd_buf_3;
            5'd4:  get_cmd_byte = cmd_buf_4;
            5'd5:  get_cmd_byte = cmd_buf_5;
            5'd6:  get_cmd_byte = cmd_buf_6;
            5'd7:  get_cmd_byte = cmd_buf_7;
            5'd8:  get_cmd_byte = cmd_buf_8;
            5'd9:  get_cmd_byte = cmd_buf_9;
            5'd10: get_cmd_byte = cmd_buf_10;
            5'd11: get_cmd_byte = cmd_buf_11;
            5'd12: get_cmd_byte = cmd_buf_12;
            5'd13: get_cmd_byte = cmd_buf_13;
            5'd14: get_cmd_byte = cmd_buf_14;
            5'd15: get_cmd_byte = cmd_buf_15;
            default: get_cmd_byte = 8'd0;
        endcase
    end
endfunction

function [7:0] get_resp_byte;
    input [4:0] idx;
    begin
        case (idx)
            5'd0:  get_resp_byte = resp_0;
            5'd1:  get_resp_byte = resp_1;
            5'd2:  get_resp_byte = resp_2;
            5'd3:  get_resp_byte = resp_3;
            5'd4:  get_resp_byte = resp_4;
            5'd5:  get_resp_byte = resp_5;
            5'd6:  get_resp_byte = resp_6;
            5'd7:  get_resp_byte = resp_7;
            5'd8:  get_resp_byte = resp_8;
            5'd9:  get_resp_byte = resp_9;
            5'd10: get_resp_byte = resp_10;
            5'd11: get_resp_byte = resp_11;
            5'd12: get_resp_byte = resp_12;
            5'd13: get_resp_byte = resp_13;
            5'd14: get_resp_byte = resp_14;
            5'd15: get_resp_byte = resp_15;
            default: get_resp_byte = 8'd0;
        endcase
    end
endfunction

//==============================================================================
// FSM
//==============================================================================

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= ST_IDLE;
        cmd_length <= 0;
        resp_length <= 0;
        resp_index <= 0;
        cmd_ping <= 0; cmd_status <= 0; cmd_reset <= 0;
        cmd_select_core <= 0; cmd_core_id <= 0;
        cmd_rom_start <= 0; cmd_rom_id <= 0; cmd_rom_size <= 0;
        cmd_rom_end <= 0; cmd_boot <= 0;
        cmd_key_char <= 0; cmd_key_data <= 0;
        cmd_prg_start <= 0; cmd_prg_addr <= 0; cmd_prg_size <= 0;
        cmd_prg_end <= 0; prg_data_mode <= 0;
        prg_byte <= 0; prg_byte_valid <= 0; prg_write_addr <= 0;
        prg_load_addr <= 0; prg_bytes_left <= 0;
        mode_rom_data <= 0;
        tx_start <= 0; tx_data <= 0;
    end else begin
        // Clear one-shot signals (tranne cmd_key_char che viene gestito separatamente)
        cmd_ping <= 0; cmd_status <= 0; cmd_reset <= 0;
        cmd_select_core <= 0; cmd_rom_start <= 0; cmd_rom_end <= 0;
        cmd_boot <= 0; cmd_prg_start <= 0; cmd_prg_end <= 0;
        prg_byte_valid <= 0;
        tx_start <= 0;
        
        // cmd_key_char rimane alto per un ciclo poi si resetta
        if (cmd_key_char) cmd_key_char <= 0;
        
        case (state)
            ST_IDLE: begin
                cmd_length <= 0;
                if (rx_valid && rx_data != 8'h0A && rx_data != 8'h0D) begin
                    cmd_buf_0 <= rx_data;
                    cmd_length <= 1;
                    state <= ST_RECEIVE;
                end
            end
            
            ST_RECEIVE: begin
                if (rx_valid) begin
                    // Per KEY_CHAR, il 10° carattere è il dato (può essere 0x0D/0x0A)
                    // Quindi terminiamo solo dopo aver ricevuto il carattere
                    if (cmd_length >= 9 && cmd_buf_0 == "K" && cmd_buf_1 == "E" &&
                        cmd_buf_2 == "Y" && cmd_buf_3 == "_") begin
                        // È un comando KEY_CHAR - il prossimo byte è il carattere
                        if (cmd_length == 9) begin
                            cmd_buf_9 <= rx_data;
                            cmd_length <= cmd_length + 1'd1;
                        end else begin
                            // Dopo il carattere, qualsiasi cosa termina il comando
                            state <= ST_PARSE;
                        end
                    end
                    else if (rx_data == 8'h0A || rx_data == 8'h0D) begin
                        state <= ST_PARSE;
                    end else if (cmd_length < MAX_CMD_LEN) begin
                        case (cmd_length)
                            5'd1:  cmd_buf_1 <= rx_data;
                            5'd2:  cmd_buf_2 <= rx_data;
                            5'd3:  cmd_buf_3 <= rx_data;
                            5'd4:  cmd_buf_4 <= rx_data;
                            5'd5:  cmd_buf_5 <= rx_data;
                            5'd6:  cmd_buf_6 <= rx_data;
                            5'd7:  cmd_buf_7 <= rx_data;
                            5'd8:  cmd_buf_8 <= rx_data;
                            5'd9:  cmd_buf_9 <= rx_data;
                            5'd10: cmd_buf_10 <= rx_data;
                            5'd11: cmd_buf_11 <= rx_data;
                            5'd12: cmd_buf_12 <= rx_data;
                            5'd13: cmd_buf_13 <= rx_data;
                            5'd14: cmd_buf_14 <= rx_data;
                            5'd15: cmd_buf_15 <= rx_data;
                            5'd16: cmd_buf_16 <= rx_data;
                            5'd17: cmd_buf_17 <= rx_data;
                            5'd18: cmd_buf_18 <= rx_data;
                            5'd19: cmd_buf_19 <= rx_data;
                        endcase
                        cmd_length <= cmd_length + 1'd1;
                    end
                end
            end
            
            ST_PARSE: begin
                // PING
                if (cmd_length == 4 && cmd_buf_0 == "P" && cmd_buf_1 == "I" && 
                    cmd_buf_2 == "N" && cmd_buf_3 == "G") begin
                    cmd_ping <= 1;
                    // "PONG\n"
                    resp_0 <= "P"; resp_1 <= "O"; resp_2 <= "N"; resp_3 <= "G"; resp_4 <= 8'h0A;
                    resp_length <= 5;
                    resp_index <= 0;
                    state <= ST_RESPOND;
                end
                // STATUS
                else if (cmd_length == 6 && cmd_buf_0 == "S" && cmd_buf_1 == "T" &&
                         cmd_buf_2 == "A" && cmd_buf_3 == "T" && cmd_buf_4 == "U" && cmd_buf_5 == "S") begin
                    cmd_status <= 1;
                    // "CORE=X ROM=Y\n"
                    resp_0 <= "C"; resp_1 <= "O"; resp_2 <= "R"; resp_3 <= "E"; resp_4 <= "=";
                    resp_5 <= "0" + {5'd0, current_core};
                    resp_6 <= " "; resp_7 <= "R"; resp_8 <= "O"; resp_9 <= "M"; resp_10 <= "=";
                    resp_11 <= rom_loaded ? "1" : "0";
                    resp_12 <= 8'h0A;  // newline
                    resp_length <= 13;
                    resp_index <= 0;
                    state <= ST_RESPOND;
                end
                // RESET
                else if (cmd_length == 5 && cmd_buf_0 == "R" && cmd_buf_1 == "E" &&
                         cmd_buf_2 == "S" && cmd_buf_3 == "E" && cmd_buf_4 == "T") begin
                    cmd_reset <= 1;
                    resp_0 <= "O"; resp_1 <= "K"; resp_2 <= 8'h0A;
                    resp_length <= 3;
                    resp_index <= 0;
                    state <= ST_RESPOND;
                end
                // SELECT_CORE X
                else if (cmd_length >= 12 && cmd_buf_0 == "S" && cmd_buf_1 == "E" &&
                         cmd_buf_2 == "L" && cmd_buf_3 == "E" && cmd_buf_4 == "C" &&
                         cmd_buf_5 == "T" && cmd_buf_6 == "_" && cmd_buf_7 == "C" &&
                         cmd_buf_8 == "O" && cmd_buf_9 == "R" && cmd_buf_10 == "E") begin
                    cmd_select_core <= 1;
                    cmd_core_id <= cmd_buf_12[2:0] - 3'd0;  // ASCII to num
                    // "OK CORE=X\n"
                    resp_0 <= "O"; resp_1 <= "K"; resp_2 <= " "; resp_3 <= "C"; resp_4 <= "O";
                    resp_5 <= "R"; resp_6 <= "E"; resp_7 <= "="; resp_8 <= cmd_buf_12; resp_9 <= 8'h0A;
                    resp_length <= 10;
                    resp_index <= 0;
                    state <= ST_RESPOND;
                end
                // ROM_START X Y  (es: "ROM_START 0 8192")
                else if (cmd_length >= 10 && cmd_buf_0 == "R" && cmd_buf_1 == "O" &&
                         cmd_buf_2 == "M" && cmd_buf_3 == "_" && cmd_buf_4 == "S" &&
                         cmd_buf_5 == "T" && cmd_buf_6 == "A" && cmd_buf_7 == "R" && cmd_buf_8 == "T") begin
                    cmd_rom_start <= 1;
                    cmd_rom_id <= cmd_buf_10 - "0";
                    // Parse size - posizioni fisse 12-15 (max 9999 o 5 cifre)
                    // Parsing semplificato senza loop
                    cmd_rom_size <= parse_decimal(cmd_buf_12, cmd_buf_13, cmd_buf_14, cmd_buf_15, cmd_buf_16, cmd_buf_17, cmd_length);
                    mode_rom_data <= 1;
                    state <= ST_IDLE;  // rom_loader risponde
                end
                // ROM_END
                else if (cmd_length >= 7 && cmd_buf_0 == "R" && cmd_buf_1 == "O" &&
                         cmd_buf_2 == "M" && cmd_buf_3 == "_" && cmd_buf_4 == "E" &&
                         cmd_buf_5 == "N" && cmd_buf_6 == "D") begin
                    cmd_rom_end <= 1;
                    mode_rom_data <= 0;
                    state <= ST_IDLE;  // rom_loader risponde
                end
                // BOOT
                else if (cmd_length == 4 && cmd_buf_0 == "B" && cmd_buf_1 == "O" &&
                         cmd_buf_2 == "O" && cmd_buf_3 == "T") begin
                    cmd_boot <= 1;
                    mode_rom_data <= 0;  // Assicura reset
                    resp_0 <= "B"; resp_1 <= "O"; resp_2 <= "O"; resp_3 <= "T";
                    resp_4 <= "_"; resp_5 <= "O"; resp_6 <= "K"; resp_7 <= 8'h0A;
                    resp_length <= 8;
                    resp_index <= 0;
                    state <= ST_RESPOND;
                end
                // KEY_CHAR X
                else if (cmd_length >= 9 && cmd_buf_0 == "K" && cmd_buf_1 == "E" &&
                         cmd_buf_2 == "Y" && cmd_buf_3 == "_" && cmd_buf_4 == "C" &&
                         cmd_buf_5 == "H" && cmd_buf_6 == "A" && cmd_buf_7 == "R") begin
                    cmd_key_char <= 1;
                    cmd_key_data <= cmd_buf_9;
                    state <= ST_IDLE;  // No response
                end
                // KEY_RET - Invia RETURN (0x0D) - comando dedicato per evitare conflitto con CR
                else if (cmd_length >= 7 && cmd_buf_0 == "K" && cmd_buf_1 == "E" &&
                         cmd_buf_2 == "Y" && cmd_buf_3 == "_" && cmd_buf_4 == "R" &&
                         cmd_buf_5 == "E" && cmd_buf_6 == "T") begin
                    cmd_key_char <= 1;
                    cmd_key_data <= 8'h0D;  // RETURN/CR
                    state <= ST_IDLE;  // No response
                end
                // PROG_START AAAA SSSS (hex address, hex size)
                else if (cmd_length >= 15 && cmd_buf_0 == "P" && cmd_buf_1 == "R" &&
                         cmd_buf_2 == "O" && cmd_buf_3 == "G" && cmd_buf_4 == "_" &&
                         cmd_buf_5 == "S" && cmd_buf_6 == "T" && cmd_buf_7 == "A" &&
                         cmd_buf_8 == "R" && cmd_buf_9 == "T") begin
                    // Parse address (4 hex digits at pos 11-14)
                    cmd_prg_addr <= {hex_to_bin(cmd_buf_11), hex_to_bin(cmd_buf_12),
                                     hex_to_bin(cmd_buf_13), hex_to_bin(cmd_buf_14)};
                    // Parse size (4 hex digits at pos 16-19)
                    cmd_prg_size <= {hex_to_bin(cmd_buf_16), hex_to_bin(cmd_buf_17),
                                     hex_to_bin(cmd_buf_18), hex_to_bin(cmd_buf_19)};
                    prg_load_addr <= {hex_to_bin(cmd_buf_11), hex_to_bin(cmd_buf_12),
                                      hex_to_bin(cmd_buf_13), hex_to_bin(cmd_buf_14)};
                    prg_bytes_left <= {hex_to_bin(cmd_buf_16), hex_to_bin(cmd_buf_17),
                                       hex_to_bin(cmd_buf_18), hex_to_bin(cmd_buf_19)};
                    cmd_prg_start <= 1;
                    prg_data_mode <= 1;
                    resp_0 <= "P"; resp_1 <= "R"; resp_2 <= "G"; resp_3 <= "_";
                    resp_4 <= "O"; resp_5 <= "K"; resp_6 <= 8'h0A;
                    resp_length <= 7;
                    resp_index <= 0;
                    state <= ST_RESPOND;
                end
                // PROG_END
                else if (cmd_length >= 8 && cmd_buf_0 == "P" && cmd_buf_1 == "R" &&
                         cmd_buf_2 == "O" && cmd_buf_3 == "G" && cmd_buf_4 == "_" &&
                         cmd_buf_5 == "E" && cmd_buf_6 == "N" && cmd_buf_7 == "D") begin
                    cmd_prg_end <= 1;
                    prg_data_mode <= 0;
                    resp_0 <= "P"; resp_1 <= "R"; resp_2 <= "G"; resp_3 <= "_";
                    resp_4 <= "D"; resp_5 <= "O"; resp_6 <= "N"; resp_7 <= "E";
                    resp_8 <= 8'h0A;
                    resp_length <= 9;
                    resp_index <= 0;
                    state <= ST_RESPOND;
                end
                else begin
                    // Unknown - respond ERR
                    resp_0 <= "E"; resp_1 <= "R"; resp_2 <= "R"; resp_3 <= 8'h0A;
                    resp_length <= 4;
                    resp_index <= 0;
                    state <= ST_RESPOND;
                end
            end
            
            ST_RESPOND: begin
                if (!tx_busy && resp_index < resp_length) begin
                    tx_data <= get_resp_byte(resp_index);
                    tx_start <= 1;
                    resp_index <= resp_index + 1'd1;
                end else if (resp_index >= resp_length) begin
                    // Se siamo in modalità PRG, vai a ricevere dati
                    if (prg_data_mode && prg_bytes_left > 0)
                        state <= ST_PRG_DATA;
                    else
                        state <= ST_IDLE;
                end
            end
            
            ST_PRG_DATA: begin
                // Ricevi dati binari PRG
                if (rx_valid) begin
                    prg_byte <= rx_data;
                    prg_byte_valid <= 1;
                    prg_write_addr <= prg_load_addr;  // Indirizzo corrente
                    prg_load_addr <= prg_load_addr + 1'd1;
                    prg_bytes_left <= prg_bytes_left - 1'd1;
                    
                    if (prg_bytes_left == 1) begin
                        // Ultimo byte
                        prg_data_mode <= 0;
                        state <= ST_IDLE;
                    end
                end
            end
            
            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
