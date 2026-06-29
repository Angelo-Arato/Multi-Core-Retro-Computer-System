module apple1_rom (
    input  wire        clk,
    input  wire [7:0]  addr,
    output reg  [7:0]  data
);

always @(posedge clk) begin
    // Placeholder ROM.
    // No original Apple I / Woz Monitor ROM bytes are included.
    // Users must provide legally obtained ROM/monitor code if required.
    case (addr)
        8'hFC: data <= 8'h00;
        8'hFD: data <= 8'hFF;
        8'hFE: data <= 8'h00;
        8'hFF: data <= 8'hFF;
        default: data <= 8'hEA; // NOP
    endcase
end

endmodule
