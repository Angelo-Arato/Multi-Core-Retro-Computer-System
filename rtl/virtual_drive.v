//==============================================================================
// VIRTUAL DRIVE - Emula un disk drive via registri I/O
//==============================================================================
// Mappa I/O: $DE00-$DE1F (C64 I/O Expansion area 1)
//
// $DE00 (W): Command - scrivere qui avvia l'operazione
//            $01 = LOAD file
//            $00 = Cancel/Reset
// $DE00 (R): Status
//            Bit 7: Busy (operazione in corso)
//            Bit 6: Error
//            Bit 5: Done (operazione completata)
//            Bit 0-4: Error code
//
// $DE01-$DE02 (RW): Filename pointer in RAM (low/high)
// $DE03 (RW): Filename length (1-16)
// $DE04 (RW): Device number (default 8)
// $DE05 (RW): Secondary address (0=load at file address, 1=load at $0801)
// $DE06-$DE07 (R): End address after LOAD (low/high)
//
// Il C64 può usare:
//   SYS 56832 - se c'è una routine LOAD helper installata
// Oppure da BASIC:
//   POKE 56833,<FNADDR:POKE 56834,>FNADDR  (indirizzo filename)
//   POKE 56835,FNLEN                        (lunghezza)
//   POKE 56836,8                            (device)
//   POKE 56837,0                            (secondary)
//   POKE 56832,1                            (GO!)
//   (aspetta PEEK(56832)<128)
//   RUN
//==============================================================================

module virtual_drive (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        enable,         // Core attivo
    
    // CPU bus interface
    input  wire [4:0]  addr,           // $DE00-$DE1F (solo 5 bit bassi)
    input  wire [7:0]  data_in,        // Dati dalla CPU
    output reg  [7:0]  data_out,       // Dati verso CPU
    input  wire        we,             // Write enable
    input  wire        cs,             // Chip select ($DE00-$DE1F)
    
    // RAM read interface (per leggere filename)
    output reg  [15:0] ram_read_addr,
    input  wire [7:0]  ram_read_data,
    output reg         ram_read_req,   // Richiesta lettura
    
    // LOAD request output (verso load_handler)
    output reg         load_req,
    output reg [127:0] load_filename,
    output reg  [3:0]  load_filename_len,
    output reg  [7:0]  load_device,
    output reg         load_secondary,
    
    // LOAD response input (da load_handler)
    input  wire        load_active,
    input  wire        load_complete,
    input  wire        load_error,
    input  wire [15:0] load_end_addr
);

//==============================================================================
// REGISTRI
//==============================================================================
reg [7:0]  reg_status;       // $DE00 read
reg [15:0] reg_fn_ptr;       // $DE01-$DE02: puntatore filename
reg [3:0]  reg_fn_len;       // $DE03: lunghezza filename (1-16)
reg [7:0]  reg_device;       // $DE04: device number
reg        reg_secondary;    // $DE05: secondary address
reg [15:0] reg_end_addr;     // $DE06-$DE07: end address

// Status bits
localparam ST_BUSY  = 7;
localparam ST_ERROR = 6;
localparam ST_DONE  = 5;

//==============================================================================
// STATE MACHINE
//==============================================================================
localparam S_IDLE       = 4'd0;
localparam S_READ_FN    = 4'd1;  // Leggi filename dalla RAM
localparam S_WAIT_FN    = 4'd2;  // Aspetta dato dalla RAM
localparam S_SEND_REQ   = 4'd3;  // Invia richiesta
localparam S_WAIT_ACK   = 4'd4;  // Aspetta ACK
localparam S_WAIT_DONE  = 4'd5;  // Aspetta completamento
localparam S_DONE       = 4'd6;

reg [3:0] state;
reg [3:0] fn_index;

