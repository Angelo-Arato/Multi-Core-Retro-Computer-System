//==============================================================================
// APPLE I-COMPATIBLE PLACEHOLDER ROM
//==============================================================================
// This file does not include the original Apple I Woz Monitor ROM.
// It is only a placeholder for synthesis/testing.
// Users must provide legally obtained monitor/ROM code if required.
//==============================================================================

module apple1_rom (
    input  wire       clk,
    input  wire [7:0] addr,
    output reg  [7:0] data
);

always @(posedge clk) begin
    case (addr)
        8'hFC: data <= 8'h00;
        8'hFD: data <= 8'hFF;
        8'hFE: data <= 8'h00;
        8'hFF: data <= 8'hFF;
        default: data <= 8'hEA; // 6502 NOP
    endcase
end

endmodule
