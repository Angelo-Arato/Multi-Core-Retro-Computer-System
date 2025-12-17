//==============================================================================
// UART CONTROLLER - Con FIFO TX (registri espliciti)
//==============================================================================
// Autore: Angelo Arato
// Data: Novembre 2025
//==============================================================================

module uart_controller #(
    parameter CLK_FREQ  = 50000000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       reset_n,
    
    // Pin fisici
    input  wire       rx,
    output wire       tx,
    
    // Interfaccia RX
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    
    // Interfaccia TX
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output wire       tx_busy
);

localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

//==============================================================================
// UART RX
//==============================================================================

reg [2:0]  rx_state;
reg [15:0] rx_clk_count;
reg [2:0]  rx_bit_index;
reg [7:0]  rx_shift;
reg        rx_sync1, rx_sync2;

localparam RX_IDLE  = 3'd0;
localparam RX_START = 3'd1;
localparam RX_DATA  = 3'd2;
localparam RX_STOP  = 3'd3;

// Sincronizzazione RX (doppio flip-flop)
always @(posedge clk) begin
    rx_sync1 <= rx;
    rx_sync2 <= rx_sync1;
end

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        rx_state <= RX_IDLE;
        rx_clk_count <= 0;
        rx_bit_index <= 0;
        rx_data <= 0;
        rx_valid <= 0;
        rx_shift <= 0;
    end else begin
        rx_valid <= 0;
        
        case (rx_state)
            RX_IDLE: begin
                rx_clk_count <= 0;
                rx_bit_index <= 0;
                
                if (rx_sync2 == 0) begin
                    rx_state <= RX_START;
                end
            end
            
            RX_START: begin
                if (rx_clk_count == (CLKS_PER_BIT - 1) / 2) begin
                    if (rx_sync2 == 0) begin
                        rx_clk_count <= 0;
                        rx_state <= RX_DATA;
                    end else begin
                        rx_state <= RX_IDLE;
                    end
                end else begin
                    rx_clk_count <= rx_clk_count + 1;
                end
            end
            
            RX_DATA: begin
                if (rx_clk_count == CLKS_PER_BIT - 1) begin
                    rx_clk_count <= 0;
                    rx_shift[rx_bit_index] <= rx_sync2;
                    
                    if (rx_bit_index == 7) begin
                        rx_bit_index <= 0;
                        rx_state <= RX_STOP;
                    end else begin
                        rx_bit_index <= rx_bit_index + 1;
                    end
                end else begin
                    rx_clk_count <= rx_clk_count + 1;
                end
            end
            
            RX_STOP: begin
                if (rx_clk_count == CLKS_PER_BIT - 1) begin
                    rx_data <= rx_shift;
                    rx_valid <= 1;
                    rx_state <= RX_IDLE;
                end else begin
                    rx_clk_count <= rx_clk_count + 1;
                end
            end
            
            default: rx_state <= RX_IDLE;
        endcase
    end
end

//==============================================================================
// TX FIFO - 8 registri espliciti (no array per evitare problemi Quartus)
//==============================================================================

reg [7:0]  fifo_0, fifo_1, fifo_2, fifo_3;
reg [7:0]  fifo_4, fifo_5, fifo_6, fifo_7;
reg [2:0]  fifo_wr_ptr;
reg [2:0]  fifo_rd_ptr;
reg [3:0]  fifo_count;

wire fifo_empty = (fifo_count == 0);
wire fifo_full  = (fifo_count == 8);

// Lettura dal FIFO
reg [7:0] fifo_rd_data;
always @(*) begin
    case (fifo_rd_ptr)
        3'd0: fifo_rd_data = fifo_0;
        3'd1: fifo_rd_data = fifo_1;
        3'd2: fifo_rd_data = fifo_2;
        3'd3: fifo_rd_data = fifo_3;
        3'd4: fifo_rd_data = fifo_4;
        3'd5: fifo_rd_data = fifo_5;
        3'd6: fifo_rd_data = fifo_6;
        3'd7: fifo_rd_data = fifo_7;
        default: fifo_rd_data = 8'd0;
    endcase
end

//==============================================================================
// UART TX
//==============================================================================

