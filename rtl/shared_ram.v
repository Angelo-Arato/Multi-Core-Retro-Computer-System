//==============================================================================
// SHARED RAM - 64KB True Dual Port
//==============================================================================
// Porta A: CPU (Read/Write) - lettura sincrona (1 ciclo di latenza)
// Porta B: Loader (Write) / Video (Read)
//==============================================================================

module shared_ram (
    input  wire        clk,
    
    // Porta A: CPU (Read/Write)
    input  wire [15:0] port_a_addr,
    input  wire [7:0]  port_a_data_in,
    output reg  [7:0]  port_a_data_out,
    input  wire        port_a_we,
    
    // Porta B: Loader/Video (Read/Write)
    input  wire [15:0] port_b_addr,
    input  wire [7:0]  port_b_data_in,
    output reg  [7:0]  port_b_data_out,
    input  wire        port_b_we
);

    // 64KB RAM - Inferisce M9K su MAX10
    (* ramstyle = "M9K" *) reg [7:0] mem [0:65535];

    // Porta A: Read/Write sincrono
    always @(posedge clk) begin
        if (port_a_we)
            mem[port_a_addr] <= port_a_data_in;
        port_a_data_out <= mem[port_a_addr];
    end
    
    // Porta B: Read/Write sincrono
    always @(posedge clk) begin
        if (port_b_we)
            mem[port_b_addr] <= port_b_data_in;
        port_b_data_out <= mem[port_b_addr];
    end

endmodule
