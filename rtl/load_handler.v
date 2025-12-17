//==============================================================================
// LOAD HANDLER - Gestisce LOAD virtuale tra C64/VIC-20 e ESP32
//==============================================================================
// Intercetta richieste LOAD dalla CPU e le inoltra all'ESP32 via UART
// Protocollo:
//   FPGA -> ESP32: "LOAD_REQ filename device secondary\n"
//   ESP32 -> FPGA: "LOAD_ACK\n" (inizia caricamento)
//   ESP32 -> FPGA: "LOAD_OK AAAA\n" (completato, AAAA = end address)
//   ESP32 -> FPGA: "LOAD_ERR\n" (errore)
//==============================================================================

module load_handler (
    input  wire        clk,
    input  wire        reset_n,
    
    // UART TX
    output reg         tx_start,
    output reg  [7:0]  tx_data,
    input  wire        tx_busy,
    
    // UART RX (per risposte)
    input  wire        rx_valid,
    input  wire [7:0]  rx_data,
    
    // C64 LOAD interface
    input  wire        c64_load_req,
    input  wire [127:0] c64_load_filename,
    input  wire [3:0]  c64_load_filename_len,
    input  wire [7:0]  c64_load_device,
    input  wire        c64_load_secondary,
    output reg         c64_load_active,
    output reg         c64_load_complete,
    output reg         c64_load_error,
    output reg  [15:0] c64_load_end_addr,
    
    // VIC-20 LOAD interface (futuro)
    input  wire        vic20_load_req,
    input  wire [127:0] vic20_load_filename,
    input  wire [3:0]  vic20_load_filename_len,
    input  wire [7:0]  vic20_load_device,
    input  wire        vic20_load_secondary,
    output reg         vic20_load_active,
    output reg         vic20_load_complete,
    output reg         vic20_load_error,
    output reg  [15:0] vic20_load_end_addr,
    
    // Current core
    input  wire [2:0]  current_core
);

//==============================================================================
// STATI
//==============================================================================
localparam ST_IDLE         = 4'd0;
localparam ST_SEND_CMD     = 4'd1;   // "LOAD_REQ "
localparam ST_SEND_FNAME   = 4'd2;   // filename
localparam ST_SEND_SPACE1  = 4'd3;   // " "
localparam ST_SEND_DEVICE  = 4'd4;   // device (hex)
localparam ST_SEND_SPACE2  = 4'd5;   // " "
localparam ST_SEND_SEC     = 4'd6;   // secondary
localparam ST_SEND_NEWLINE = 4'd7;   // "\n"
localparam ST_WAIT_ACK     = 4'd8;   // Aspetta LOAD_ACK
localparam ST_WAIT_DONE    = 4'd9;   // Aspetta LOAD_OK o LOAD_ERR
localparam ST_DONE         = 4'd10;

reg [3:0] state;
reg [4:0] send_index;
reg [3:0] fname_index;

// Buffer per comando "LOAD_REQ "
localparam [79:0] CMD_PREFIX = "LOAD_REQ ";  // 9 chars
reg [3:0] cmd_index;

// Buffer per risposta
reg [7:0] resp_buf [0:15];
reg [3:0] resp_index;

// Registri per parametri attivi
reg [127:0] active_filename;
reg [3:0]   active_fname_len;
reg [7:0]   active_device;
reg         active_secondary;
reg [2:0]   active_core;  // 1=C64, 3=VIC-20

// Funzione hex to ASCII
function [7:0] hex_to_ascii;
    input [3:0] hex;
    begin
        if (hex < 10)
            hex_to_ascii = 8'h30 + hex;  // '0'-'9'
        else
            hex_to_ascii = 8'h41 + hex - 10;  // 'A'-'F'
    end
endfunction