reg [2:0]  tx_state;
reg [15:0] tx_clk_count;
reg [2:0]  tx_bit_index;
reg [7:0]  tx_shift;
reg        tx_out;

localparam TX_IDLE  = 3'd0;
localparam TX_LOAD  = 3'd1;
localparam TX_START = 3'd2;
localparam TX_DATA  = 3'd3;
localparam TX_STOP  = 3'd4;

assign tx = tx_out;
assign tx_busy = !fifo_empty || (tx_state != TX_IDLE);

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        tx_state <= TX_IDLE;
        tx_clk_count <= 0;
        tx_bit_index <= 0;
        tx_out <= 1;
        tx_shift <= 0;
        fifo_wr_ptr <= 0;
        fifo_rd_ptr <= 0;
        fifo_count <= 0;
        fifo_0 <= 0; fifo_1 <= 0; fifo_2 <= 0; fifo_3 <= 0;
        fifo_4 <= 0; fifo_5 <= 0; fifo_6 <= 0; fifo_7 <= 0;
    end else begin
        
        // Scrittura nel FIFO
        if (tx_start && !fifo_full) begin
            case (fifo_wr_ptr)
                3'd0: fifo_0 <= tx_data;
                3'd1: fifo_1 <= tx_data;
                3'd2: fifo_2 <= tx_data;
                3'd3: fifo_3 <= tx_data;
                3'd4: fifo_4 <= tx_data;
                3'd5: fifo_5 <= tx_data;
                3'd6: fifo_6 <= tx_data;
                3'd7: fifo_7 <= tx_data;
            endcase
            fifo_wr_ptr <= fifo_wr_ptr + 1'd1;
        end
        
        // Gestione contatore FIFO e TX FSM
        case (tx_state)
            TX_IDLE: begin
                tx_out <= 1;
                tx_clk_count <= 0;
                tx_bit_index <= 0;
                
                if (!fifo_empty) begin
                    tx_state <= TX_LOAD;
                end
                
                // Aggiorna contatore per scrittura
                if (tx_start && !fifo_full) begin
                    fifo_count <= fifo_count + 1'd1;
                end
            end
            
            TX_LOAD: begin
                tx_shift <= fifo_rd_data;
                fifo_rd_ptr <= fifo_rd_ptr + 1'd1;
                
                // Aggiorna contatore: -1 per lettura, +1 se anche scrittura
                if (tx_start && !fifo_full) begin
                    fifo_count <= fifo_count;  // +1 -1 = 0
                end else begin
                    fifo_count <= fifo_count - 1'd1;
                end
                
                tx_state <= TX_START;
            end
            
            TX_START: begin
                tx_out <= 0;  // Start bit
                
                // Aggiorna contatore per scrittura
                if (tx_start && !fifo_full) begin
                    fifo_count <= fifo_count + 1'd1;
                end
                
                if (tx_clk_count == CLKS_PER_BIT - 1) begin
                    tx_clk_count <= 0;
                    tx_state <= TX_DATA;
                end else begin
                    tx_clk_count <= tx_clk_count + 1;
                end
            end
            
            TX_DATA: begin
                tx_out <= tx_shift[tx_bit_index];
                
                // Aggiorna contatore per scrittura
                if (tx_start && !fifo_full) begin
                    fifo_count <= fifo_count + 1'd1;
                end
                
                if (tx_clk_count == CLKS_PER_BIT - 1) begin
                    tx_clk_count <= 0;
                    
                    if (tx_bit_index == 7) begin
                        tx_bit_index <= 0;
                        tx_state <= TX_STOP;
                    end else begin
                        tx_bit_index <= tx_bit_index + 1;
                    end
                end else begin
                    tx_clk_count <= tx_clk_count + 1;
                end
            end
            
            TX_STOP: begin
                tx_out <= 1;  // Stop bit
                
                // Aggiorna contatore per scrittura
                if (tx_start && !fifo_full) begin
                    fifo_count <= fifo_count + 1'd1;
                end
                
                if (tx_clk_count == CLKS_PER_BIT - 1) begin
                    tx_clk_count <= 0;
                    tx_state <= TX_IDLE;
                end else begin
                    tx_clk_count <= tx_clk_count + 1;
                end
            end
            
            default: tx_state <= TX_IDLE;
        endcase
    end
end

endmodule