//==============================================================================
// REGISTRO LETTURA/SCRITTURA
//==============================================================================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        reg_fn_ptr <= 16'h0000;
        reg_fn_len <= 4'd0;
        reg_device <= 8'd8;
        reg_secondary <= 1'b0;
        reg_end_addr <= 16'h0000;
        reg_status <= 8'h00;
        state <= S_IDLE;
        load_req <= 0;
        load_filename <= 128'd0;
        load_filename_len <= 4'd0;
        load_device <= 8'd8;
        load_secondary <= 0;
        fn_index <= 0;
        ram_read_req <= 0;
        ram_read_addr <= 16'h0000;
    end else begin
        // Default: clear one-shot signals
        load_req <= 0;
        ram_read_req <= 0;
        
        // Aggiorna status da load_handler
        if (load_complete) begin
            reg_status[ST_DONE] <= 1;
            reg_status[ST_BUSY] <= 0;
            reg_end_addr <= load_end_addr;
            state <= S_DONE;
        end
        if (load_error) begin
            reg_status[ST_ERROR] <= 1;
            reg_status[ST_BUSY] <= 0;
            state <= S_DONE;
        end
        
        // Scrittura registri dalla CPU
        if (enable && cs && we) begin
            case (addr[4:0])
                5'h00: begin  // Command register
                    if (data_in == 8'h01 && state == S_IDLE) begin
                        // START LOAD
                        reg_status <= 8'h80;  // Busy
                        fn_index <= 0;
                        state <= S_READ_FN;
                    end
                    else if (data_in == 8'h00) begin
                        // Reset/Cancel
                        reg_status <= 8'h00;
                        state <= S_IDLE;
                    end
                end
                5'h01: reg_fn_ptr[7:0] <= data_in;
                5'h02: reg_fn_ptr[15:8] <= data_in;
                5'h03: reg_fn_len <= (data_in > 16) ? 4'd16 : data_in[3:0];
                5'h04: reg_device <= data_in;
                5'h05: reg_secondary <= data_in[0];
            endcase
        end
        
        // State machine
        case (state)
            S_IDLE: begin
                // Aspetta comando
            end
            
            S_READ_FN: begin
                // Richiedi lettura carattere filename dalla RAM
                ram_read_addr <= reg_fn_ptr + fn_index;
                ram_read_req <= 1;
                state <= S_WAIT_FN;
            end
            
            S_WAIT_FN: begin
                // Aspetta 1 ciclo per la RAM, poi memorizza
                // Il dato è disponibile su ram_read_data
                case (fn_index)
                    4'd0:  load_filename[127:120] <= ram_read_data;
                    4'd1:  load_filename[119:112] <= ram_read_data;
                    4'd2:  load_filename[111:104] <= ram_read_data;
                    4'd3:  load_filename[103:96]  <= ram_read_data;
                    4'd4:  load_filename[95:88]   <= ram_read_data;
                    4'd5:  load_filename[87:80]   <= ram_read_data;
                    4'd6:  load_filename[79:72]   <= ram_read_data;
                    4'd7:  load_filename[71:64]   <= ram_read_data;
                    4'd8:  load_filename[63:56]   <= ram_read_data;
                    4'd9:  load_filename[55:48]   <= ram_read_data;
                    4'd10: load_filename[47:40]   <= ram_read_data;
                    4'd11: load_filename[39:32]   <= ram_read_data;
                    4'd12: load_filename[31:24]   <= ram_read_data;
                    4'd13: load_filename[23:16]   <= ram_read_data;
                    4'd14: load_filename[15:8]    <= ram_read_data;
                    4'd15: load_filename[7:0]     <= ram_read_data;
                endcase
                
                if (fn_index >= reg_fn_len - 1) begin
                    // Filename completo
                    load_filename_len <= reg_fn_len;
                    load_device <= reg_device;
                    load_secondary <= reg_secondary;
                    state <= S_SEND_REQ;
                end else begin
                    fn_index <= fn_index + 1;
                    state <= S_READ_FN;
                end
            end
            
            S_SEND_REQ: begin
                // Invia richiesta LOAD
                load_req <= 1;
                state <= S_WAIT_ACK;
            end
            
            S_WAIT_ACK: begin
                // Aspetta che load_handler accetti
                if (load_active) begin
                    state <= S_WAIT_DONE;
                end
            end
            
            S_WAIT_DONE: begin
                // Aspetta completamento (gestito sopra)
            end
            
            S_DONE: begin
                // Completato, aspetta reset o nuovo comando
                // Lo status rimane settato finché non viene letto/resettato
            end
        endcase
    end
end

//==============================================================================
// LETTURA REGISTRI
//==============================================================================
always @(*) begin
    data_out = 8'hFF;
    if (cs) begin
        case (addr[4:0])
            5'h00: data_out = reg_status;
            5'h01: data_out = reg_fn_ptr[7:0];
            5'h02: data_out = reg_fn_ptr[15:8];
            5'h03: data_out = {4'h0, reg_fn_len};
            5'h04: data_out = reg_device;
            5'h05: data_out = {7'h00, reg_secondary};
            5'h06: data_out = reg_end_addr[7:0];
            5'h07: data_out = reg_end_addr[15:8];
            default: data_out = 8'hFF;
        endcase
    end
end

endmodule