//==============================================================================
// MACCHINA A STATI
//==============================================================================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= ST_IDLE;
        tx_start <= 0;
        tx_data <= 0;
        send_index <= 0;
        fname_index <= 0;
        cmd_index <= 0;
        resp_index <= 0;
        c64_load_active <= 0;
        c64_load_complete <= 0;
        c64_load_error <= 0;
        c64_load_end_addr <= 0;
        vic20_load_active <= 0;
        vic20_load_complete <= 0;
        vic20_load_error <= 0;
        vic20_load_end_addr <= 0;
    end else begin
        // Clear one-shot signals
        tx_start <= 0;
        c64_load_complete <= 0;
        c64_load_error <= 0;
        vic20_load_complete <= 0;
        vic20_load_error <= 0;
        
        case (state)
            ST_IDLE: begin
                // Controlla richieste LOAD
                if (c64_load_req && current_core == 3'd1) begin
                    active_filename <= c64_load_filename;
                    active_fname_len <= c64_load_filename_len;
                    active_device <= c64_load_device;
                    active_secondary <= c64_load_secondary;
                    active_core <= 3'd1;
                    c64_load_active <= 1;
                    cmd_index <= 0;
                    state <= ST_SEND_CMD;
                end
                else if (vic20_load_req && current_core == 3'd3) begin
                    active_filename <= vic20_load_filename;
                    active_fname_len <= vic20_load_filename_len;
                    active_device <= vic20_load_device;
                    active_secondary <= vic20_load_secondary;
                    active_core <= 3'd3;
                    vic20_load_active <= 1;
                    cmd_index <= 0;
                    state <= ST_SEND_CMD;
                end
            end
            
            ST_SEND_CMD: begin
                // Invia "LOAD_REQ "
                if (!tx_busy && !tx_start) begin
                    case (cmd_index)
                        4'd0: tx_data <= "L";
                        4'd1: tx_data <= "O";
                        4'd2: tx_data <= "A";
                        4'd3: tx_data <= "D";
                        4'd4: tx_data <= "_";
                        4'd5: tx_data <= "R";
                        4'd6: tx_data <= "E";
                        4'd7: tx_data <= "Q";
                        4'd8: tx_data <= " ";
                        default: tx_data <= " ";
                    endcase
                    tx_start <= 1;
                    
                    if (cmd_index == 4'd8) begin
                        fname_index <= 0;
                        state <= ST_SEND_FNAME;
                    end else begin
                        cmd_index <= cmd_index + 1;
                    end
                end
            end
            
            ST_SEND_FNAME: begin
                // Invia filename (packed in 128 bit, MSB first)
                if (!tx_busy && !tx_start) begin
                    // Estrai carattere dal filename packed
                    // filename[127:120] = char 0, filename[119:112] = char 1, etc.
                    case (fname_index)
                        4'd0:  tx_data <= active_filename[127:120];
                        4'd1:  tx_data <= active_filename[119:112];
                        4'd2:  tx_data <= active_filename[111:104];
                        4'd3:  tx_data <= active_filename[103:96];
                        4'd4:  tx_data <= active_filename[95:88];
                        4'd5:  tx_data <= active_filename[87:80];
                        4'd6:  tx_data <= active_filename[79:72];
                        4'd7:  tx_data <= active_filename[71:64];
                        4'd8:  tx_data <= active_filename[63:56];
                        4'd9:  tx_data <= active_filename[55:48];
                        4'd10: tx_data <= active_filename[47:40];
                        4'd11: tx_data <= active_filename[39:32];
                        4'd12: tx_data <= active_filename[31:24];
                        4'd13: tx_data <= active_filename[23:16];
                        4'd14: tx_data <= active_filename[15:8];
                        4'd15: tx_data <= active_filename[7:0];
                    endcase
                    tx_start <= 1;
                    
                    if (fname_index == active_fname_len - 1 || fname_index == 4'd15) begin
                        state <= ST_SEND_SPACE1;
                    end else begin
                        fname_index <= fname_index + 1;
                    end
                end
            end
            
            ST_SEND_SPACE1: begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= " ";
                    tx_start <= 1;
                    send_index <= 0;
                    state <= ST_SEND_DEVICE;
                end
            end
            
            ST_SEND_DEVICE: begin
                // Invia device come 2 cifre hex
                if (!tx_busy && !tx_start) begin
                    if (send_index == 0) begin
                        tx_data <= hex_to_ascii(active_device[7:4]);
                        tx_start <= 1;
                        send_index <= 1;
                    end else begin
                        tx_data <= hex_to_ascii(active_device[3:0]);
                        tx_start <= 1;
                        state <= ST_SEND_SPACE2;
                    end
                end
            end
            
            ST_SEND_SPACE2: begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= " ";
                    tx_start <= 1;
                    state <= ST_SEND_SEC;
                end
            end
            
            ST_SEND_SEC: begin
                // Invia secondary address (0 o 1)
                if (!tx_busy && !tx_start) begin
                    tx_data <= active_secondary ? "1" : "0";
                    tx_start <= 1;
                    state <= ST_SEND_NEWLINE;
                end
            end
            
            ST_SEND_NEWLINE: begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= 8'h0A;  // newline
                    tx_start <= 1;
                    resp_index <= 0;
                    state <= ST_WAIT_ACK;
                end
            end
            
            ST_WAIT_ACK: begin
                // Aspetta risposta dall'ESP32
                // Leggi caratteri finché non ricevi newline
                if (rx_valid) begin
                    if (rx_data == 8'h0A) begin
                        // Fine risposta - controlla
                        // "LOAD_ACK" = vai avanti
                        // "LOAD_ERR" = errore
                        if (resp_index >= 7 && 
                            resp_buf[0] == "L" && resp_buf[1] == "O" &&
                            resp_buf[2] == "A" && resp_buf[3] == "D" &&
                            resp_buf[4] == "_") begin
                            if (resp_buf[5] == "A" && resp_buf[6] == "C" && resp_buf[7] == "K") begin
                                // ACK ricevuto, aspetta completamento
                                resp_index <= 0;
                                state <= ST_WAIT_DONE;
                            end else if (resp_buf[5] == "E" && resp_buf[6] == "R" && resp_buf[7] == "R") begin
                                // Errore
                                if (active_core == 3'd1) begin
                                    c64_load_error <= 1;
                                    c64_load_active <= 0;
                                end else begin
                                    vic20_load_error <= 1;
                                    vic20_load_active <= 0;
                                end
                                state <= ST_IDLE;
                            end
                        end
                    end else if (resp_index < 16) begin
                        resp_buf[resp_index] <= rx_data;
                        resp_index <= resp_index + 1;
                    end
                end
            end
            
            ST_WAIT_DONE: begin
                // Aspetta "LOAD_OK AAAA" o "LOAD_ERR"
                if (rx_valid) begin
                    if (rx_data == 8'h0A) begin
                        // Fine risposta
                        if (resp_index >= 7 &&
                            resp_buf[0] == "L" && resp_buf[1] == "O" &&
                            resp_buf[2] == "A" && resp_buf[3] == "D" &&
                            resp_buf[4] == "_") begin
                            if (resp_buf[5] == "O" && resp_buf[6] == "K") begin
                                // Caricamento completato
                                // Parse end address se presente (LOAD_OK AAAA)
                                if (active_core == 3'd1) begin
                                    c64_load_complete <= 1;
                                    c64_load_active <= 0;
                                    // TODO: parse end address from resp_buf[8:11]
                                end else begin
                                    vic20_load_complete <= 1;
                                    vic20_load_active <= 0;
                                end
                                state <= ST_IDLE;
                            end else if (resp_buf[5] == "E" && resp_buf[6] == "R" && resp_buf[7] == "R") begin
                                // Errore
                                if (active_core == 3'd1) begin
                                    c64_load_error <= 1;
                                    c64_load_active <= 0;
                                end else begin
                                    vic20_load_error <= 1;
                                    vic20_load_active <= 0;
                                end
                                state <= ST_IDLE;
                            end
                        end
                        resp_index <= 0;
                    end else if (resp_index < 16) begin
                        resp_buf[resp_index] <= rx_data;
                        resp_index <= resp_index + 1;
                    end
                end
            end
            
            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
