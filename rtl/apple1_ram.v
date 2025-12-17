//==============================================================================
// APPLE I RAM - 2KB usando memoria M9K embedded
//==============================================================================
// Autore: Angelo Arato
// Indirizzo Apple I: $0000-$07FF (2KB - minimo per Woz Monitor)
//==============================================================================

module apple1_ram (
    input  wire        clk,
    // Porta CPU
    input  wire [10:0] addr,      // 2KB = 11 bit
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out,
    input  wire        we
);

// Memoria RAM 2KB (inferisce M9K)
(* ramstyle = "M9K" *) reg [7:0] mem [0:2047];

always @(posedge clk) begin
    if (we)
        mem[addr] <= data_in;
    data_out <= mem[addr];
end

endmodule
