//==============================================================================
// ZX Spectrum RAM 48KB - Inferisce M9K Memory Blocks
//==============================================================================
// Pattern specifico per MAX10 M9K inference
// Port A: CPU + Program Loader (multiplexed)
// Port B: Video (read only)
//==============================================================================

module zx_ram_48k (
    input  wire        clk,
    
    // Port A - CPU
    input  wire [15:0] addr_a,
    input  wire [7:0]  data_a,
    input  wire        we_a,
    output reg  [7:0]  q_a,
    
    // Port B - Video (read only)
    input  wire [15:0] addr_b,
    output reg  [7:0]  q_b,
    
    // Port C - Program Loader (shared with Port A)
    input  wire [15:0] load_addr,
    input  wire [7:0]  load_data,
    input  wire        load_we
);

// 48KB = 49152 bytes - diviso in blocchi per M9K
(* ramstyle = "M9K" *) reg [7:0] mem [0:49151];

// Mux per Port A: loader ha priorità
wire [15:0] port_a_addr = load_we ? load_addr : addr_a;
wire [7:0]  port_a_data = load_we ? load_data : data_a;
wire        port_a_we   = load_we ? 1'b1 : we_a;

// Port A - CPU read/write + Loader
always @(posedge clk) begin
    if (port_a_we)
        mem[port_a_addr] <= port_a_data;
    q_a <= mem[port_a_addr];
end

// Port B - Video read only
always @(posedge clk) begin
    q_b <= mem[addr_b];
end

endmodule

//==============================================================================
// ZX Spectrum ROM 16KB - Inferisce M9K Memory Blocks
//==============================================================================

module zx_rom_16k (
    input  wire        clk,
    
    // Port A - CPU read
    input  wire [13:0] addr_a,
    output reg  [7:0]  q_a,
    
    // Port B - Loader write
    input  wire [13:0] addr_b,
    input  wire [7:0]  data_b,
    input  wire        we_b
);

(* ramstyle = "M9K" *) reg [7:0] mem [0:16383];

// Port A - CPU read
always @(posedge clk) begin
    q_a <= mem[addr_a];
end

// Port B - Loader write
always @(posedge clk) begin
    if (we_b)
        mem[addr_b] <= data_b;
end

endmodule
