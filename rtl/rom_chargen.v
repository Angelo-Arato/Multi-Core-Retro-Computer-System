//==============================================================================
// CHARACTER ROM - 4KB usando memoria M9K embedded (dual-port)
//==============================================================================
// Autore: Angelo Arato
// Indirizzo C64: $D000-$DFFF (bank switched)
// Porta A: lettura video / Porta B: scrittura loader
//==============================================================================

module rom_chargen (
    input  wire        clk,
    // Porta lettura (video)
    input  wire [11:0] addr_read,
    output reg  [7:0]  data_read,
    // Porta scrittura (ESP32 loader)
    input  wire [11:0] addr_write,
    input  wire [7:0]  data_write,
    input  wire        we
);

// Memoria RAM dual-port (inferisce M9K)
reg [7:0] mem [0:4095];

// Porta A: lettura sincrona (video)
always @(posedge clk) begin
    data_read <= mem[addr_read];
end

// Porta B: scrittura sincrona (loader)
always @(posedge clk) begin
    if (we)
        mem[addr_write] <= data_write;
end

endmodule
